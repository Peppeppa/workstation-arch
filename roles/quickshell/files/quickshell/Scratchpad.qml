pragma Singleton

// Scratchpad - the shared handle (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// The one ScratchpadWindow (shell.qml) registers itself here; the bar
// widget and anything else toggle it through this and read `open`. Where
// the notes live is decided here only: ONE Markdown file in ~/Documents
// (the Nextcloud-synced folder, /2_Dokumente) - see ScratchpadWindow.qml.

import QtQuick
import Quickshell

Singleton {
    id: root

    property var window: null
    // === true: during a config reload `window` can still name the old,
    // destroyed window, whose visible is undefined ("Unable to assign
    // [undefined] to bool" at every reload, journal 2026-10-10).
    readonly property bool open: !!window && window.visible === true

    readonly property string dir: Quickshell.env("HOME") + "/Documents/.system"
    readonly property string file: dir + "/scratchpad.md"
    readonly property string stateFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                        + "/workstation/scratchpad.json"

    function toggle() {
        if (window) window.toggle();
    }
}
