// Central color source for every Quickshell component (see
// docs/DESIGN_SYSTEM.md). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch.
//
// Components read semantic roles only - `Colors.background`,
// `Colors.accent`, ... - never a hex literal and never `scheme`
// directly. This file is the one place that decides WHICH scheme is
// active (the appearance/theme decision); the scheme files themselves
// are pure color data (ColorScheme.qml contract, DefaultDark.qml).
//
// Today that decision is a single static scheme. A later dark/light
// switch replaces just the `scheme:` binding below (e.g. picking the
// preferred dark or light scheme by an `appearance` value) - every
// role below stays a binding, so components update without changes
// and without their own dark/light branches.
//
// Purely declarative: a QML singleton evaluated once at load, no
// process, timer, or file watcher.

pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property ColorScheme scheme: DefaultDark {}

    readonly property color background: scheme.background
    readonly property color surface: scheme.surface
    readonly property color surfaceHover: scheme.surfaceHover
    readonly property color text: scheme.text
    readonly property color textMuted: scheme.textMuted
    readonly property color accent: scheme.accent
    readonly property color accentText: scheme.accentText
    readonly property color border: scheme.border
    readonly property color error: scheme.error
}
