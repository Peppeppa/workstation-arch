pragma Singleton

// The bar's popout coordinator (Omarchy's requestPopout/releasePopout idea):
// at most ONE bar popup is open at a time, across all monitors. A widget
// calls request(this) when it opens its popup; whatever was open before is
// asked to close (its closePopup()). Managed by Ansible: do not edit by
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
