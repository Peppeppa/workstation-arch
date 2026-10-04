// Bar widget "power" - battery state (core). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch. UPower's
// displayDevice over D-Bus: event-driven, no polling.

import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: model

    // Shared with BatteryWatcher.qml: the low/critical threshold.
    readonly property int lowPercent: 15

    readonly property var device: UPower.displayDevice
    // A real laptop battery only (UPS/peripheral batteries are not this).
    readonly property bool hasBattery: device !== null && device.isPresent && device.isLaptopBattery
    // UPower's percentage is 0-1.
    readonly property int percent: hasBattery ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: hasBattery && device.state === UPowerDeviceState.Charging
    readonly property bool onExternalPower: hasBattery && (charging || device.state === UPowerDeviceState.FullyCharged
                                                           || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool discharging: hasBattery && device.state === UPowerDeviceState.Discharging
    readonly property bool low: discharging && percent <= lowPercent

    // Plug while on external power; otherwise a battery filled in 10% steps.
    readonly property string batteryIcon: onExternalPower ? "\u{F06A5}"            // power-plug
        : percent <= 10 ? "\u{F008E}"                                              // battery-outline
        : percent >= 95 ? "\u{F0079}"                                              // battery (full)
        : String.fromCodePoint(0xF007A + Math.max(0, Math.min(8, Math.floor(percent / 10) - 1)))

    // UPower's own estimates (seconds; 0 = none). Never computed here.
    function estimateText() {
        if (!hasBattery) return "";
        const s = charging ? device.timeToFull : discharging ? device.timeToEmpty : 0;
        if (!(s > 60)) return "";
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        const t = h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m";
        return charging ? t + " until full" : t + " remaining";
    }

    function profileIcon(p) {
        return p === PowerProfile.Performance ? "\u{F14DE}"     // rocket
             : p === PowerProfile.PowerSaver ? "\u{F032A}"      // leaf
             : "\u{F05D1}";                                      // scale (balanced)
    }
}
