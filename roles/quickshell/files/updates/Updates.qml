pragma Singleton

// System updates - the shared model of the bar's update icon and the updater
// dialog (UpdaterDialog.qml). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. Deployed only with the host
// capability recovery_enabled (system-update is its update transaction).
// See docs/feature-architecture.md "System updates".
//
// The check: `workstation-checkupdates` (roles/recovery: pacman-contrib's
// checkupdates against a private copy of the sync databases, as the user -
// the system's databases are never touched, no partial upgrade). Official
// repositories only; AUR/Flatpak are not counted. It runs once when this
// singleton is first used (the bar's icon: at bar start), then every 60
// minutes (one single-shot-like Timer - nothing else wakes up), when the
// dialog opens, and after an update finished. Never while an update runs.
//
// status: "unknown" (never checked) | "ok" (packages is the fresh list) |
// "offline" | "error". A failed check never re-presents an older list as
// fresh: packages is emptied, the last good result stays only as lastGood
// ({count, at}) for the tooltip, marked as old.

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    readonly property int intervalMs: 60 * 60 * 1000

    property string status: "unknown"
    property var packages: []              // [{name, from, to}] - only with status "ok"
    property string message: ""            // why offline/error
    property var checkedAt: null           // Date of the last check (any outcome)
    property var lastGood: null            // {count, at} of the last successful check
    readonly property bool checking: proc.running
    readonly property int count: status === "ok" ? packages.length : 0

    property bool updating: false          // our system-update terminal runs
    property var dialog: null              // UpdaterDialog registers itself

    // The update terminal is a transient user unit (UpdaterDialog.launch);
    // whether it still runs is asked from systemd, on demand only.
    readonly property string unit: "workstation-system-update.service"

    function check() {
        if (proc.running) return;
        if (updating) {
            syncUnit();             // a closed terminal must not block checks forever
            return;
        }
        proc.running = true;
    }

    // updating := the unit is active; then a check if it just ended.
    function syncUnit() {
        if (!unitProc.running) unitProc.running = true;
    }

    function openDialog() {
        if (dialog) dialog.open();
    }

    // workstation-checkupdates' JSON line -> the model's fields. Pure (state
    // in, new state out) so tests can run it.
    function parseResult(text, now) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        if (!d || typeof d.status !== "string")
            return { status: "error", packages: [], message: "the update check returned no result", lastGood: null };
        if (d.status === "ok") {
            const pkgs = Array.isArray(d.packages) ? d.packages.filter(p => p && typeof p.name === "string") : [];
            return { status: "ok", packages: pkgs, message: "", lastGood: { count: pkgs.length, at: now } };
        }
        if (d.status === "offline" || d.status === "error")
            return { status: d.status, packages: [], message: String(d.message || ""), lastGood: null };
        return { status: "error", packages: [], message: "unknown status " + d.status, lastGood: null };
    }

    function apply(r) {
        status = r.status;
        packages = r.packages;
        message = r.message;
        checkedAt = new Date();
        if (r.lastGood) lastGood = r.lastGood;
        if (r.status === "error") Log.warn("updates", "update check failed: " + r.message);
    }

    // Bar icon: shown with at least one pending official update (fresh), or
    // dimmed while the check fails but the last good one had updates, or
    // while an update runs.
    readonly property bool iconVisible: updating || count > 0
        || ((status === "offline" || status === "error") && lastGood !== null && lastGood.count > 0)

    function hhmm(d) {
        return d ? Qt.formatTime(d, "HH:mm") : "";
    }

    readonly property string tooltip: {
        if (updating) return "Systemupdate läuft im Terminal";
        if (status === "ok") {
            const names = packages.slice(0, 8).map(p => p.name).join(", ") + (packages.length > 8 ? ", …" : "");
            return (count === 1 ? "1 Update verfügbar" : count + " Updates verfügbar") + "\n" + names;
        }
        const why = status === "offline" ? "offline" : "Prüfung fehlgeschlagen";
        return "Updates: " + why + (lastGood ? " - zuletzt " + lastGood.count + " um " + hhmm(lastGood.at) + " (veraltet)" : "");
    }

    Timer {
        interval: root.intervalMs
        repeat: true
        running: true
        onTriggered: root.check()
    }

    Component.onCompleted: check()

    Process {
        id: unitProc
        command: ["systemctl", "--user", "is-active", "--quiet", root.unit]
        onExited: code => {
            const was = root.updating;
            root.updating = code === 0;
            if (was && !root.updating) root.check();
        }
    }

    Process {
        id: proc
        command: ["/usr/local/bin/workstation-checkupdates"]
        stdout: StdioCollector { id: out }
        onExited: (code, exitStatus) => root.apply(root.parseResult(code === 0 ? out.text : "", new Date()))
    }
}
