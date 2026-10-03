// Core Desktop v1 top bar. Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. One instance per monitor,
// created by shell.qml's Variants block.
//
// Every data source here is one of Quickshell's own native,
// event-driven integrations (Hyprland's IPC socket, PipeWire's and
// UPower's D-Bus services, NetworkManager via Quickshell.Networking) -
// nothing here shells out to hyprctl/wpctl/nmcli/upower/date, and
// nothing here starts, stops, or reconfigures the backends it reads or
// (for audio) writes to (PipeWire/WirePlumber, NetworkManager, Hyprland
// itself stay owned by their existing roles - see docs/ARCHITECTURE.md
// "one owner per responsibility").

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland

PanelWindow {
    id: bar

    // Injected by shell.qml's Variants block after construction - not
    // a `required property` on purpose: Variants sets it via direct
    // property assignment, not QML object-literal syntax, and this is
    // the same pattern already confirmed working for the Quickshell
    // foundation milestone.
    property var modelData
    screen: modelData

    required property var clock
    // lock_idle feature present (templated by shell.qml.j2): only then
    // is there an idle daemon worth pausing, so only then the coffee
    // toggle exists.
    required property bool idleToggleAvailable
    required property int barHeight
    required property int fontSize

    anchors {
        top: true
        left: true
        right: true
    }
    // Exactly 3 anchors + the default ExclusionMode.Auto makes
    // Quickshell reserve this bar's own height as a layer-shell
    // exclusive zone automatically - no hardcoded Hyprland gaps.
    implicitHeight: barHeight
    color: Colors.background

    // Coffee mode: a Wayland idle inhibitor on this (always visible) bar
    // surface while active - created on toggle, destroyed on toggle off
    // or when Quickshell goes away. Every bar holds one; any one is
    // enough for the compositor.
    IdleInhibitor {
        window: bar
        enabled: bar.idleToggleAvailable && CoffeeMode.active
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 16

        // LEFT: Hyprland workspaces, filtered to this bar's own
        // monitor by matching HyprlandWorkspace.monitor.name against
        // this screen's name - both are real notifying properties, so
        // this stays live as workspaces/monitors change, without
        // needing Hyprland.monitorFor() (a plain method call, not
        // guaranteed to re-evaluate on its own). Hyprland.workspaces
        // only ever contains workspaces Hyprland itself currently knows
        // about (i.e. existing/occupied ones), kept live over
        // Hyprland's own IPC event socket - Quickshell handles the
        // subscription, this file just reads it.
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            Repeater {
                model: Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === bar.screen.name)

                Rectangle {
                    implicitWidth: label.implicitWidth + 12
                    implicitHeight: bar.barHeight - 8
                    radius: 3
                    color: modelData.focused ? Colors.accent : "transparent"

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: modelData.name.length > 0 ? modelData.name : modelData.id
                        color: modelData.focused ? Colors.accentText : Colors.text
                        font.pixelSize: bar.fontSize
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: modelData.activate()
                    }
                }
            }
        }

        // CENTER: clock - weekday + 24h time, e.g. "Saturday 16:03"
        // (weekday language follows the session locale). The coffee
        // toggle hangs off the clock's left edge, so the clock stays
        // exactly centered and nothing moves when the icon shows/hides.
        Item {
            Layout.fillWidth: true
            implicitHeight: clockText.implicitHeight

            Text {
                id: clockText
                anchors.centerIn: parent
                text: Qt.formatDateTime(bar.clock.date, "dddd HH:mm")
                color: Colors.text
                font.pixelSize: bar.fontSize
            }

            // Coffee toggle (CoffeeMode.qml). Fixed 22px click/hover
            // target whether or not the icon is drawn. Off: icon hidden,
            // shown muted on hover. On: always shown in the normal text
            // color. Click toggles.
            Item {
                id: coffee
                visible: bar.idleToggleAvailable
                anchors.right: clockText.left
                anchors.rightMargin: 6
                anchors.verticalCenter: clockText.verticalCenter
                width: 22
                height: bar.barHeight

                Text {
                    anchors.centerIn: parent
                    visible: CoffeeMode.active || coffeeMouse.containsMouse
                    text: "\uf0f4"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: bar.fontSize + 1
                    color: CoffeeMode.active ? Colors.text : Colors.textMuted
                }

                MouseArea {
                    id: coffeeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: CoffeeMode.active = !CoffeeMode.active
                }
            }
        }

        // RIGHT: network, volume, battery (battery only if present).
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 16

            Text {
                color: Colors.text
                font.pixelSize: bar.fontSize
                text: {
                    const devices = Networking.devices.values;
                    for (const device of devices) {
                        if (!device.connected) continue;
                        if (device.type === DeviceType.Wifi) {
                            const nets = device.networks ? device.networks.values : [];
                            for (const n of nets) {
                                if (n.connected) return "Wi-Fi: " + n.name;
                            }
                            return "Wi-Fi";
                        }
                        if (device.type === DeviceType.Wired) return "Wired";
                    }
                    return "Disconnected";
                }
            }

            // Volume: left-click toggles mute, scroll adjusts volume.
            // Clamped to [0, 1] - no accidental extreme boost past unity
            // gain via a stray scroll.
            Text {
                id: volumeLabel
                color: Colors.text
                font.pixelSize: bar.fontSize
                text: {
                    const sink = Pipewire.defaultAudioSink;
                    if (!sink || !sink.ready) return "Vol: --";
                    if (sink.audio.muted) return "Muted";
                    return "Vol: " + Math.round(sink.audio.volume * 100) + "%";
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        const sink = Pipewire.defaultAudioSink;
                        if (sink && sink.ready) sink.audio.muted = !sink.audio.muted;
                    }
                    onWheel: wheel => {
                        const sink = Pipewire.defaultAudioSink;
                        if (!sink || !sink.ready) return;
                        const step = 0.05;
                        const delta = wheel.angleDelta.y > 0 ? step : -step;
                        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
                    }
                }
            }

            Text {
                visible: UPower.displayDevice !== null && UPower.displayDevice.isPresent
                color: Colors.text
                font.pixelSize: bar.fontSize
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
