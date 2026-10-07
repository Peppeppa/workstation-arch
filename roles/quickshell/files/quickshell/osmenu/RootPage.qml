// OS menu - a list of entries: the root list, and (with other entries) the
// Settings list. Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. Navigation only: what an entry
// does is OsMenu.activate(); the entries themselves are OsMenu's
// (rootEntries / settingsEntries). The first entry is selected on every
// open; no wrap-around. Plain letters (j/k too) start the type-to-search.

import QtQuick
import QtQuick.Layouts
import qs

FocusScope {
    id: page

    required property var menu

    required property var entries
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

    // A printable character with no Ctrl/Alt/Super (control characters
    // like Backspace and a leading blank excluded): search text.
    function isSearchText(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false;
        const t = event.text;
        if (t.length === 0 || t.trim() === "") return false;
        const c = t.charCodeAt(0);
        return c >= 0x20 && c !== 0x7f;
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J)) page.move(1);
        else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K)) page.move(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            page.menu.activate(page.entries[page.index].id);
        else if (event.key === Qt.Key_Left) page.menu.back();
        else if (event.key === Qt.Key_Escape) page.menu.close();
        else if (page.isSearchText(event)) page.menu.startSearch(event.text);
        else return;
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
                    width: Fonts.px(22)
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
