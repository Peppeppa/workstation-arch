// Bar widget "power": battery icon + percent when a battery exists (core);
// without one, the current power profile icon (power_profiles feature) or
// nothing at all (no empty slot). With the feature a click opens the power
// popup (Popup.qml: battery details + profiles). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.

import QtQuick
import Quickshell.Services.UPower
import qs
import qs.bar

BarWidget {
    id: root

    Model {
        id: power
    }

    visible: power.hasBattery || BarFeatures.powerProfiles
    icon: power.hasBattery ? power.batteryIcon : power.profileIcon(PowerProfiles.profile)
    text: power.hasBattery ? power.percent + "%" : ""
    warning: power.low
    interactive: BarFeatures.powerProfiles
    onClicked: button => { if (button === Qt.LeftButton) root.togglePopup(); }

    Loader {
        id: popupLoader
        active: root.popupOpen && BarFeatures.powerProfiles
        Component.onCompleted: if (BarFeatures.powerProfiles) setSource("Popup.qml", { owner: root, profileIcon: power.profileIcon })
    }

    Connections {
        target: popupLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested() { root.closePopup(); }
    }
}
