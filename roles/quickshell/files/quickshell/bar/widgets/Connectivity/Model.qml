// Bar widget "connectivity" - the network state it shows (core). Managed
// by Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
// Quickshell.Networking (NetworkManager over D-Bus, event-driven); never
// changes anything.

import QtQuick
import Quickshell.Networking

QtObject {
    id: model

    readonly property var connectedDevice: Networking.devices.values.find(d => d.connected && d.type === DeviceType.Wifi)
                                           || Networking.devices.values.find(d => d.connected && d.type === DeviceType.Wired)
                                           || null
    readonly property string kind: connectedDevice === null ? "none"
                                 : connectedDevice.type === DeviceType.Wifi ? "wifi" : "wired"
    readonly property var wifiNetwork: kind === "wifi" && connectedDevice.networks
                                       ? connectedDevice.networks.values.find(n => n.connected) || null : null
    readonly property real signal: wifiNetwork ? (wifiNetwork.signalStrength > 1 ? wifiNetwork.signalStrength / 100 : wifiNetwork.signalStrength) : 0

    readonly property string icon: kind === "wired" ? "\u{F0200}"                   // ethernet
        : kind === "wifi" ? (signal > 0.75 ? "\u{F0928}" : signal > 0.5 ? "\u{F0925}" : signal > 0.25 ? "\u{F0922}" : "\u{F091F}")
        : "\u{F092E}"                                                                   // wifi-strength-off
    readonly property string label: kind === "wired" ? "Wired"
        : kind === "wifi" ? "Wi-Fi: " + (wifiNetwork ? wifiNetwork.name + "  (" + Math.round(signal * 100) + "%)" : "connected")
        : "Disconnected"
}
