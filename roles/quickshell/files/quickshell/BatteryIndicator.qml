// Battery slot of the bar (core). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// UPower's display device via Quickshell (event-driven D-Bus, no
// polling). Hidden when there is no battery. Note: Quickshell 0.3.1's
// UPowerDevice.percentage is 0-1 (it scales UPower's 0-100 by 0.01).
// Click is forwarded to the bar (opens the power popup when the
// power_profiles feature is on).

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

Item {
    id: indicator

    required property var bar
    signal clicked

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent && device.isLaptopBattery
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging
                                                 || device.state === UPowerDeviceState.FullyCharged
                                                 || device.state === UPowerDeviceState.PendingCharge)

    visible: present
    implicitWidth: row.implicitWidth
    implicitHeight: bar.barHeight

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            // Nerd Font (Material Design) battery glyphs: charging, alert,
            // 10..90 % steps, full.
            text: indicator.charging ? "\u{F0084}"
                : indicator.percent <= 10 ? "\u{F0083}"
                : indicator.percent >= 95 ? "\u{F0079}"
                : String.fromCodePoint(0xF007A + Math.max(0, Math.min(8, Math.floor(indicator.percent / 10) - 1)))
            color: !indicator.charging && indicator.percent <= 10 ? Colors.error : Colors.foreground
            font.family: Fonts.icons
            font.pixelSize: indicator.bar.fontSize + 1
        }

        Text {
            text: indicator.percent + "%"
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: indicator.bar.fontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: indicator.clicked()
    }
}
