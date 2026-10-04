// Low-battery warning (core). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Instantiated once by
// shell.qml (not per bar, so one notification per event).
//
// Event-driven: reacts to UPower's percentage/state changes, no timer.
// Warns once when the battery drops to thresholdPercent (15%, the bar
// widget's critical threshold) while discharging; re-armed only by a new
// charging cycle (external power) or once the charge is back above
// rearmPercent - a level hovering around 15% never notifies twice. Uses the
// existing notification system via a one-shot `notify-send` (fixed argv);
// without a notification daemon it simply does nothing.

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: watcher

    readonly property int thresholdPercent: 15
    readonly property int rearmPercent: 20
    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent && device.isLaptopBattery
    readonly property bool discharging: present && device.state === UPowerDeviceState.Discharging
    readonly property int percent: present ? Math.round(device.percentage * 100) : 100
    property bool warned: false

    function check() {
        if (!discharging || percent >= rearmPercent) {
            warned = false;
        } else if (!warned && percent <= thresholdPercent) {
            warned = true;
            Log.warn("power", "battery low: " + percent + "% while discharging - notification sent");
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Battery",
                                     "Battery low", percent + "% remaining - plug in the charger"]);
        }
    }

    onPercentChanged: check()
    onDischargingChanged: check()
}
