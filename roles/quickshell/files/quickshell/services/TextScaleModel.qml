// Shared text-size model (non-visual). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// The user-facing text size is GNOME's own runtime setting
// org.gnome.desktop.interface text-scaling-factor (GSettings): GTK3/GTK4/
// libadwaita apps follow it live. Ansible sets only the font NAMES
// (roles/desktop font-name/monospace-font-name) and never this key, so
// there is exactly one owner: the user, through this control. The shell
// itself (bar, popups, menus) keeps its own fixed pixel sizes for now -
// see docs/feature-architecture.md "Appearance". One `gsettings get` when
// an instance is created, `gsettings set` per change; no watcher.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: model

    readonly property var steps: [
        { label: "Small", factor: 0.9 },
        { label: "Default", factor: 1.0 },
        { label: "Large", factor: 1.1 },
        { label: "Larger", factor: 1.25 },
        { label: "Largest", factor: 1.5 }
    ]
    property real factor: 1.0
    property bool ready: false

    function set(f) {
        factor = f;
        setProc.command = ["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", String(f)];
        setProc.running = true;
    }

    Component.onCompleted: getProc.running = true

    Process {
        id: getProc
        command: ["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text.trim());
                if (!isNaN(v)) model.factor = v;
                model.ready = true;
            }
        }
    }

    Process {
        id: setProc
    }
}
