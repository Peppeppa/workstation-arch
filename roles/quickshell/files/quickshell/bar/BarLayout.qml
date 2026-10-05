pragma Singleton

// Bar layout = runtime user state (RICE v1). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// The widget registry (which widget ids exist, where their QML lives,
// whether this host has them) and the user's arrangement of them in three
// zones. The arrangement lives in ~/.config/workstation/bar-layout.json:
//   { "version": 1, "layout": { "left": [{ "id": "workspaces" }], "center": [...], "right": [...] },
//     "settings": { "background": "solid" } }
// Only widget ids (+ plain per-widget values) and the bar settings -
// nothing executable.
//
// - read once at startup (no watcher); every change is made here (drag &
//   drop in Bar.qml -> move()) and written back at once, atomically
// - unknown ids and duplicates are ignored (and dropped on the next write);
//   ids of widgets this host has switched off (feature flag false) are kept
//   in the file, so they return to their place when switched on again
// - migration: the former standalone "coffee" and "theme" widgets are one
//   "visuals" widget now; a stored layout with either of them gets
//   "visuals" at the place of the first one (the other is dropped), every
//   other entry stays as it was, and the migrated layout is written once
// - a widget missing from the file is shown at the end of its default zone
// - missing/broken file -> the shipped default (bar/default-layout.json);
//   `qs ipc call bar resetLayout` restores it (the arrangement only -
//   settings stay)
// - settings.background: "solid" (theme background, the default) or
//   "transparent"; switched at runtime with
//   `qs ipc call bar setBackground solid|transparent` (applied at once,
//   written atomically) - the interface a later settings menu uses
// Ansible only creates the file when it does not exist; bootstrap never
// touches an existing one.

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    readonly property var zoneNames: ["left", "center", "right"]

    // The registry. Core widgets are imported by Bar.qml (always deployed);
    // feature-only widgets (deployed only with their flag) are loaded by
    // path, relative to Bar.qml (bar/).
    readonly property var widgets: [
        { id: "workspaces", available: true },
        { id: "clock", available: true },
        { id: "tray", path: "widgets/Tray/Widget.qml", available: BarFeatures.tray },
        { id: "connectivity", available: true },
        { id: "bluetooth", path: "widgets/Bluetooth/Widget.qml", available: BarFeatures.bluetooth },
        { id: "audio", available: true },
        { id: "power", available: true },
        { id: "visuals", available: true }
    ]
    // Retired ids and the widget that replaced them (see sanitize).
    readonly property var renamed: ({ coffee: "visuals", theme: "visuals" })
    readonly property var availableWidgets: widgets.filter(w => w.available)

    property var defaultLayout: emptyLayout()
    property var raw: emptyLayout()            // what is (or will be) in the file

    // What the bar shows: {left: [id...], center: [...], right: [...]}.
    readonly property var zones: normalize(raw)

    readonly property var backgrounds: ["solid", "transparent"]
    readonly property string background: raw.settings.background

    function emptyLayout() {
        return { version: 1, layout: { left: [], center: [], right: [] }, settings: { background: "solid" } };
    }

    function known(id) {
        return widgets.some(w => w.id === id);
    }

    function available(id) {
        return availableWidgets.some(w => w.id === id);
    }

    function isPlaced(id) {
        return zoneNames.some(z => zones[z].indexOf(id) !== -1);
    }

    // Keep only well-formed entries: {id: <known id>, <key>: <plain value>...}.
    function cleanEntry(entry) {
        let e = typeof entry === "string" ? { id: entry } : entry;
        if (e && typeof e === "object" && typeof e.id === "string" && renamed[e.id] !== undefined)
            e = { id: renamed[e.id] };
        if (!e || typeof e !== "object" || typeof e.id !== "string" || !known(e.id)) return null;
        const out = { id: e.id };
        for (const k in e) {
            const v = e[k];
            if (k !== "id" && (typeof v === "string" || typeof v === "number" || typeof v === "boolean"))
                out[k] = v;
        }
        return out;
    }

    // File content -> a clean layout (every zone an array of clean entries,
    // each known id at most once). null if it is not a layout at all.
    function sanitize(data) {
        if (!data || typeof data !== "object" || !data.layout || typeof data.layout !== "object") return null;
        const seen = {};
        const out = emptyLayout();
        for (const z of zoneNames) {
            const list = Array.isArray(data.layout[z]) ? data.layout[z] : [];
            for (const entry of list) {
                const e = cleanEntry(entry);
                if (e === null || seen[e.id]) continue;
                seen[e.id] = true;
                out.layout[z].push(e);
            }
        }
        const settings = data.settings && typeof data.settings === "object" ? data.settings : {};
        if (backgrounds.indexOf(settings.background) !== -1) out.settings.background = settings.background;
        return out;
    }

    function defaultZoneOf(id) {
        for (const z of zoneNames)
            if (defaultLayout.layout[z].some(e => e.id === id)) return z;
        return "right";
    }

    function normalize(layout) {
        const zones = { left: [], center: [], right: [] };
        const seen = {};
        for (const z of zoneNames) {
            for (const e of layout.layout[z]) {
                if (!available(e.id) || seen[e.id]) continue;
                seen[e.id] = true;
                zones[z].push(e.id);
            }
        }
        for (const w of availableWidgets)
            if (!seen[w.id]) zones[defaultZoneOf(w.id)].push(w.id);
        return zones;
    }

    // Move widget `id` into `zone`, before `beforeId` ("" = at the end).
    // Works on the stored layout, so entries of switched-off widgets keep
    // their places. Writes the file. Returns whether anything changed.
    function move(id, zone, beforeId) {
        if (!available(id) || zoneNames.indexOf(zone) === -1 || id === beforeId) return false;
        const next = JSON.parse(JSON.stringify(raw));
        let entry = { id: id };
        for (const z of zoneNames) {
            const i = next.layout[z].findIndex(e => e.id === id);
            if (i !== -1) entry = next.layout[z].splice(i, 1)[0];
        }
        const target = next.layout[zone];
        const at = beforeId === "" ? -1 : target.findIndex(e => e.id === beforeId);
        if (at === -1) target.push(entry);
        else target.splice(at, 0, entry);
        if (JSON.stringify(next) === JSON.stringify(raw)) return false;
        raw = next;
        save();
        return true;
    }

    function reset() {
        const next = JSON.parse(JSON.stringify(defaultLayout));
        next.settings = raw.settings;
        raw = next;
        save();
    }

    // Returns "" on success, else the reason.
    function setBackground(mode) {
        if (backgrounds.indexOf(mode) === -1) return "unknown background '" + mode + "' (" + backgrounds.join("|") + ")";
        if (raw.settings.background === mode) return "";
        const next = JSON.parse(JSON.stringify(raw));
        next.settings.background = mode;
        raw = next;
        save();
        return "";
    }

    function save() {
        stateFile.setText(JSON.stringify(raw, null, 2) + "\n");
    }

    FileView {
        id: defaultFile
        path: decodeURIComponent(Qt.resolvedUrl("default-layout.json").toString().replace("file://", ""))
        blockLoading: true
    }

    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/workstation/bar-layout.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => Log.warn("bar", "cannot save " + path + " (" + error + ") - the change is lost at the next start")
    }

    function parse(text) {
        try {
            return sanitize(JSON.parse(text));
        } catch (e) {
            return null;
        }
    }

    Component.onCompleted: {
        defaultLayout = parse(defaultFile.text()) || emptyLayout();
        const stored = stateFile.text();
        raw = parse(stored) || JSON.parse(JSON.stringify(defaultLayout));
        if (stored.trim() !== "" && parse(stored) === null)
            Log.warn("bar", "bar-layout.json is not a valid layout - showing the default (the file is rewritten on the next change)");
        else if (/"id"\s*:\s*"(coffee|theme)"/.test(stored))
            save();         // the coffee/theme -> visuals migration, written once
    }

    IpcHandler {
        target: "bar"

        // Restore the shipped default arrangement.
        function resetLayout(): void {
            root.reset();
        }

        // The current stored layout (JSON).
        function layout(): string {
            return JSON.stringify(root.raw);
        }

        // Bar background: "solid" | "transparent" (persistent, applied at once).
        function setBackground(mode: string): string {
            const err = root.setBackground(mode);
            if (err !== "") Log.warn("bar", "setBackground: " + err);
            return err === "" ? root.background : "error: " + err;
        }

        function getBackground(): string {
            return root.background;
        }
    }
}
