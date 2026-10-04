// Shared display-brightness model (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// Backlight only (laptop panel): brightnessctl's backlight class, the same
// tool the brightness keys use (roles/hyprland binds). Capability-aware:
// without a controllable backlight `available` stays false and the UI
// hides the control - nothing is faked. One `brightnessctl -m` read when an
// instance is created (popup/window opened) and after each own change; no
// poller - a change made by the keys while a popup is open shows on the
// next open. Writes are coalesced: one running `brightnessctl set` at a
// time, the latest requested value follows it.

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Scope {
    id: model

    property bool available: false
    property string device: ""
    property real value: 0               // 0..1
    property real pending: -1

    function set(v) {
        if (!available) return;
        v = Math.max(0.01, Math.min(1, v));     // never fully dark from a slider
        value = v;
        if (setProc.running) pending = v;
        else write(v);
    }

    function write(v) {
        setProc.command = ["brightnessctl", "-q", "-c", "backlight", "-d", device, "set", Math.round(v * 100) + "%"];
        setProc.running = true;
    }

    Component.onCompleted: readProc.running = true

    // -m: "device,class,current,percent%,max" per device; first backlight.
    Process {
        id: readProc
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.split("\n")[0].split(",");
                if (f.length >= 5 && f[1] === "backlight" && parseInt(f[4]) > 0) {
                    model.device = f[0];
                    model.value = parseInt(f[2]) / parseInt(f[4]);
                    model.available = true;
                } else {
                    model.available = false;
                }
            }
        }
        onExited: exitCode => { if (exitCode !== 0) model.available = false; }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: exitCode => {
            if (exitCode !== 0)
                Log.warn("brightness", "brightnessctl set on " + model.device + " failed (exit " + exitCode + "): " + Log.firstLine(setErr.text));
            if (model.pending >= 0) {
                const v = model.pending;
                model.pending = -1;
                model.write(v);
            }
        }
    }
}
