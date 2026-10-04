// OS menu - Applications: search + results (the former launcher's view).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Data and filtering: AppModel.qml.
//
// The search field has the focus as soon as the page shows; every letter
// is search input (no j/k/h/l handling here). Up/Down move, Enter
// launches, Escape closes the whole OS menu. Each row is only
// [icon] Name (34 px): the entry's icon via Quickshell.iconPath in the
// session icon theme (QS_ICON_THEME = Papirus), or a generic glyph.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

FocusScope {
    id: page

    required property var menu

    readonly property int rowHeight: 34
    property string query: ""
    property int selectedIndex: 0
    readonly property var results: apps.search(query)
    onResultsChanged: selectedIndex = 0

    function reset() {
        query = "";
        searchInput.text = "";
        selectedIndex = 0;
    }

    function takeFocus() {
        searchInput.forceActiveFocus();
    }

    function launchSelected() {
        if (results.length === 0) return;
        const entry = results[Math.min(selectedIndex, results.length - 1)];
        page.menu.close();
        entry.execute();
    }

    implicitHeight: header.implicitHeight + 8 + 36 + 8 + apps.maxResults * rowHeight

    AppModel {
        id: apps
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        PageHeader {
            id: header
            Layout.fillWidth: true
            title: "Applications"
            menu: page.menu
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: 4
            color: Colors.surface
            border.color: Colors.borderActive
            border.width: 1

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.margins: 8
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: page.menu.fontSize + 2
                clip: true

                onTextChanged: page.query = text

                Keys.onDownPressed: page.selectedIndex = Math.min(page.selectedIndex + 1, page.results.length - 1)
                Keys.onUpPressed: page.selectedIndex = Math.max(page.selectedIndex - 1, 0)
                Keys.onReturnPressed: page.launchSelected()
                Keys.onEnterPressed: page.launchSelected()
                Keys.onEscapePressed: page.menu.close()
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: false
            model: page.results
            currentIndex: page.selectedIndex

            delegate: Rectangle {
                id: resultDelegate
                required property var modelData
                required property int index
                readonly property bool selected: index === page.selectedIndex
                width: ListView.view.width
                height: page.rowHeight
                radius: 4
                color: selected ? Colors.accent : "transparent"

                // App icon (theme lookup; "" when the theme has none)
                // or a generic app glyph.
                readonly property string iconSource: resultDelegate.modelData.icon
                    ? Quickshell.iconPath(resultDelegate.modelData.icon, true) : ""

                Item {
                    id: iconBox
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        visible: resultDelegate.iconSource !== "" && status === Image.Ready
                        source: resultDelegate.iconSource
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: resultDelegate.iconSource === "" || appIcon.status === Image.Error
                        text: "\u{F08C6}"          // generic application glyph
                        color: resultDelegate.selected ? Colors.accentForeground : Colors.foregroundMuted
                        font.family: Fonts.icons
                        font.pixelSize: 18
                    }
                }

                Text {
                    anchors.left: iconBox.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: resultDelegate.modelData.name
                    color: resultDelegate.selected ? Colors.accentForeground : Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: page.menu.fontSize
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        page.selectedIndex = resultDelegate.index;
                        page.launchSelected();
                    }
                }
            }
        }
    }
}
