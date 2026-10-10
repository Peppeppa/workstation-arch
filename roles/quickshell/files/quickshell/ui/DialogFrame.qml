// The panel of every centred question/dialog (RICE v1 phase 3): one width
// class, radius, padding, title and spacing. Managed by Ansible: do not edit
// by hand, see roles/quickshell in workstation-arch.
//
// Only the look: the owner keeps its stages, keys, focus and close policy
// (bar/BarPopups.qml). Children go into the column under the title; a click
// on the panel never reaches the owner's outside-click area.

import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: frame

    property string title: ""
    property color titleColor: Colors.foreground
    property int panelWidth: Style.standardPanelWidth   // a Style width class
    property int availableWidth: parent ? parent.width : panelWidth + 2 * Style.spacingXl
    // never taller than the screen leaves (a long form scrolls nowhere: clipped)
    property int maxHeight: parent ? parent.height - 5 * Style.spacingXl : height
    default property alias content: column.data

    anchors.centerIn: parent
    width: Style.fitWidth(panelWidth, availableWidth)
    height: Math.min(column.implicitHeight + 2 * Style.spacingXl, maxHeight)
    clip: column.implicitHeight + 2 * Style.spacingXl > maxHeight
    radius: Style.panelRadius
    color: Colors.background
    border.color: Colors.borderActive
    border.width: 1

    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacingXl
        spacing: Style.spacingMd

        Text {
            visible: frame.title !== ""
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: frame.title
            color: frame.titleColor
            font.family: Fonts.family
            font.pixelSize: Style.title
            font.bold: true
        }
    }
}
