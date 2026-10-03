// Color scheme CONTRACT - the semantic color roles every scheme must
// define (see docs/DESIGN_SYSTEM.md). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// A scheme is pure color data: no logic, no dark/light decision (that
// belongs to Colors.qml). `required` makes a scheme that forgets a role
// fail loudly at load time instead of rendering a silent default.
//
// Add a role here only when a real component needs it - this is a
// small vocabulary, not a design-token framework.

import QtQuick

QtObject {
    // Base layers
    required property color background     // panels, bar, launcher window
    required property color surface        // elements on top of background (input field, buttons)
    required property color surfaceHover   // hovered surface (Power Menu v1)

    // Text
    required property color text           // primary text on background/surface
    required property color textMuted      // secondary text (descriptions, hints)

    // Emphasis
    required property color accent         // focus/selection fill (focused workspace, selected row)
    required property color accentText     // text drawn on top of accent
    required property color border         // panel/input outlines

    // Status
    required property color error          // destructive/failed state (Power Menu v1)
}
