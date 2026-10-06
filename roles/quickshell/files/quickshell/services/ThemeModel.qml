// Shared theme/wallpaper model (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// Theme sources (Appearance -> Theme -> Import): `theme import <url> <mode>`
// and `theme remove <id>` - the helper clones/compiles/removes and edits the
// repository's themes/sources.yml; nothing here touches files itself.
//
// The QML side of the ONE theme implementation, the `theme` helper
// (roles/theme): `theme status --json` for the lists (the theme
// directories are the registry), `theme select` / `theme wallpaper set` /
// `theme text-size` to change something. Used by the bar's theme popup and the Appearance
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
    // The desktop text size (px) and its presets - see Fonts.qml.
    readonly property var textSizes: status && status.text_sizes ? status.text_sizes : []
    readonly property int textSize: status && status.state ? parseInt(status.state.text_size) || 0 : 0
    // Themes from repositories (themes/sources.yml): [{id, name, url, commit,
    // mode, bundled, installed, selected}]
    readonly property var sources: status && status.sources ? status.sources : []
    // Import / remove: one at a time; sourceMessage = the last result.
    readonly property bool sourceBusy: sourceProc.running
    property string sourceMessage: ""
    property bool sourceFailed: false

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
        actionProc.what = "theme";
        actionProc.running = true;
    }

    function setTextSize(px) {
        if (px === textSize || actionProc.running) return;
        actionProc.command = [helper, "text-size", String(px)];
        actionProc.what = "appearance";
        actionProc.running = true;
    }

    function setWallpaper(file) {
        if (actionProc.running) return;
        actionProc.command = [helper, "wallpaper", "set", file];
        actionProc.what = "wallpaper";
        actionProc.running = true;
    }

    function importTheme(url, mode) {
        if (sourceProc.running) return;
        sourceMessage = "Importing " + url + " ...";
        sourceFailed = false;
        sourceProc.command = [helper, "import", url, mode];
        sourceProc.running = true;
    }

    function removeTheme(id) {
        if (sourceProc.running) return;
        sourceMessage = "";
        sourceFailed = false;
        sourceProc.command = [helper, "remove", id];
        sourceProc.running = true;
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
        stderr: StdioCollector { id: statusErr }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    model.status = JSON.parse(text);
                } catch (e) {
                    model.errorText = "theme helper returned no status";
                    Log.warn("theme", "`theme status --json` returned no JSON - is ~/.local/bin/theme deployed?");
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) Log.warn("theme", "`theme status` failed (exit " + exitCode + "): " + Log.firstLine(statusErr.text));
            if (model.refreshPending) {
                model.refreshPending = false;
                running = true;
            }
        }
    }

    Process {
        id: sourceProc
        stdout: StdioCollector { id: sourceOut }
        stderr: StdioCollector { id: sourceErr }
        onExited: exitCode => {
            model.sourceFailed = exitCode !== 0;
            if (exitCode !== 0) {
                model.sourceMessage = sourceErr.text.trim().replace(/^theme: /, "") || "failed (exit " + exitCode + ")";
                Log.warn("theme", "`" + command.slice(1).join(" ") + "` failed: " + Log.firstLine(sourceErr.text));
            } else if (command[1] === "import") {
                try {
                    const r = JSON.parse(sourceOut.text);
                    model.sourceMessage = "Added " + r.name + " (" + r.mode + ")"
                        + (r.ignored.length ? " - not used: " + r.ignored.join(", ") : "");
                } catch (e) {
                    model.sourceMessage = "Added";
                }
            } else {
                model.sourceMessage = "Removed";
            }
            model.refresh();
        }
    }

    Process {
        id: actionProc
        property string what: "theme"
        stderr: StdioCollector { id: actionErr }
        onExited: exitCode => {
            model.errorText = exitCode === 0 ? "" : actionErr.text.trim();
            if (exitCode !== 0)
                Log.warn(what, "`" + command.slice(1).join(" ") + "` failed (exit " + exitCode + "): " + Log.firstLine(actionErr.text));
            model.refresh();
        }
    }
}
