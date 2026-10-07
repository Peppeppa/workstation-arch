// OS menu - Settings: Appearance, Network and Firewall. Managed by Ansible:
// do not edit by hand, see roles/quickshell in workstation-arch. The same
// list as the root (RootPage with other entries); the destinations stay
// OsMenu.activate()'s: Appearance opens the Appearance window, Network
// nm-connection-editor, Firewall the Firewall window. Back
// (h/Left/Backspace) returns to the root list.

import QtQuick
import QtQuick.Layouts
import qs

FocusScope {
    id: page

    required property var menu

    implicitHeight: column.implicitHeight

    function reset() {
        list.reset();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace) {
            page.menu.back();
            event.accepted = true;
        }
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

        RootPage {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            focus: true
            menu: page.menu
            entries: page.menu.settingsEntries
        }
    }
}
