// Bar widget "power" - battery (UPower displayDevice) and power profile
// state (core). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. Event-driven D-Bus, no polling.

import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: model

    readonly property var device: UPower.displayDevice
    readonly property bool hasBattery: device !== null && device.isPresent && device.isLaptopBattery
    // UPower's percentage is 0-1.
    readonly property int percent: hasBattery ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: hasBattery && (device.state === UPowerDeviceState.Charging
                                                    || device.state === UPowerDeviceState.FullyCharged
                                                    || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool low: hasBattery && !charging && percent <= 10

    readonly property string batteryIcon: charging ? "\u{F0084}"
        : percent <= 10 ? "\u{F0083}"
        : percent >= 95 ? "\u{F0079}"
        : String.fromCodePoint(0xF007A + Math.max(0, Math.min(8, Math.floor(percent / 10) - 1)))

    function profileIcon(p) {
        return p === PowerProfile.Performance ? "\u{F14DE}"     // rocket
             : p === PowerProfile.PowerSaver ? "\u{F032A}"      // leaf
             : "\u{F05D1}";                                      // scale (balanced)
    }
}
