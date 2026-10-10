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
//
// It is also the shell's ONE close controller: every transient surface
// closes through its own closePopup() - Escape (after the surface's own
// inner state: search, nested dialog), a click outside, Super+Q
// (closeActive, below) and another surface opening. Surface-specific
// guards stay in closePopup() (e.g. a running snapshot keeps its dialog).
// See docs/feature-architecture.md "Close policy".

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

    // Super+Q while a shell overlay has the keyboard (roles/hyprland
    // binds.lua -> IPC shell closeActive). -> true when one was asked to
    // close. Nothing active: nothing happens - never a window close here.
    function closeActive() {
        const a = active;
        if (!a || typeof a.closePopup !== "function") return false;
        a.closePopup();
        return true;
    }

    function closeAll() {
        if (active && typeof active.closePopup === "function") active.closePopup();
        active = null;
    }
}
