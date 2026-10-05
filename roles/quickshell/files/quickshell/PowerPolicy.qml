// AC/battery power-profile policy (feature power_profiles, laptops only).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Instantiated once by shell.qml (not per bar).
//
// Product policy: on external power the laptop always runs Performance
// (Balanced where the platform has no Performance); on battery it runs the
// profile the user last chose ON BATTERY. The battery popup shows the
// profile buttons only on battery (Power/Popup.qml).
//
//   plug in    -> Performance (the battery choice is kept, not overwritten)
//   unplug     -> the remembered battery profile
//   on battery, profile changed (popup, powerprofilesctl) -> remembered
//
// Event-driven only: UPower's OnBattery and power-profiles-daemon's
// ActiveProfile (both D-Bus properties via Quickshell) - no timer, no
// polling. A profile is set only when it differs from the active one, so
// repeated events (resume, duplicate signals) set nothing. Suspend/resume
// needs nothing extra: UPower reports the new OnBattery after resume.
// The battery choice survives restarts in one plain file
// (~/.config/workstation/power-battery-profile: power-saver|balanced|
// performance), written only by this object. A host without a laptop
// battery (workstation) is left completely alone.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

Scope {
    id: policy

    readonly property var device: UPower.displayDevice
    readonly property bool laptop: device !== null && device.isPresent && device.isLaptopBattery
    readonly property bool onAc: laptop && !UPower.onBattery
    readonly property int acProfile: PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance : PowerProfile.Balanced
    readonly property var names: ["power-saver", "balanced", "performance"]

    property int batteryProfile: PowerProfile.Balanced
    property bool ready: false

    function nameOf(p) {
        return p === PowerProfile.PowerSaver ? "power-saver" : p === PowerProfile.Performance ? "performance" : "balanced";
    }

    function profileOf(name) {
        return name === "power-saver" ? PowerProfile.PowerSaver : name === "performance" ? PowerProfile.Performance
             : name === "balanced" ? PowerProfile.Balanced : -1;
    }

    // The profile the policy wants now; -1 = leave it alone.
    function wanted() {
        if (!ready || !laptop) return -1;
        return onAc ? acProfile : batteryProfile;
    }

    function apply() {
        const want = wanted();
        if (want === -1 || PowerProfiles.profile === want) return;
        PowerProfiles.profile = want;
    }

    // A change while on battery is the user's battery choice.
    function remember() {
        if (!ready || !laptop || onAc || PowerProfiles.profile === batteryProfile) return;
        batteryProfile = PowerProfiles.profile;
        store.setText(nameOf(batteryProfile) + "\n");
    }

    onOnAcChanged: apply()
    onLaptopChanged: apply()

    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            policy.remember();
        }
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/workstation/power-battery-profile"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => Log.warn("power", "cannot save " + path + " (" + error + ")")
    }

    Component.onCompleted: {
        const p = profileOf(store.text().trim());
        // No remembered choice yet: the current profile if on battery now,
        // else Balanced.
        batteryProfile = p !== -1 && (p !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile) ? p
                       : laptop && !onAc ? PowerProfiles.profile : PowerProfile.Balanced;
        ready = true;
        apply();
    }
}
