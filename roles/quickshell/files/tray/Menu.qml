// FEATURE: tray - context menu of one tray item (see Widget.qml). Managed
// by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.
//
// Renders the item's own DBusMenu (through Quickshell's QsMenuOpener in
// MenuLevel.qml) with the central Colors/Fonts, so it follows a live
// theme switch. Same overlay pattern as the power menu: while open the
// transparent surface covers the output, a click outside or Escape
// closes it, choosing an entry triggers it and closes. Created by a
// Loader only while open - when closed there is no surface at all, so
// nothing is left holding keyboard or pointer input.

import QtQuick
import qs
import qs.bar

BarPopup {
    id: menuWindow

    required property var item

    panelWidth: Fonts.px(240)

    Loader {
        id: level
        anchors.left: parent.left
        anchors.right: parent.right
        Component.onCompleted: setSource("MenuLevel.qml", { handle: menuWindow.item.menu, fontSize: menuWindow.fontSize })
    }

    Connections {
        target: level.item
        function onEntryTriggered() { menuWindow.closeRequested(); }
    }
}
