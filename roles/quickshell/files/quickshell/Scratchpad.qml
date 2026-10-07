pragma Singleton

// Scratchpad - the shared handle (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// The one ScratchpadWindow (shell.qml) registers itself here; the bar
// widget and anything else toggle it through this and read `open`. Where
// the four notes live is decided here only (dataDir) - a later sync can
// point it at another local folder (e.g. a synced Nextcloud directory)
// without touching the window.

import QtQuick
import Quickshell

Singleton {
    id: root

    property var window: null
    readonly property bool open: window !== null && window.visible

    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                      + "/workstation/scratchpad"
    readonly property string stateFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                        + "/workstation/scratchpad.json"

    function toggle() {
        if (window) window.toggle();
    }
}
