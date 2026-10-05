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

    // Not `id: power`: the popup's `power: power` below would then bind
    // the popup's own (undefined) property - QML resolves the right-hand
    // name inside the object first. Real-hardware finding: the popup showed
    // no percentage and an empty charge bar (TypeError on every binding).
    Model {
        id: batteryModel
    }

    visible: batteryModel.hasBattery
    icon: batteryModel.batteryIcon
    warning: batteryModel.low
    onClicked: button => { if (button === Qt.LeftButton) root.togglePopup(); }

    Loader {
        active: root.popupOpen && batteryModel.hasBattery
        sourceComponent: Popup {
            owner: root
            power: batteryModel
            onCloseRequested: root.closePopup()
        }
    }
}
