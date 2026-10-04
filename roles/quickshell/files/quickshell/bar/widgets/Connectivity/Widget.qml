// Bar widget "connectivity": compact network state (icon only). With the connectivity feature a click opens the Connectivity
// Center (Popup.qml: Wi-Fi, QR, Bluetooth, VPN). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.

import QtQuick
import qs
import qs.bar

BarWidget {
    id: root

    Model {
        id: net
    }

    icon: net.icon
    muted: net.kind === "none"
    interactive: BarFeatures.connectivity
    onClicked: button => { if (button === Qt.LeftButton) root.togglePopup(); }

    Loader {
        id: popupLoader
        active: root.popupOpen && BarFeatures.connectivity
        Component.onCompleted: if (BarFeatures.connectivity) setSource("Popup.qml", { owner: root })
    }

    Connections {
        target: popupLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested() { root.closePopup(); }
        function onBluetoothRequested() { Qt.callLater(() => root.bar.openWidgetPopup("bluetooth")); }
    }
}
