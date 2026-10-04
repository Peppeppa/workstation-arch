// OS menu - Settings: reserved. Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. A real destination replaces
// this page later (OsMenu.activate("settings") stays the hook); nothing
// speculative is built here.

import QtQuick
import QtQuick.Layouts
import qs

FocusScope {
    id: page

    required property var menu

    implicitHeight: column.implicitHeight

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_H: case Qt.Key_Left: case Qt.Key_Backspace: page.menu.back(); break;
        case Qt.Key_Escape: page.menu.close(); break;
        default: return;
        }
        event.accepted = true;
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        PageHeader {
            Layout.fillWidth: true
            title: "Settings"
            menu: page.menu
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 8
            text: "No additional settings yet."
            color: Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: page.menu.fontSize
        }
    }
}
