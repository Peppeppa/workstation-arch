// Bar widget "power" (battery v2): exists only where a real laptop battery
// is present - otherwise it is invisible and takes no space (the layout
// keeps its id, nothing is rewritten). Icon only: a plug on external power,
// else a battery filled in 10% steps; at <= 15% while discharging it turns
// the theme's error color (BatteryWatcher notifies once). A click opens the
// popup (Popup.qml: charge, UPower's time estimate, power profiles).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. UPower over D-Bus - event-driven, no polling.

import QtQuick
import qs
import qs.bar

BarWidget {
    id: root

    Model {
        id: power
    }

    visible: power.hasBattery
    icon: power.batteryIcon
    warning: power.low
    onClicked: button => { if (button === Qt.LeftButton) root.togglePopup(); }

    Loader {
        active: root.popupOpen && power.hasBattery
        sourceComponent: Popup {
            owner: root
            power: power
            onCloseRequested: root.closePopup()
        }
    }
}
