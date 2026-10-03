// FEATURE: connectivity (see group_vars/all.yml connectivity_enabled and
// docs/feature-architecture.md). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Loaded by Bar.qml only while
// the feature is enabled.
//
// Host for the Connectivity Center (ConnectivityPopup.qml, created only
// while open): the bar's network label stays core, a click on it calls
// open(). No bar content of its own.

import QtQuick
import Quickshell

Item {
    id: control

    required property var bar
    // Bluetooth feature present: the popup shows its Bluetooth section and
    // hands "More" over to the Bluetooth popup via openBluetooth().
    required property bool bluetoothEnabled
    required property var openBluetooth

    property bool popupOpen: false
    property real popupAnchorX: 0

    function open(item) {
        popupAnchorX = item.mapToItem(null, item.width / 2, 0).x;
        popupOpen = !popupOpen;
    }

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    Loader {
        active: control.popupOpen
        sourceComponent: ConnectivityPopup {
            screen: control.bar.screen
            anchorX: control.popupAnchorX
            barHeight: control.bar.barHeight
            fontSize: control.bar.fontSize
            bluetoothEnabled: control.bluetoothEnabled
            onCloseRequested: control.popupOpen = false
            onBluetoothRequested: {
                control.popupOpen = false;
                control.openBluetooth();
            }
        }
    }
}
