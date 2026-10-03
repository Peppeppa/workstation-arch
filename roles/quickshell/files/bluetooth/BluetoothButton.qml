// FEATURE: bluetooth (see group_vars/all.yml bluetooth_enabled and
// docs/feature-architecture.md). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Loaded by Bar.qml only while
// the feature is enabled.
//
// Bar slot: Quickshell 0.3.1's native Bluetooth module (BlueZ over D-Bus,
// event-driven - no polling, no bluetoothctl). Hidden when there is no
// adapter at all (same convention as the battery widget). Icon:
//   muted        - adapter off or rfkill-blocked
//   normal       - on, nothing connected
//   accent       - at least one device connected
// Left click opens BluetoothPopup.qml (created only while open).

import QtQuick
import Quickshell
import Quickshell.Bluetooth

Item {
    id: button

    required property var bar

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool blocked: adapter !== null && adapter.state === BluetoothAdapterState.Blocked
    readonly property bool on: adapter !== null && adapter.enabled && !blocked
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []
    property bool popupOpen: false

    visible: adapter !== null
    implicitWidth: 22
    implicitHeight: bar.barHeight

    Text {
        anchors.centerIn: parent
        // Nerd Font (Material Design) bluetooth glyphs: off / on / connected.
        text: !button.on ? "\u{F00B2}" : button.connectedDevices.length > 0 ? "\u{F00B1}" : "\u{F00AF}"
        font.family: Fonts.icons
        font.pixelSize: button.bar.fontSize + 2
        color: !button.on ? Colors.foregroundMuted
             : button.connectedDevices.length > 0 ? Colors.accent : Colors.foreground
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: button.popupOpen = !button.popupOpen
    }

    PopupWindow {
        id: tooltip
        readonly property string label: button.blocked ? "Bluetooth blocked"
            : !button.on ? "Bluetooth off"
            : button.connectedDevices.length > 0
              ? button.connectedDevices.map(d => d.name || d.address).join(", ") + " connected"
              : "Bluetooth on"

        visible: mouse.containsMouse && !button.popupOpen
        anchor.item: button
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        color: "transparent"
        implicitWidth: tip.implicitWidth + 16
        implicitHeight: tip.implicitHeight + 10

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Colors.background
            border.color: Colors.border
            border.width: 1

            Text {
                id: tip
                anchors.centerIn: parent
                text: tooltip.label
                textFormat: Text.PlainText
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: button.bar.fontSize - 1
            }
        }
    }

    Loader {
        active: button.popupOpen && button.adapter !== null
        sourceComponent: BluetoothPopup {
            screen: button.bar.screen
            adapter: button.adapter
            anchorX: button.mapToItem(null, button.width / 2, 0).x
            barHeight: button.bar.barHeight
            fontSize: button.bar.fontSize
            onCloseRequested: button.popupOpen = false
        }
    }
}
