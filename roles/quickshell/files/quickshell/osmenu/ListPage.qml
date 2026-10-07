// OS menu - a titled sub list (Packages, Packages -> Install / Remove).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. The same list as the root (RootPage with other entries,
// typing starts the search); what an entry does is OsMenu.activate(). Back
// (Left/Backspace or the header) goes one level up.

import QtQuick
import QtQuick.Layouts
import qs

FocusScope {
    id: page

    required property var menu
    required property string title
    required property var entries

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
            title: page.title
            menu: page.menu
        }

        RootPage {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            focus: true
            menu: page.menu
            entries: page.entries
        }
    }
}
