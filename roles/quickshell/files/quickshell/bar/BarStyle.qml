pragma Singleton

// Bar geometry + typography in one place (RICE v1, Omarchy-style compact
// bar). Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Colors are NOT here - they come from Colors (themes).
// Sizes follow the user's text size (Fonts.px: the values below are the
// default text size's; the bar never gets smaller than that).

import QtQuick
import Quickshell
import qs

Singleton {
    // Bar
    readonly property int height: Math.max(26, Fonts.px(26))
    readonly property int edgeMargin: 8          // bar content inset left/right
    readonly property int iconSlot: Math.max(27, Fonts.px(27))           // width of an icon-only widget
    readonly property int iconSize: Fonts.px(13)           // Nerd Font glyph px (slot stays iconSlot wide)
    readonly property int trayIconSize: Fonts.px(15)       // tray item images (slot stays 24 px)
    readonly property int textSize: Fonts.px(12)           // bar labels
    readonly property int textPadding: Fonts.px(8)         // left/right padding of a labelled widget
    readonly property int groupGap: 4            // icon <-> label inside one widget

    // Interaction states
    readonly property int hoverInset: 3          // hover background inset (top/bottom)
    readonly property int hoverRadius: 4
    readonly property int underlineHeight: 2     // "popup open" mark under the widget
    readonly property int dragThreshold: 6
    readonly property int dragCorridor: 100      // a drop counts up to this far below the bar
    readonly property int moveDuration: 120      // neighbours sliding during a drag only
    readonly property int revealDuration: 140    // hover reveal of Visuals / the tray (fade, slide)

    // Popups
    readonly property int popupGap: 4            // between bar and popup
    readonly property int popupWidth: Math.max(320, Fonts.px(320))
    readonly property int popupPadding: 10
    readonly property int popupRadius: 8
    readonly property int popupFontSize: Fonts.px(13)
    readonly property int tooltipFontSize: Fonts.px(12)
}
