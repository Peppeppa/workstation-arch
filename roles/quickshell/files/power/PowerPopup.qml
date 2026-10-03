// FEATURE: power_profiles - battery details + power profile picker (see
// PowerControl.qml). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch.
//
// Same overlay pattern as the other popups (click outside / Escape
// closes, created by a Loader only while open). Battery block only when a
// battery exists. Profiles: only what power-profiles-daemon offers
// (Performance only if hasPerformanceProfile); choosing one sets
// PowerProfiles.profile (D-Bus) - no sudo, no sysfs.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Wayland

PanelWindow {
    id: popup

    required property real anchorX
    required property int barHeight
    required property int fontSize
    required property var profileIcon

    readonly property var device: UPower.displayDevice
    readonly property bool hasBattery: device !== null && device.isPresent && device.isLaptopBattery
    readonly property var profiles: [
        { value: PowerProfile.Performance, label: "Performance", available: PowerProfiles.hasPerformanceProfile },
        { value: PowerProfile.Balanced, label: "Balanced", available: true },
        { value: PowerProfile.PowerSaver, label: "Power Saver", available: true }
    ].filter(p => p.available)

    signal closeRequested

    function stateText() {
        switch (device.state) {
        case UPowerDeviceState.Charging: return "Charging";
        case UPowerDeviceState.Discharging: return "Discharging";
        case UPowerDeviceState.FullyCharged: return "Fully charged";
        case UPowerDeviceState.PendingCharge: return "Not charging";
        case UPowerDeviceState.Empty: return "Empty";
        default: return "Unknown";
        }
    }

    function duration(seconds) {
        if (!(seconds > 0)) return "";
        const h = Math.floor(seconds / 3600), m = Math.round((seconds % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    visible: true
    focusable: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power"

    MouseArea {
        anchors.fill: parent
        onClicked: popup.closeRequested()
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: popup.closeRequested()
    }

    Component.onCompleted: keyHandler.forceActiveFocus()

    Rectangle {
        readonly property int panelWidth: 260

        x: Math.max(6, Math.min(popup.anchorX - panelWidth / 2, popup.width - panelWidth - 6))
        y: popup.barHeight + 4
        width: panelWidth
        implicitHeight: content.implicitHeight + 20
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 4

            // Battery (only with a battery).
            ColumnLayout {
                visible: popup.hasBattery
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Battery  " + (popup.hasBattery ? Math.round(popup.device.percentage * 100) + "%" : "")
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize + 1
                    font.bold: true
                }

                Text {
                    text: popup.hasBattery
                          ? [popup.stateText(),
                             UPower.onBattery ? "on battery" : "on AC power",
                             popup.device.state === UPowerDeviceState.Discharging && popup.duration(popup.device.timeToEmpty) !== ""
                               ? popup.duration(popup.device.timeToEmpty) + " left"
                             : popup.device.state === UPowerDeviceState.Charging && popup.duration(popup.device.timeToFull) !== ""
                               ? popup.duration(popup.device.timeToFull) + " until full" : ""
                            ].filter(s => s !== "").join("  ·  ")
                          : ""
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize - 1
                }
            }

            Text {
                Layout.topMargin: popup.hasBattery ? 8 : 0
                text: "Power profile"
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 1
            }

            Repeater {
                model: popup.profiles

                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool active: PowerProfiles.profile === modelData.value

                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 4
                    color: active ? Colors.accent : rowMouse.containsMouse ? Colors.surface : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: popup.profileIcon(row.modelData.value)
                            color: row.active ? Colors.accentForeground : Colors.foreground
                            font.family: Fonts.icons
                            font.pixelSize: popup.fontSize + 1
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            color: row.active ? Colors.accentForeground : Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: PowerProfiles.profile = row.modelData.value
                    }
                }
            }

            Text {
                visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
                      ? "Performance limited: laptop on your lap"
                      : "Performance limited: high temperature"
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 2
            }
        }
    }
}
