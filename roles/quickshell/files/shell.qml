// Quickshell foundation - one minimal top bar. Managed by Ansible: do
// not edit by hand, see roles/quickshell in workstation-arch.
//
// Scope is deliberately small (see AGENTS.md Next Milestone): one thin,
// opaque bar per monitor showing workspaces (left), a clock (center),
// and network/volume/battery state (right). No launcher, tray,
// notifications, or control center yet - fuzzel/mako (roles/hyprland,
// roles/desktop) still own those responsibilities until a later
// milestone replaces them.
//
// Every data source below is one of Quickshell's own native,
// event-driven integrations (Hyprland's IPC socket, PipeWire's and
// UPower's D-Bus services, NetworkManager via Quickshell.Networking) -
// nothing here shells out to hyprctl/wpctl/nmcli/upower/date, and
// nothing here starts, stops, or reconfigures the backends it reads
// (PipeWire/WirePlumber, NetworkManager, Hyprland itself stay owned by
// their existing roles - see docs/ARCHITECTURE.md "one owner per
// responsibility").

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

ShellRoot {
    // Centralized, minimal constants every bar instance below shares -
    // not a theming framework (docs/DESIGN_SYSTEM.md stays deferred
    // until a later milestone actually needs one), just the one place
    // to change a color/size instead of repeating literals.
    readonly property color colorBackground: "#1e1e1e"
    readonly property color colorText: "#e0e0e0"
    readonly property color colorTextActive: "#ffffff"
    readonly property color colorActive: "#3a6ea5"
    readonly property int barHeight: 28
    readonly property int fontSize: 13

    // Native, event-driven clock: SystemClock maintains its own
    // internal timer at the given precision - this never polls `date`.
    // Minutes precision matches the "no seconds" requirement exactly
    // (it simply never updates more often than that).
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Binding (not starting/owning) the current default sink: this is
    // what makes its live audio.volume/audio.muted properties update at
    // all, per Quickshell.Services.Pipewire's own PwObjectTracker docs.
    // Re-evaluates automatically whenever PipeWire's default sink
    // changes (e.g. a device is plugged/unplugged) - WirePlumber alone
    // still owns that decision.
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    // One bar per connected monitor - Quickshell's own normal model for
    // this (Variants over Quickshell.screens) makes it no more complex
    // than a single bar would be. Workspace highlighting below is
    // global (Hyprland.focusedWorkspace), not yet filtered per the
    // monitor each bar is on - deliberately deferred, see the
    // implementation report, rather than adding monitor-matching logic
    // this milestone doesn't need.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            // Exactly 3 anchors + the default ExclusionMode.Auto makes
            // Quickshell reserve this bar's own height as a layer-shell
            // exclusive zone automatically - no hardcoded Hyprland gaps.
            implicitHeight: barHeight
            color: colorBackground

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 16

                // LEFT: Hyprland workspaces. Hyprland.workspaces only
                // ever contains workspaces Hyprland itself currently
                // knows about (i.e. existing/occupied ones), kept live
                // over Hyprland's own IPC event socket - Quickshell
                // handles the subscription, this file just reads it.
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    Repeater {
                        model: Hyprland.workspaces.values

                        Rectangle {
                            implicitWidth: label.implicitWidth + 12
                            implicitHeight: barHeight - 8
                            radius: 3
                            color: modelData.focused ? colorActive : "transparent"

                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: modelData.name.length > 0 ? modelData.name : modelData.id
                                color: modelData.focused ? colorTextActive : colorText
                                font.pixelSize: fontSize
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: modelData.activate()
                            }
                        }
                    }
                }

                // CENTER: clock, e.g. "Fri 02 Oct 15:30".
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "ddd dd MMM hh:mm")
                    color: colorText
                    font.pixelSize: fontSize
                }

                // RIGHT: network, volume, battery (battery only if present).
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 16

                    Text {
                        color: colorText
                        font.pixelSize: fontSize
                        text: {
                            const devices = Networking.devices.values;
                            for (const device of devices) {
                                if (!device.connected) continue;
                                if (device.type === DeviceType.Wifi) return "Wi-Fi";
                                if (device.type === DeviceType.Wired) return "Wired";
                            }
                            return "Disconnected";
                        }
                    }

                    Text {
                        color: colorText
                        font.pixelSize: fontSize
                        text: {
                            const sink = Pipewire.defaultAudioSink;
                            if (!sink || !sink.ready) return "Vol: --";
                            if (sink.audio.muted) return "Muted";
                            return "Vol: " + Math.round(sink.audio.volume * 100) + "%";
                        }
                    }

                    Text {
                        visible: UPower.displayDevice !== null && UPower.displayDevice.isPresent
                        color: colorText
                        font.pixelSize: fontSize
                        text: {
                            const battery = UPower.displayDevice;
                            if (!battery || !battery.isPresent) return "";
                            const charging = battery.state === UPowerDeviceState.Charging;
                            return Math.round(battery.percentage) + "%" + (charging ? " +" : "");
                        }
                    }
                }
            }
        }
    }
}
