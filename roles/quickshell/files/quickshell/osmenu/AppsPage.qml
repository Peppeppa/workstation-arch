// OS menu - Applications: search + results (the former launcher's view).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Data and filtering: AppModel.qml.
//
// The search field has the focus as soon as the page shows; every letter
// is search input (no j/k/h/l handling here). Up/Down move, Enter
// launches, Escape clears the search, then closes the whole OS menu (the
// close policy's search exception). Each row is only
// [icon] Name (34 px): the entry's icon via Quickshell.iconPath in the
// session icon theme (QS_ICON_THEME = Papirus), or a generic glyph.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

FocusScope {
    id: page

    required property var menu

    readonly property int rowHeight: Style.comfortableRowHeight
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
        // DesktopEntry.execute() ignores Terminal=true (Quickshell 0.3):
        // such an entry (e.g. the user's JupyterLab one) gets the terminal
        // like the menu's own terminal leaves; field codes (%f, %U) dropped.
        if (entry.runInTerminal)
            page.menu.runInTerminal(Array.from(entry.command).filter(a => !/^%[a-zA-Z]$/.test(a)));
        else
            entry.execute();
    }

    implicitHeight: header.implicitHeight + 2 * Style.spacingMd + Style.comfortableRowHeight + apps.maxResults * rowHeight

    AppModel {
        id: apps
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacingMd

        PageHeader {
            id: header
            Layout.fillWidth: true
            title: "Applications"
            menu: page.menu
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Style.comfortableRowHeight
            radius: Style.controlRadius
            color: Colors.surface
            border.color: Colors.borderActive
            border.width: 1

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.margins: Style.spacingMd
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: Style.title
                clip: true

                onTextChanged: page.query = text

                Keys.onDownPressed: page.selectedIndex = Math.min(page.selectedIndex + 1, page.results.length - 1)
                Keys.onUpPressed: page.selectedIndex = Math.max(page.selectedIndex - 1, 0)
                Keys.onReturnPressed: page.launchSelected()
                Keys.onEnterPressed: page.launchSelected()
                Keys.onEscapePressed: {
                    if (text !== "") text = "";
                    else page.menu.close();
                }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // The empty search lists every app: wheel scrolling, and the
            // keyboard selection is kept in view.
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.results
            currentIndex: page.selectedIndex
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: resultDelegate
                required property var modelData
                required property int index
                readonly property bool selected: index === page.selectedIndex
                width: ListView.view.width
                height: page.rowHeight
                radius: Style.controlRadius
                color: selected ? Colors.accent : "transparent"

                // App icon (theme lookup; "" when the theme has none)
                // or a generic app glyph.
                readonly property string iconSource: resultDelegate.modelData.icon
                    ? Quickshell.iconPath(resultDelegate.modelData.icon, true) : ""

                Item {
                    id: iconBox
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.iconLarge
                    height: Style.iconLarge

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        visible: resultDelegate.iconSource !== "" && status === Image.Ready
                        source: resultDelegate.iconSource
                        sourceSize.width: Style.iconLarge
                        sourceSize.height: Style.iconLarge
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
                        font.pixelSize: Style.text(18)
                    }
                }

                Text {
                    anchors.left: iconBox.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacingMd
                    anchors.rightMargin: Style.spacingMd
                    text: resultDelegate.modelData.name
                    color: resultDelegate.selected ? Colors.accentForeground : Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: Style.body
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
