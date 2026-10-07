// OS menu - type-to-search results. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// Shown only while there is a query: the first printable key on a menu
// list starts it (OsMenu.startSearch); an emptied query or Escape returns
// to the normal menu (OsMenu.endSearch) - there is never an empty results
// view. Searches the OS menu's own entries (OsMenu.rootEntries /
// settingsEntries - the same list the pages show, opened through the same
// OsMenu.activate()) and the applications (AppModel, its ranking for
// both). The best match is selected at once: type, Enter. Up/Down or
// Ctrl+J/Ctrl+K move; every other key is text (j and k included). The
// index is built per keystroke from what is already in memory, only
// while this page is used - nothing runs while the menu is closed.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

FocusScope {
    id: page

    required property var menu

    readonly property int rowHeight: 34
    readonly property int maxResults: apps.maxResults
    property string query: ""
    property int selectedIndex: 0

    // [{kind: "entry", id, label, icon, hint} | {kind: "app", entry}],
    // best first: score, then menu entries before apps, then name.
    readonly property var results: {
        if (query.length === 0) return [];
        const needle = query.toLowerCase();
        const out = [];
        const entries = page.menu.rootEntries.map(e => ({ e: e, hint: "" }))
            .concat(page.menu.settingsEntries.map(e => ({ e: e, hint: "Settings" })));
        for (const x of entries) {
            const score = apps.matchScore(needle, x.e.label, "", x.e.keywords || "");
            if (score >= 0)
                out.push({ score: score, rank: 0, name: x.e.label,
                           item: { kind: "entry", id: x.e.id, label: x.e.label, icon: x.e.icon, hint: x.hint } });
        }
        for (const a of apps.scored(query))
            out.push({ score: a.score, rank: 1, name: a.entry.name, item: { kind: "app", entry: a.entry } });
        out.sort((a, b) => a.score - b.score || a.rank - b.rank || a.name.localeCompare(b.name));
        return out.slice(0, maxResults).map(o => o.item);
    }
    onResultsChanged: selectedIndex = 0

    function reset() {
        searchInput.text = "";
        query = "";
        selectedIndex = 0;
    }

    // The first key typed on a menu list.
    function begin(text) {
        searchInput.text = text;
        searchInput.cursorPosition = searchInput.text.length;
        searchInput.forceActiveFocus();
    }

    function takeFocus() {
        searchInput.forceActiveFocus();
    }

    function move(d) {
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + d));
    }

    function activateSelected() {
        if (results.length === 0) return;
        const r = results[Math.min(selectedIndex, results.length - 1)];
        if (r.kind === "entry") {
            page.menu.activate(r.id);
        } else {
            page.menu.close();
            r.entry.execute();
        }
    }

    // From the layout itself: field + rows incl. their spacing.
    implicitHeight: column.implicitHeight

    AppModel {
        id: apps
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Fonts.px(36)
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

                onTextChanged: {
                    page.query = text;
                    if (text === "" && page.menu.page === "search") page.menu.endSearch();
                }

                // Before the TextInput's own handling: Ctrl+K would otherwise
                // delete to the end of the line.
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J)) page.move(1);
                    else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K)) page.move(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) page.activateSelected();
                    else if (event.key === Qt.Key_Escape) page.menu.endSearch();
                    else return;
                    event.accepted = true;
                }
            }
        }

        Text {
            visible: page.results.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: page.rowHeight
            leftPadding: 10
            verticalAlignment: Text.AlignVCenter
            text: "No matches"
            color: Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: page.menu.fontSize
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: page.results

                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === page.selectedIndex
                    readonly property bool isApp: modelData.kind === "app"
                    readonly property string iconSource: isApp && modelData.entry.icon
                        ? Quickshell.iconPath(modelData.entry.icon, true) : ""

                    Layout.fillWidth: true
                    implicitHeight: page.rowHeight
                    radius: 4
                    color: selected ? Colors.accent : rowMouse.containsMouse ? Colors.surface : "transparent"

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
                            visible: row.iconSource !== "" && status === Image.Ready
                            source: row.iconSource
                            sourceSize.width: 22
                            sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !row.isApp || row.iconSource === "" || appIcon.status === Image.Error
                            text: row.isApp ? "\u{F08C6}" : row.modelData.icon
                            color: row.selected ? Colors.accentForeground : row.isApp ? Colors.foregroundMuted : Colors.foreground
                            font.family: Fonts.icons
                            font.pixelSize: row.isApp ? 18 : page.menu.fontSize + 3
                        }
                    }

                    Text {
                        anchors.left: iconBox.right
                        anchors.right: hint.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        text: row.isApp ? row.modelData.entry.name : row.modelData.label
                        color: row.selected ? Colors.accentForeground : Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: page.menu.fontSize
                        elide: Text.ElideRight
                    }

                    // Where a menu entry lives (Settings), so it reads apart from apps.
                    Text {
                        id: hint
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.isApp ? "" : row.modelData.hint
                        color: row.selected ? Colors.accentForeground : Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: page.menu.fontSize - 1
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            page.selectedIndex = row.index;
                            page.activateSelected();
                        }
                    }
                }
            }
        }
    }
}
