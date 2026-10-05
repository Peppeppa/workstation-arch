// Bar widget "power" - its popup (battery v2, core). Managed by Ansible:
// do not edit by hand, see roles/quickshell in workstation-arch.
//
// A BarPopup (click outside / Escape closes, exists only while open).
//   Battery            72%       percentage from UPower
//   [==========......]           charge bar (error color when low)
//   3h 42m remaining             UPower's own estimate, only when it has one
//   Power profile                feature power_profiles: Power Saver |
//   [Saver][Balanced][Perf]      Balanced | Performance via power-profiles-
//                                daemon (D-Bus); Performance only where the
//                                platform offers it (hasPerformanceProfile)
// No sudo, no sysfs, no sampling.

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs
import qs.bar

BarPopup {
    id: popup

    required property var power

    readonly property var profiles: [
        { value: PowerProfile.PowerSaver, label: "Power Saver", available: true },
        { value: PowerProfile.Balanced, label: "Balanced", available: true },
        { value: PowerProfile.Performance, label: "Performance", available: PowerProfiles.hasPerformanceProfile }
    ]

    panelWidth: 300

    // power-profiles-daemon answers asynchronously; a switch it refused
    // (polkit, platform) leaves the old profile - say so in the journal.
    Timer {
        id: profileCheck
        property int wanted: -1
        interval: 2000
        onTriggered: if (PowerProfiles.profile !== wanted)
            Log.warn("power", "switch to " + PowerProfile.toString(wanted) + " was not applied by power-profiles-daemon (still "
                     + PowerProfile.toString(PowerProfiles.profile) + ")")
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Battery"
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: popup.fontSize + 1
                font.bold: true
            }

            Text {
                text: popup.power.percent + "%"
                color: popup.power.low ? Colors.error : Colors.foreground
                font.family: Fonts.family
                font.pixelSize: popup.fontSize + 1
                font.bold: true
            }
        }

        Rectangle {
            id: track
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: Colors.surface
            border.color: Colors.border
            border.width: 1

            Rectangle {
                width: track.width * Math.max(0, Math.min(1, popup.power.percent / 100))
                height: parent.height
                radius: 4
                color: popup.power.low ? Colors.error : Colors.accent
            }
        }

        Text {
            readonly property string estimate: popup.power.estimateText()
            visible: estimate !== ""
            text: estimate
            color: Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 2
        }

        // Power profiles (feature power_profiles) - only on battery: on
        // external power PowerPolicy.qml keeps Performance.
        Text {
            visible: BarFeatures.powerProfiles && popup.power.profileByPolicy
            Layout.topMargin: 8
            text: "\u{F06A5}  On external power: " + (PowerProfiles.hasPerformanceProfile ? "Performance" : "Balanced")
            color: Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
        }
        Text {
            visible: BarFeatures.powerProfiles && !popup.power.profileByPolicy
            Layout.topMargin: 8
            text: "Power profile"
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
            font.bold: true
        }

        RowLayout {
            visible: BarFeatures.powerProfiles && !popup.power.profileByPolicy
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: popup.profiles

                Rectangle {
                    id: btn
                    required property var modelData
                    readonly property bool current: PowerProfiles.profile === modelData.value
                    readonly property bool usable: modelData.available
                    Layout.fillWidth: true
                    implicitHeight: Fonts.px(30)
                    radius: 4
                    opacity: usable ? 1 : 0.4
                    color: current ? Colors.accent : btnMouse.containsMouse && usable ? Colors.surface : "transparent"
                    border.color: current ? Colors.accent : Colors.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: btn.modelData.label
                        color: btn.current ? Colors.accentForeground : btn.usable ? Colors.foreground : Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: popup.fontSize - 2
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: btn.usable && !btn.current
                        onClicked: {
                            PowerProfiles.profile = btn.modelData.value;
                            profileCheck.wanted = btn.modelData.value;
                            profileCheck.restart();
                        }
                    }
                }
            }
        }
    }
}
