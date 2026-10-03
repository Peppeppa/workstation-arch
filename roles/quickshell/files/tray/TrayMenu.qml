// FEATURE: tray - context menu of one tray item (see Tray.qml). Managed
// by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.
//
// Renders the item's own DBusMenu (through Quickshell's QsMenuOpener in
// TrayMenuLevel.qml) with the central Colors/Fonts, so it follows a live
// theme switch. Same overlay pattern as the power menu: while open the
// transparent surface covers the output, a click outside or Escape
// closes it, choosing an entry triggers it and closes. Created by a
// Loader only while open - when closed there is no surface at all, so
// nothing is left holding keyboard or pointer input.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: menuWindow

    required property var item
    required property real anchorX
    required property int barHeight
    required property int fontSize

    signal closeRequested

    visible: true
    focusable: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-traymenu"

    MouseArea {
        anchors.fill: parent
        onClicked: menuWindow.closeRequested()
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: menuWindow.closeRequested()
    }

    Component.onCompleted: keyHandler.forceActiveFocus()

    Rectangle {
        id: panel

        readonly property int panelWidth: 240

        x: Math.max(6, Math.min(menuWindow.anchorX - panelWidth / 2, menuWindow.width - panelWidth - 6))
        y: menuWindow.barHeight + 4
        width: panelWidth
        implicitHeight: level.implicitHeight + 12
        radius: 6
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        // Clicks on the panel never reach the close area underneath.
        MouseArea {
            anchors.fill: parent
        }

        TrayMenuLevel {
            id: level
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            handle: menuWindow.item.menu
            fontSize: menuWindow.fontSize
            onEntryTriggered: menuWindow.closeRequested()
        }
    }
}
