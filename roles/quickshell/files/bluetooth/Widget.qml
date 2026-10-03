// FEATURE: bluetooth - bar widget "bluetooth" (see group_vars/all.yml
// bluetooth_enabled and docs/feature-architecture.md). Managed by Ansible:
// do not edit by hand, see roles/quickshell in workstation-arch.
//
// Quickshell 0.3.1's native Bluetooth module (BlueZ over D-Bus,
// event-driven - no polling, no bluetoothctl). Hidden when there is no
// adapter at all. Icon: muted = off or rfkill-blocked, normal = on,
// accent = at least one device connected. Click opens Popup.qml. The
// Connectivity Center's "More" opens the same popup (Bar.openWidgetPopup).

import QtQuick
import Quickshell.Bluetooth
import qs
import qs.bar

BarWidget {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool blocked: adapter !== null && adapter.state === BluetoothAdapterState.Blocked
    readonly property bool on: adapter !== null && adapter.enabled && !blocked
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []

    visible: adapter !== null
    // Nerd Font (Material Design) bluetooth glyphs: off / on / connected.
    icon: !on ? "\u{F00B2}" : connectedDevices.length > 0 ? "\u{F00B1}" : "\u{F00AF}"
    muted: !on
    active: on && connectedDevices.length > 0
    tooltip: blocked ? "Bluetooth blocked"
           : !on ? "Bluetooth off"
           : connectedDevices.length > 0 ? connectedDevices.map(d => d.name || d.address).join(", ") + " connected"
           : "Bluetooth on"
    onClicked: button => { if (button === Qt.LeftButton) root.togglePopup(); }

    // Loaded by path (feature widget): its own files by relative path too.
    Loader {
        id: popupLoader
        active: root.popupOpen && root.adapter !== null
        Component.onCompleted: setSource("Popup.qml", { owner: root, adapter: Qt.binding(() => root.adapter) })
    }

    Connections {
        target: popupLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested() { root.closePopup(); }
    }
}
