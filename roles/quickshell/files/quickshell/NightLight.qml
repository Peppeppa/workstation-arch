// Day/Night: a warmer display color temperature (Visuals bar widget).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.
//
// Night = hyprsunset (hyprwm's own blue-light filter, official Arch
// package; it sets the outputs' color transform through Hyprland's
// hyprland-ctm-control protocol) running as a child of this Quickshell,
// with one fixed temperature. Day = no hyprsunset: when it exits,
// Hyprland drops its color transform and the colors are normal again.
// So the process exists exactly while Night is on - no daemon otherwise,
// no schedule, no polling, no slider.
//
// Deliberately not persisted (like Coffee): every Quickshell start is Day;
// if Quickshell exits or crashes, hyprsunset goes with it (fail-safe).

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property int temperature: 4500     // K - lightly orange
    property bool active: false

    onActiveChanged: proc.running = active

    Process {
        id: proc
        command: ["hyprsunset", "--temperature", String(root.temperature)]
        stderr: StdioCollector { id: err }
        onExited: exitCode => {
            // Ended without being asked (missing binary, protocol refused):
            // show Day again instead of a toggle that lies.
            if (root.active) {
                Log.warn("visuals", "hyprsunset exited (" + exitCode + ") while Night was on: " + Log.firstLine(err.text));
                root.active = false;
            }
        }
    }
}
