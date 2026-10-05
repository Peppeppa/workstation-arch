// Displays for Appearance (non-visual). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// Two owners, one small interface between them:
//   - the host's monitor configuration (mode, position, default scale) is
//     declarative: hyprland_monitors in host_vars/<host>.yml, rendered by
//     Ansible into ~/.config/hypr/conf/monitors.lua. "Change" opens THAT
//     file (the repository's host_vars - never the generated Lua) in
//     Neovim; ./bootstrap.sh applies an edit.
//   - the display SCALE picked in Appearance is runtime state: one line per
//     output in ~/.config/workstation/display-scale.lua, written only here
//     (atomically), never by Ansible. monitors.lua reads it (pcall dofile,
//     like the theme colors) and lets it win over the host default for
//     that output; "Default" removes the line again. Applied by
//     `hyprctl reload` (Hyprland re-runs its config) - no watcher.
// Outputs: one `hyprctl monitors -j` per open and after each change.

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Scope {
    id: model

    required property string configFile     // host_vars/<host>.yml in the repository checkout
    required property var terminal          // argv of the terminal (hyprland_terminal)

    readonly property var scales: [1, 1.25, 1.6, 2, 4]
    property var monitors: []
    property var overrides: ({})            // output -> scale (the runtime file)

    function refresh() {
        if (!monitorsProc.running) monitorsProc.running = true;
    }

    function isCurrent(m, s) {
        return Math.abs(m.scale - s) < 0.01;
    }

    // Output names come from Hyprland; anything unusual is never written
    // into a file that Hyprland executes.
    function safeName(name) {
        return /^[A-Za-z0-9._-]+$/.test(name);
    }

    function write(next) {
        const lines = Object.keys(next).filter(safeName).sort()
            .map(n => "    [\"" + n + "\"] = " + Number(next[n]) + ",");
        overrides = next;
        store.setText("-- Display scale per output, chosen in Appearance (Quickshell) - runtime\n"
                      + "-- state, read by ~/.config/hypr/conf/monitors.lua. Not managed by Ansible.\n"
                      + "return {\n" + lines.join("\n") + (lines.length ? "\n" : "") + "}\n");
    }

    function setScale(name, s) {
        if (!safeName(name) || scales.indexOf(s) === -1) return;
        const next = Object.assign({}, overrides);
        next[name] = s;
        write(next);
    }

    function resetScale(name) {
        const next = Object.assign({}, overrides);
        delete next[name];
        write(next);
    }

    function openConfig() {
        Quickshell.execDetached(["systemd-run", "--user", "--quiet", "--collect", "--"]
            .concat(terminal).concat(["-e", "nvim", "+silent! /^hyprland_monitors:", configFile]));
    }

    function parse(text) {
        const out = {};
        const re = /\["([A-Za-z0-9._-]+)"\]\s*=\s*([0-9.]+)/g;
        let m;
        while ((m = re.exec(text)) !== null) out[m[1]] = parseFloat(m[2]);
        return out;
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/workstation/display-scale.lua"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onSaved: reloadProc.running = true
        onSaveFailed: error => Log.warn("appearance", "cannot save " + path + " (" + error + ") - scale not changed")
    }

    Component.onCompleted: {
        overrides = parse(store.text());
        refresh();
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        onExited: model.refresh()
    }

    Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    model.monitors = JSON.parse(text);
                } catch (e) {
                    model.monitors = [];
                    Log.warn("appearance", "`hyprctl monitors -j` returned no JSON - no display information");
                }
            }
        }
    }
}
