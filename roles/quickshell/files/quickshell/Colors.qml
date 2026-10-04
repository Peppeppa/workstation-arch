// Central color source for every Quickshell component (see
// docs/DESIGN_SYSTEM.md). Managed by Ansible - do not edit by hand.
//
// Components read these semantic roles only - never a hex literal, never
// a theme name, never their own dark/light branches.
//
// The values come from the active theme, rendered by the `theme` helper
// (roles/theme) into ~/.config/workstation/theme/colors.json. Read once
// at startup (blocking, so the first frame is already themed) and again
// only when the helper calls `qs ipc call theme reload` after a switch -
// no file watcher, no polling, and no Quickshell reload, so runtime state
// (coffee mode, open menus) survives a theme change. Every binding below
// updates in place.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var data: ({})
    readonly property var c: data.colors || ({})

    readonly property string themeId: data.id || ""
    readonly property string themeName: data.name || ""
    readonly property string mode: data.mode || "dark"

    // Fallbacks only matter if colors.json is missing (never after a
    // bootstrap) - plain readable greys rather than an invisible bar.
    readonly property color background: c.background || "black"
    readonly property color surface: c.surface || "black"
    readonly property color foreground: c.foreground || "white"
    readonly property color foregroundStrong: c.foreground_strong || foreground
    readonly property color foregroundMuted: c.foreground_muted || "gray"
    readonly property color accent: c.accent || "gray"
    readonly property color accentForeground: c.accent_foreground || "white"
    readonly property color border: c.border || "gray"
    readonly property color borderActive: c.border_active || "white"
    readonly property color error: c.error || "red"

    // A missing file is reported by FileView itself ("Read of ... failed");
    // only content that is not JSON needs a message of ours.
    function parse() {
        const text = file.text();
        if (text.trim() === "") return;
        try {
            root.data = JSON.parse(text);
        } catch (e) {
            Log.warn("theme", "colors.json unreadable (" + e + ") - keeping the previous colors; run `theme apply`");
        }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
              + "/workstation/theme/colors.json"
        blockLoading: true
        onTextChanged: root.parse()
    }

    Component.onCompleted: parse()

    // Only entry point for a live theme change: re-read the one file.
    IpcHandler {
        target: "theme"

        function reload(): void {
            file.reload();
        }
    }
}
