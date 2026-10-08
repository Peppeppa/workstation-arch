// "Coffee mode": pause AUTOMATIC idle actions (hypridle's idle lock and
// idle DPMS-off) while the user reads/watches. Managed by Ansible: do
// not edit by hand, see roles/quickshell in workstation-arch. Only
// meaningful with the lock_idle feature (Bar.qml shows the toggle only
// then).
//
// One shared flag for every Bar instance (one per monitor). The actual
// inhibition is a Wayland idle inhibitor (zwp_idle_inhibit_v1, via
// Quickshell's IdleInhibitor in Bar.qml) - the standard mechanism
// hypridle's listeners already obey. It never stops or reconfigures
// hypridle, so explicit locks (Super+Delete, power menu, lock before
// suspend) are unaffected: those go through logind, not idle events.
//
// Switches: the bar icon and mainMod+Y (`qs ipc call coffee toggle`) - both
// flip this one flag. `qs ipc call coffee status` prints "on" or "off".
//
// Survives a Quickshell restart or reload, but only inside the same
// Hyprland session: while on, $XDG_RUNTIME_DIR/workstation-coffee holds this
// session's HYPRLAND_INSTANCE_SIGNATURE (written on every change, empty when
// off), read once at start. A new login is a new signature, and a reboot or
// full logout clears the runtime directory - so Coffee never comes back on
// by itself in a later session. If Quickshell exits or crashes, the
// compositor drops the inhibitor with its surface (no orphan); a restarted
// Quickshell re-creates it from the flag. No process, no timer, no watcher.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false
    readonly property string session: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    property bool restored: false            // no writes before the start state is read

    // The stored state applies only to the session that wrote it.
    function restoredState(stored, session) {
        return session !== "" && stored.trim() === session;
    }

    onActiveChanged: if (restored) state.setText(active ? session + "\n" : "")

    FileView {
        id: state
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/0") + "/workstation-coffee"
        blockLoading: true
        printErrors: false                  // no file = never switched on in this boot
        atomicWrites: true
    }

    Component.onCompleted: {
        active = restoredState(state.text(), session);
        restored = true;
    }

    IpcHandler {
        target: "coffee"

        function status(): string {
            return root.active ? "on" : "off";
        }

        // mainMod+Y: the same flip as the bar icon -> the new status.
        function toggle(): string {
            root.active = !root.active;
            return root.active ? "on" : "off";
        }
    }
}
