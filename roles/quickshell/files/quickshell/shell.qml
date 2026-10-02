// Quickshell Core Desktop v1 - root config. Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// Owns: one top bar per monitor (Bar.qml) and one keyboard-driven app
// launcher (Launcher.qml), toggled via Quickshell's own IPC (see
// Launcher.qml's IpcHandler and roles/hyprland's mainMod+Space bind).
// mako still owns notifications; no tray, control center, Wi-Fi/
// Bluetooth menus, or theme framework yet - see AGENTS.md Next
// Milestone for what's deliberately deferred.
//
// A handful of readonly color/size constants here, shared by Bar.qml
// and Launcher.qml via required properties, are the whole "design
// system" for now - not a framework, just the one place to change a
// value instead of repeating literals in two files.

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    readonly property color colorBackground: "#1e1e1e"
    readonly property color colorText: "#e0e0e0"
    readonly property color colorTextActive: "#ffffff"
    readonly property color colorActive: "#3a6ea5"
    readonly property int barHeight: 28
    readonly property int fontSize: 13

    // Native, event-driven clock: SystemClock maintains its own
    // internal timer at the given precision - this never polls `date`.
    // Shared by every Bar instance below via the `clock` property.
    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    // Binding (not starting/owning) the current default sink: this is
    // what makes its live audio.volume/audio.muted properties update
    // and settable at all, per Quickshell.Services.Pipewire's own
    // PwObjectTracker docs. Shared globally (Pipewire is a singleton),
    // so one tracker here covers Bar.qml's volume widget on every
    // monitor. Never starts, stops, or reconfigures PipeWire/
    // WirePlumber (roles/audio remains their only lifecycle owner).
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    // One bar per connected monitor - Quickshell's own normal model for
    // this (Variants over Quickshell.screens) makes it no more complex
    // than a single bar would be.
    Variants {
        model: Quickshell.screens

        Bar {
            // modelData is injected by Variants itself after this
            // delegate is created - do not set it explicitly here (see
            // Bar.qml's own property declaration).
            //
            // Qualified with `root.` throughout: Bar.qml declares its
            // own same-named properties, so an unqualified RHS (e.g.
            // `clock: clock`) would resolve to Bar's own not-yet-set
            // property instead of ShellRoot's - a self-reference
            // binding loop, confirmed the hard way in testing (Qt
            // reported "Binding loop detected" and clock.date read as
            // undefined until this was qualified).
            clock: systemClock
            colorBackground: root.colorBackground
            colorText: root.colorText
            colorTextActive: root.colorTextActive
            colorActive: root.colorActive
            barHeight: root.barHeight
            fontSize: root.fontSize
        }
    }

    // One launcher instance, not one per monitor: it has no preferred
    // screen set, so the compositor places it on whichever output is
    // currently focused (standard wlr-layer-shell behavior for a
    // surface with no output binding) - simpler and more correct for a
    // single modal overlay than guessing which monitor to pin it to.
    Launcher {
        // Qualified with `root.` for the same reason as Bar above.
        colorBackground: root.colorBackground
        colorText: root.colorText
        colorTextActive: root.colorTextActive
        colorActive: root.colorActive
        fontSize: root.fontSize
    }
}
