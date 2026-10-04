// Shared theme/wallpaper model (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// The QML side of the ONE theme implementation, the `theme` helper
// (roles/theme): `theme status --json` for the lists (the theme
// directories are the registry), `theme select` / `theme wallpaper set`
// to change something. Used by the bar's theme popup and the Appearance
// window alike - each creates its own instance only while it is open.
// Every applied change (from here, the bar icon, the CLI) ends in the
// helper's `qs ipc call theme reload`, which reloads Colors: that is the
// refresh event. No watcher, no timer.

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Scope {
    id: model

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/theme"

    // {state: {dark, light, mode}, dark: [{id, name}], light: [...],
    //  wallpaper: {theme, selected, backgrounds: [{file, path, animated}]}}
    property var status: null
    property string errorText: ""
    readonly property bool busy: actionProc.running
    readonly property var wallpaper: status ? status.wallpaper : null
    readonly property var backgrounds: wallpaper ? wallpaper.backgrounds : []

    // A request while a status run is in flight is not dropped: that run may
    // have read the state before the change, so one more run follows it.
    property bool refreshPending: false

    function refresh() {
        if (statusProc.running) refreshPending = true;
        else statusProc.running = true;
    }

    function options(slot) {
        return status ? status[slot] : [];
    }

    function selectedId(slot) {
        return status && status.state ? status.state[slot] : "";
    }

    function nameOf(slot, id) {
        const hit = options(slot).find(t => t.id === id);
        return hit ? hit.name : id;
    }

    function activeMode() {
        return status && status.state ? status.state.mode : "";
    }

    function select(slot, id) {
        if (id === selectedId(slot) || actionProc.running) return;
        actionProc.command = [helper, "select", slot, id];
        actionProc.running = true;
    }

    function setWallpaper(file) {
        if (actionProc.running) return;
        actionProc.command = [helper, "wallpaper", "set", file];
        actionProc.running = true;
    }

    Component.onCompleted: refresh()

    Connections {
        target: Colors
        function onDataChanged() {
            model.refresh();
        }
    }

    Process {
        id: statusProc
        command: [model.helper, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    model.status = JSON.parse(text);
                } catch (e) {
                    model.errorText = "theme helper returned no status";
                }
            }
        }
        onExited: {
            if (model.refreshPending) {
                model.refreshPending = false;
                running = true;
            }
        }
    }

    Process {
        id: actionProc
        stderr: StdioCollector { id: actionErr }
        onExited: exitCode => {
            model.errorText = exitCode === 0 ? "" : actionErr.text.trim();
            model.refresh();
        }
    }
}
