// OS menu - the root list. Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. Navigation only: what an entry
// does is OsMenu.activate(). Applications is selected on every open; no
// wrap-around.

import QtQuick
import QtQuick.Layouts
import qs

FocusScope {
    id: page

    required property var menu

    readonly property var entries: [
        { id: "apps", label: "Applications", icon: "\u{F003B}", sub: true },
        { id: "appearance", label: "Appearance", icon: "\u{F03D8}", sub: false },
        { id: "network", label: "Network", icon: "\u{F06F3}", sub: false },
        { id: "settings", label: "Settings", icon: "\u{F0493}", sub: true },
        { id: "system", label: "System", icon: "\u{F0425}", sub: false }
    ].filter(e => e.id !== "system" || menu.powerMenu !== null)
    property int index: 0

    function reset() {
        index = 0;
        pointerAtOpen = Qt.point(-1, -1);
    }

    // Hover selects only after real pointer movement (as in PowerMenu.qml):
    // the menu maps under a resting pointer, whose first hover report must
    // not replace the preselected Applications entry.
    property point pointerAtOpen: Qt.point(-1, -1)
    function hoverRow(area, mouse, i) {
        const p = area.mapToItem(null, mouse.x, mouse.y);
        if (pointerAtOpen.x < 0) pointerAtOpen = p;
        else if (p.x !== pointerAtOpen.x || p.y !== pointerAtOpen.y) index = i;
    }

    function move(d) {
        index = Math.max(0, Math.min(entries.length - 1, index + d));
    }

    implicitHeight: list.implicitHeight
    focus: true

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_J: case Qt.Key_Down: page.move(1); break;
        case Qt.Key_K: case Qt.Key_Up: page.move(-1); break;
        case Qt.Key_L: case Qt.Key_Right: case Qt.Key_Return: case Qt.Key_Enter:
            page.menu.activate(page.entries[page.index].id); break;
        case Qt.Key_H: case Qt.Key_Left: page.menu.back(); break;
        case Qt.Key_Escape: page.menu.close(); break;
        default: return;
        }
        event.accepted = true;
    }

    ColumnLayout {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 2

        Repeater {
            model: page.entries

            Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === page.index

                Layout.fillWidth: true
                implicitHeight: Fonts.px(34)
                radius: 4
                color: selected ? Colors.accent : rowMouse.containsMouse ? Colors.surface : "transparent"

                Text {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: row.modelData.icon
                    color: row.selected ? Colors.accentForeground : Colors.foreground
                    font.family: Fonts.icons
                    font.pixelSize: page.menu.fontSize + 3
                }

                Text {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    color: row.selected ? Colors.accentForeground : Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: page.menu.fontSize
                }

                Text {
                    visible: row.modelData.sub
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0142}"           // chevron-right: opens a page
                    color: row.selected ? Colors.accentForeground : Colors.foregroundMuted
                    font.family: Fonts.icons
                    font.pixelSize: page.menu.fontSize
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: mouse => page.hoverRow(rowMouse, mouse, row.index)
                    onClicked: page.menu.activate(row.modelData.id)
                }
            }
        }
    }
}
