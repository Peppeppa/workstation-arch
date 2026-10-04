// Applications - the app model (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// Moved unchanged from the former Launcher.qml. App data comes entirely
// from Quickshell's DesktopEntries (XDG .desktop parsing) - no app list of
// our own. Shown is an entry that passes (docs/DESIGN_SYSTEM.md "Launcher"):
//   1. its own metadata: NoDisplay=true / Hidden=true are dropped
//      (Quickshell parses both; Hidden entries never reach `applications`).
//      Quickshell 0.3.1 does not evaluate OnlyShowIn/NotShowIn/TryExec -
//      the few entries that rely on them are covered by rule 3.
//   2. category rule: settings dialogs and debuggers are not apps one
//      launches (hiddenCategories) - this also keeps the NetworkManager
//      connection editor (Settings) out: it is the OS menu's Network entry.
//   3. a small denylist of desktop-file ids for technical tools that
//      dependencies bring along (hiddenIds) - packages stay installed,
//      only their launcher entry is hidden.

import QtQuick
import Quickshell

Scope {
    id: model

    readonly property int maxResults: 8

    // Rule 2: entries in any of these categories are system configuration
    // or debugging helpers (e.g. Qt's D-Bus viewer).
    readonly property var hiddenCategories: ["Settings", "DesktopSettings", "Debugger"]

    // Rule 3: desktop-file ids (file name without .desktop) of technical
    // tools pulled in by dependencies, with the package that brings them.
    readonly property var hiddenIds: [
        "avahi-discover", "bssh", "bvnc",            // avahi (needed by CUPS, PipeWire-Pulse, Flatpak/ostree)
        "lstopo",                                    // hwloc (via onetbb <- appstream <- Flatpak)
        "designer", "linguist", "assistant",         // qt6-tools (needed by VirtualBox)
        "qv4l2", "qvidcap"                           // v4l-utils (needed by ffmpeg)
    ]

    function shown(e) {
        return !e.noDisplay
            && hiddenIds.indexOf(e.id) === -1
            && !(e.categories || []).some(c => hiddenCategories.indexOf(c) !== -1);
    }

    // Name matches first, then generic name, then keywords; empty query:
    // alphabetical. Only the name is shown - the rest only helps finding.
    function search(q) {
        const apps = DesktopEntries.applications.values.filter(e => model.shown(e));
        if (q.length === 0) {
            return apps.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, maxResults);
        }

        const needle = q.toLowerCase();
        const scored = [];
        for (const e of apps) {
            const name = (e.name || "").toLowerCase();
            const generic = (e.genericName || "").toLowerCase();
            const keywords = (e.keywords || []).join(" ").toLowerCase();
            let score = -1;
            if (name.startsWith(needle)) score = 0;
            else if (name.includes(needle)) score = 1;
            else if (generic.includes(needle)) score = 2;
            else if (keywords.includes(needle)) score = 3;
            if (score >= 0) scored.push({ entry: e, score: score });
        }
        scored.sort((a, b) => a.score - b.score || a.entry.name.localeCompare(b.entry.name));
        return scored.slice(0, maxResults).map(s => s.entry);
    }
}
