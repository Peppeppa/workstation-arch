// Bar widget "connectivity": the interface carrying the active default
// route (Model.qml) as one icon - Wi-Fi with signal level, Ethernet, or
// disconnected. With the connectivity feature a click opens the network
// popup (Popup.qml: status, VPN, Wi-Fi - quick control only; administration
// is nm-connection-editor via the OS menu). Managed by Ansible: do not edit
// by hand, see roles/quickshell in workstation-arch.

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
        Component.onCompleted: if (BarFeatures.connectivity) setSource("Popup.qml", { owner: root, net: net })
    }

    Connections {
        target: popupLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested() { root.closePopup(); }
    }
}
