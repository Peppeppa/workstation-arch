// Bar widget "coffee": the idle-pause toggle (CoffeeMode.qml; the inhibitor
// itself lives on the bar surface, Bar.qml). Only with the lock_idle
// feature. Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Off: dimmed cup. On: accent cup. Fixed slot - nothing
// shifts when it toggles.

import QtQuick
import qs
import qs.bar

BarWidget {
    icon: ""
    active: CoffeeMode.active
    muted: !CoffeeMode.active
    tooltip: CoffeeMode.active ? "Coffee mode on: no idle lock / screen off" : "Coffee mode off"
    onClicked: button => { if (button === Qt.LeftButton) CoffeeMode.active = !CoffeeMode.active; }
}
