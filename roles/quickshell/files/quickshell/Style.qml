pragma Singleton

// Design tokens: geometry + type scale of every Quickshell surface (RICE v1,
// docs/DESIGN_SYSTEM.md "Design tokens"). Managed by Ansible: do not edit
// by hand, see roles/quickshell in workstation-arch.
//
// The third central source next to Colors (theme roles) and Fonts (font
// families, the one desktop text size): no colors and no font names here.
// Values are written for the default text size (11) and scale through
// Fonts.px (n * size / 11):
//   text(n)  type sizes follow the text size both ways (9 = smaller text)
//   grow(n)  geometry (spacing, radii, rows, panel widths) grows with the
//            text size but never drops below its default value - smaller
//            text keeps the default click targets and padding
// Panel widths are classes, not per-dialog numbers; fitWidth() keeps a
// grown panel inside its screen. Pure values, no state, no process: a theme
// or text-size switch updates every binding through Colors/Fonts.

import QtQuick
import Quickshell

Singleton {
    id: root

    function text(n) {
        return Fonts.px(n);
    }

    function grow(n) {
        return Math.max(n, Fonts.px(n));
    }

    // A panel class width, at most the space the screen leaves (margin
    // spacingXl on each side); never negative.
    function fitWidth(width, available) {
        return Math.max(0, Math.min(width, available - 2 * spacingXl));
    }

    // ---- radius (base: panels 8, controls 4)
    readonly property int panelRadius: grow(8)      // dialogs, menus, popups, toasts
    readonly property int controlRadius: grow(4)    // buttons, rows, fields, plates
    readonly property int smallRadius: grow(2)      // thumbnails, dots, small marks

    // ---- spacing (a 2/4/8/12/16 scale)
    readonly property int spacingXs: grow(2)        // inside a compact element (icon <-> text)
    readonly property int spacingSm: grow(4)        // between related elements
    readonly property int spacingMd: grow(8)        // between rows/groups, control padding
    readonly property int spacingLg: grow(12)       // panel content padding
    readonly property int spacingXl: grow(16)       // dialog padding, distance to the screen edge

    // ---- row heights (text + vertical padding)
    readonly property int compactRowHeight: grow(28)      // dense lists, popup rows, buttons
    readonly property int standardRowHeight: grow(32)     // fields, dialog rows
    readonly property int comfortableRowHeight: grow(36)  // menu / launcher rows

    // ---- panel width classes (base px; fitWidth() for the screen limit)
    readonly property int narrowPanelWidth: grow(280)     // short action lists (power menu)
    readonly property int standardPanelWidth: grow(480)   // menus and ordinary dialogs
    readonly property int widePanelWidth: grow(560)       // lists with columns (firewall, clipboard)

    // ---- typography (Fonts.family / Fonts.icons; sizes only)
    readonly property int body: text(13)            // normal text of overlays and dialogs
    readonly property int secondary: text(12)       // labels, details, bar text
    readonly property int caption: text(11)         // hints, metadata, small print
    // headings stay at least 1 px above the next smaller step (at text size 9
    // rounding would otherwise make a section title as large as body text)
    readonly property int sectionTitle: Math.max(body + 1, text(14))    // a heading inside a panel
    readonly property int title: Math.max(sectionTitle + 1, text(15))   // the panel's own title
    readonly property int iconSmall: text(12)       // glyph inside a secondary line
    readonly property int iconStandard: text(15)    // glyph next to body text (menu rows)
    readonly property int iconLarge: text(22)       // application icons, status pictures

    // Every token (read-only IPC `qs ipc call shell style`, tests).
    function tokens() {
        return {
            textSize: Fonts.size,
            panelRadius: panelRadius, controlRadius: controlRadius, smallRadius: smallRadius,
            spacingXs: spacingXs, spacingSm: spacingSm, spacingMd: spacingMd, spacingLg: spacingLg, spacingXl: spacingXl,
            compactRowHeight: compactRowHeight, standardRowHeight: standardRowHeight, comfortableRowHeight: comfortableRowHeight,
            narrowPanelWidth: narrowPanelWidth, standardPanelWidth: standardPanelWidth, widePanelWidth: widePanelWidth,
            body: body, secondary: secondary, caption: caption, sectionTitle: sectionTitle, title: title,
            iconSmall: iconSmall, iconStandard: iconStandard, iconLarge: iconLarge
        };
    }
}
