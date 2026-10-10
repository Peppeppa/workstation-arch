// OS menu - the header of a page below the root: back chevron + title.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. A click goes back to the root list.

import QtQuick
import qs

Rectangle {
    id: header

    required property string title
    required property var menu

    implicitHeight: Fonts.px(28)
    radius: Style.controlRadius
    color: backMouse.containsMouse ? Colors.surface : "transparent"

    Text {
        id: chevron
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0141}"               // chevron-left
        color: Colors.foregroundMuted
        font.family: Fonts.icons
        font.pixelSize: Style.body
    }

    Text {
        anchors.left: chevron.right
        anchors.leftMargin: Style.spacingMd
        anchors.verticalCenter: parent.verticalCenter
        text: header.title
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: Style.secondary
    }

    MouseArea {
        id: backMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: header.menu.back()
    }
}
