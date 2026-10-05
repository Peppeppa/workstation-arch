pragma Singleton

// The shell's popout coordinator (Omarchy's requestPopout/releasePopout idea):
// at most ONE transient surface is open at a time, across all monitors - a
// bar popup or one of the overlays (OS menu, Appearance, power menu,
// clipboard history). An owner calls request(this) when it opens and
// release(this) when it closes; whatever was open before is asked to close
// (its closePopup()). Without the overlays in here, opening the OS menu over
// a bar popup showed both, and once the menu closed the popup no longer had
// the keyboard (Escape did nothing). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.

import QtQuick
import Quickshell

Singleton {
    id: root

    property var active: null

    function request(owner) {
        if (active === owner) return;
        const previous = active;
        active = owner;
        if (previous && typeof previous.closePopup === "function") previous.closePopup();
    }

    function release(owner) {
        if (active === owner) active = null;
    }

    function closeAll() {
        if (active && typeof active.closePopup === "function") active.closePopup();
        active = null;
    }
}
