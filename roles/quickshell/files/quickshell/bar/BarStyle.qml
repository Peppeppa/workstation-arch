pragma Singleton

// Bar geometry + typography in one place (RICE v1, Omarchy-style compact
// bar). Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Colors are NOT here - they come from Colors (themes).
// Sizes follow the user's text size (Fonts.px: the values below are the
// default text size's; the bar never gets smaller than that).
// Built on the design tokens (Style) since RICE v1 phase 2: same values at
// the default text size. What stays a literal is bar-specific and listed as
// an exception in docs/DESIGN_SYSTEM.md (hover inset, underline, drag and
// animation numbers, the 10 px popup padding, the 13 px bar glyph).

import QtQuick
import Quickshell
import qs

Singleton {
    // Bar
    readonly property int height: Style.grow(26)
    readonly property int edgeMargin: Style.spacingMd   // bar content inset left/right
    readonly property int iconSlot: Style.grow(27)           // width of an icon-only widget
    readonly property int iconSize: Fonts.px(13)           // Nerd Font glyph px (slot stays iconSlot wide)
    readonly property int trayIconSize: Fonts.px(15)       // tray item images (slot stays 24 px)
    readonly property int textSize: Style.secondary        // bar labels (12 at the default size)
    readonly property int textPadding: Style.spacingMd    // left/right padding of a labelled widget
    readonly property int groupGap: Style.spacingSm     // icon <-> label inside one widget

    // Interaction states
    readonly property int hoverInset: 3          // hover background inset (top/bottom)
    readonly property int hoverRadius: Style.controlRadius
    readonly property int underlineHeight: 2     // "popup open" mark under the widget
    readonly property int dragThreshold: 6
    readonly property int dragCorridor: 100      // a drop counts up to this far below the bar
    readonly property int moveDuration: 120      // neighbours sliding during a drag only
    readonly property int revealDuration: 140    // hover reveal of Visuals / the tray (fade, slide)

    // Popups
    readonly property int popupGap: Style.spacingSm     // between bar and popup
    readonly property int popupWidth: Style.grow(320)
    readonly property int popupPadding: 10
    readonly property int popupRadius: Style.panelRadius
    readonly property int popupFontSize: Style.body        // 13 at the default size
    readonly property int tooltipFontSize: Style.secondary
}
