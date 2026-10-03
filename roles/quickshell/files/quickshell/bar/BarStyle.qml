pragma Singleton

// Bar geometry + typography in one place (RICE v1, Omarchy-style compact
// bar). Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Colors are NOT here - they come from Colors (themes).

import QtQuick
import Quickshell

Singleton {
    // Bar
    readonly property int height: 26
    readonly property int edgeMargin: 8          // bar content inset left/right
    readonly property int iconSlot: 27           // width of an icon-only widget
    readonly property int iconSize: 14           // Nerd Font glyph px
    readonly property int textSize: 12           // bar labels
    readonly property int textPadding: 8         // left/right padding of a labelled widget
    readonly property int groupGap: 4            // icon <-> label inside one widget

    // Interaction states
    readonly property int hoverInset: 3          // hover background inset (top/bottom)
    readonly property int hoverRadius: 4
    readonly property int underlineHeight: 2     // "popup open" mark under the widget
    readonly property int dragThreshold: 6
    readonly property int moveDuration: 120      // neighbours sliding during a drag only

    // Popups
    readonly property int popupGap: 4            // between bar and popup
    readonly property int popupWidth: 320
    readonly property int popupPadding: 10
    readonly property int popupRadius: 8
    readonly property int popupFontSize: 13
    readonly property int tooltipFontSize: 12
}
