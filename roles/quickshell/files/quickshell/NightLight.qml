// Day/Night: a warmer display color temperature (Visuals bar widget).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.
//
// Night = hyprsunset (hyprwm's own blue-light filter, official Arch
// package; it sets the outputs' color transform through Hyprland's
// hyprland-ctm-control protocol) running as a child of this Quickshell.
// Day = no hyprsunset: when it exits, Hyprland drops its color transform.
// So the process exists exactly while Night is on - no daemon otherwise,
// no schedule, no polling, no slider.
//
// Fade (0.5 s): hyprsunset starts neutral (--identity) and is stepped from
// 6500 K to 4500 K over its IPC (`hyprctl hyprsunset temperature N`,
// ~5 ms each), 10 steps; switching back steps up to 6500 K first and only
// then ends the process. The step timer exists only while fading. At most
// one IPC call runs at a time - a step that would overlap is replaced by
// the newest temperature (no queue). Clicks during a fade do nothing
// (toggle() returns while busy).
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
    readonly property int neutral: 6500         // K - no visible tint
    readonly property int steps: 10
    readonly property int fadeMs: 500

    property bool active: false                 // Night (the target, set at the click)
    property bool busy: false                   // a fade is running
    property int step: 0
    property int from: neutral
    property int to: neutral
    property int pending: -1                    // newest temperature waiting for the IPC call

    function toggle() {
        if (busy) return;                       // a click during a fade: no action
        busy = true;
        step = 0;
        if (!active) {
            active = true;
            from = neutral;
            to = temperature;
            proc.running = true;                // fade starts once it runs
        } else {
            active = false;
            from = temperature;
            to = neutral;
            fade.start();
        }
    }

    function setTemperature(t) {
        if (ipc.running) {
            pending = t;
            return;
        }
        ipc.command = ["hyprctl", "hyprsunset", "temperature", String(t)];
        ipc.running = true;
    }

    // The last step is applied: Night stays, Day ends hyprsunset.
    function finish() {
        busy = false;
        if (!active) proc.running = false;
    }

    Process {
        id: proc
        command: ["hyprsunset", "--identity"]
        stderr: StdioCollector { id: err }
        onStarted: fade.start()
        onExited: exitCode => {
            fade.stop();
            // Ended without being asked (missing binary, protocol refused):
            // show Day again instead of a toggle that lies.
            if (root.active || root.busy) {
                Log.warn("visuals", "hyprsunset exited (" + exitCode + ") while Night was on: " + Log.firstLine(err.text));
                root.active = false;
                root.busy = false;
            }
        }
    }

    Timer {
        id: fade
        interval: root.fadeMs / root.steps
        repeat: true
        onTriggered: {
            root.step++;
            root.setTemperature(Math.round(root.from + (root.to - root.from) * root.step / root.steps));
            if (root.step >= root.steps) stop();
        }
    }

    Process {
        id: ipc
        onExited: {
            if (root.pending !== -1) {
                const t = root.pending;
                root.pending = -1;
                root.setTemperature(t);
            } else if (root.busy && root.step >= root.steps) {
                root.finish();
            }
        }
    }
}
