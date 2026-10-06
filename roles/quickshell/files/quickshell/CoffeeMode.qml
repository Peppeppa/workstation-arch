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
// hypridle, so explicit locks (Super+L, power menu, lock before
// suspend) are unaffected: those go through logind, not idle events.
//
// Read-only status for scripts/tests: `qs ipc call coffee status` prints
// "on" or "off". Deliberately no setter - the bar icon is the only switch.
//
// Deliberately not persisted: starts off on every Quickshell start/
// reload, and if Quickshell exits or crashes the compositor drops the
// inhibitor with its surface - idle is normal again (fail-safe).

pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    IpcHandler {
        target: "coffee"

        function status(): string {
            return root.active ? "on" : "off";
        }
    }
}
