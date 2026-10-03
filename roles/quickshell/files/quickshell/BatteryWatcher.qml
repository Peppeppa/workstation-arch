// Low-battery warning (core). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Instantiated once by
// shell.qml (not per bar, so one notification per event).
//
// Event-driven: reacts to UPower's percentage/state changes, no timer.
// Warns once per discharge cycle when the battery drops to thresholdPercent
// while discharging; re-armed as soon as it charges again. Uses the
// existing notification system via a one-shot `notify-send` (fixed argv);
// without a notification daemon it simply does nothing.

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: watcher

    readonly property int thresholdPercent: 10
    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent && device.isLaptopBattery
    readonly property bool discharging: present && device.state === UPowerDeviceState.Discharging
    readonly property int percent: present ? Math.round(device.percentage * 100) : 100
    property bool warned: false

    function check() {
        if (!discharging) {
            warned = false;
        } else if (!warned && percent <= thresholdPercent) {
            warned = true;
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Battery",
                                     "Battery low", percent + "% remaining - plug in the charger"]);
        }
    }

    onPercentChanged: check()
    onDischargingChanged: check()
}
