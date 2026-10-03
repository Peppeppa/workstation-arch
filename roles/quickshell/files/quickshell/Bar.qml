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
    // The one ThemeDialog instance (shell.qml), opened by right-clicking
    // the theme icon next to the clock.
    required property var themeDialog
    // tray_enabled (templated by shell.qml.j2): load the tray zone.
    required property bool trayEnabled
    // bluetooth_enabled (templated by shell.qml.j2): load the Bluetooth slot.
    required property bool bluetoothEnabled
    // power_profiles_enabled (templated by shell.qml.j2).
    required property bool powerProfilesEnabled
    // audio_popup_enabled (templated by shell.qml.j2).
    required property bool audioPopupEnabled
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
                        color: modelData.focused ? Colors.accentForeground : Colors.foreground
                        font.family: Fonts.family
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
        // (weekday language follows the session locale). The bar controls
        // hang off the clock's left edge in fixed-size slots, so the clock
        // stays exactly centered and nothing moves when icons show/hide.
        Item {
            Layout.fillWidth: true
            implicitHeight: clockText.implicitHeight

            Text {
                id: clockText
                anchors.centerIn: parent
                text: Qt.formatDateTime(bar.clock.date, "dddd HH:mm")
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: bar.fontSize
            }

            // [coffee][theme] - both icons invisible until the pointer is
            // over either slot (the slots always take their 22px).
            Row {
                id: clockControls
                readonly property bool hovered: themeMouse.containsMouse || coffeeMouse.containsMouse

                anchors.right: clockText.left
                anchors.rightMargin: 4
                anchors.verticalCenter: clockText.verticalCenter

                // Coffee toggle (CoffeeMode.qml). Off: hidden, muted on
                // hover. On: always shown in the normal text color.
                Item {
                    visible: bar.idleToggleAvailable
                    width: 22
                    height: bar.barHeight

                    Text {
                        anchors.centerIn: parent
                        visible: CoffeeMode.active || clockControls.hovered
                        text: "\uf0f4"
                        font.family: Fonts.icons
                        font.pixelSize: bar.fontSize + 1
                        color: CoffeeMode.active ? Colors.foreground : Colors.foregroundMuted
                    }

                    MouseArea {
                        id: coffeeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: CoffeeMode.active = !CoffeeMode.active
                    }
                }

                // Theme mode: moon in dark mode, sun in light mode (from the
                // active theme's mode). Left click toggles dark/light via the
                // `theme` helper (a one-shot process); right click opens the
                // theme picker (ThemeDialog.qml).
                Item {
                    width: 22
                    height: bar.barHeight

                    Text {
                        anchors.centerIn: parent
                        visible: clockControls.hovered
                        text: Colors.mode === "light" ? "\uf185" : "\uf186"
                        font.family: Fonts.icons
                        font.pixelSize: bar.fontSize + 1
                        color: Colors.foreground
                    }

                    MouseArea {
                        id: themeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                bar.themeDialog.open();
                            else
                                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/theme", "toggle"]);
                        }
                    }
                }
            }
        }

        // RIGHT: tray, bluetooth (features), network, volume, battery (battery only if present).
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 16

            // FEATURE: tray (Tray.qml, tray_enabled) - first in the status
            // zone. Not instantiated at all when the feature is off; with no
            // visible item it is invisible and takes no space.
            Loader {
                active: bar.trayEnabled
                visible: active && item !== null && item.shown.length > 0
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: if (active) setSource("Tray.qml", { bar: bar })
            }

            // FEATURE: bluetooth (BluetoothButton.qml, bluetooth_enabled).
            // Not instantiated when the feature is off; hidden when the
            // machine has no Bluetooth adapter.
            Loader {
                active: bar.bluetoothEnabled
                visible: active && item !== null && item.adapter !== null
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: if (active) setSource("BluetoothButton.qml", { bar: bar })
            }

            Text {
                color: Colors.foreground
                font.family: Fonts.family
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

            // Volume: left-click toggles mute, scroll adjusts volume,
            // right-click opens the audio popup (audio_popup feature).
            // Clamped to [0, 1] - no accidental extreme boost past unity
            // gain via a stray scroll.
            Text {
                id: volumeLabel
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: bar.fontSize
                text: {
                    const sink = Pipewire.defaultAudioSink;
                    if (!sink || !sink.ready) return "Vol: --";
                    if (sink.audio.muted) return "Muted";
                    return "Vol: " + Math.round(sink.audio.volume * 100) + "%";
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (audioControl.item) audioControl.item.open(volumeLabel);
                            return;
                        }
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

            // FEATURE: audio_popup (AudioControl.qml): popup host, plus a
            // mic-muted icon while the default input is muted.
            Loader {
                id: audioControl
                active: bar.audioPopupEnabled
                visible: active && item !== null && item.micMuted
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: if (active) setSource("AudioControl.qml", { bar: bar })
            }

            // Battery (core; hidden without a battery). With the
            // power_profiles feature a click opens the power popup.
            BatteryIndicator {
                id: battery
                bar: bar
                Layout.alignment: Qt.AlignVCenter
                onClicked: if (powerControl.item) powerControl.item.open(battery)
            }

            // FEATURE: power_profiles (PowerControl.qml): popup host, plus a
            // profile icon on machines without a battery.
            Loader {
                id: powerControl
                active: bar.powerProfilesEnabled
                visible: active && item !== null && !battery.present
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: if (active) setSource("PowerControl.qml", { bar: bar, hasBattery: Qt.binding(() => battery.present) })
            }
        }
    }
}
