// FEATURE: clipboard_history (see group_vars/all.yml
// clipboard_history_enabled and docs/feature-architecture.md). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// The clipboard history popup, toggled by Hyprland's mainMod+V bind via
// IPC (`qs ipc call clipboard toggle`). The history itself is cliphist's
// (~/.cache/cliphist/db, filled by the watcher Hyprland starts - see
// roles/hyprland); this file only reads and edits it on demand:
//   open      `cliphist list` once (previews only)
//   select    `cliphist decode ID | wl-copy` - back onto the clipboard,
//             paste with Ctrl+V as usual
//   delete    `cliphist delete` with "ID" on stdin
//   clear     `cliphist wipe` (second click confirms)
// All fixed argv; entry ids are cliphist's own numbers. Nothing is kept
// while closed (the window and the list exist only while open).
// Keys: type to search, Up/Down, Enter = copy, Delete = remove entry.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property int fontSize

    property bool open: false

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.open = !root.open;
        }

        function close(): void {
            root.open = false;
        }
    }

    Loader {
        active: root.open

        sourceComponent: PanelWindow {
            id: popup

            property var entries: []          // [{id, text}] newest first
            property string query: ""
            property int selectedIndex: 0
            property bool confirmClear: false
            readonly property var results: {
                const q = query.toLowerCase();
                return q === "" ? entries : entries.filter(e => e.text.toLowerCase().includes(q));
            }
            onResultsChanged: selectedIndex = Math.min(selectedIndex, Math.max(0, results.length - 1))

            function reload() {
                listProc.running = true;
            }

            function copySelected() {
                if (results.length === 0) return;
                copyProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", results[selectedIndex].id];
                copyProc.running = true;
            }

            function deleteSelected() {
                if (results.length === 0 || deleteProc.running) return;
                const id = results[selectedIndex].id;
                entries = entries.filter(e => e.id !== id);
                deleteProc.pendingId = id;
                deleteProc.running = true;
            }

            // No screen set: the compositor places it on the focused monitor
            // (same as the launcher).
            visible: true
            focusable: true
            color: "transparent"
            implicitWidth: 560
            implicitHeight: 420

            Component.onCompleted: {
                reload();
                searchInput.forceActiveFocus();
            }

            Process {
                id: listProc
                command: ["cliphist", "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        popup.entries = text.split("\n").filter(l => l.includes("\t")).map(l => {
                            const tab = l.indexOf("\t");
                            return { id: l.slice(0, tab), text: l.slice(tab + 1) };
                        });
                    }
                }
            }

            Process {
                id: copyProc
                onExited: root.open = false
            }

            Process {
                id: deleteProc
                property string pendingId: ""
                command: ["cliphist", "delete"]
                stdinEnabled: true
                onStarted: {
                    write(pendingId + "\n");
                    stdinEnabled = false;
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: wipeProc
                command: ["cliphist", "wipe"]
                onExited: popup.reload()
            }

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Colors.background
                border.color: Colors.borderActive
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

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
                                font.pixelSize: root.fontSize + 1
                                clip: true
                                onTextChanged: popup.query = text

                                Text {
                                    visible: searchInput.text === ""
                                    text: "Search clipboard history"
                                    color: Colors.foregroundMuted
                                    font: searchInput.font
                                }

                                Keys.onDownPressed: popup.selectedIndex = Math.min(popup.selectedIndex + 1, popup.results.length - 1)
                                Keys.onUpPressed: popup.selectedIndex = Math.max(popup.selectedIndex - 1, 0)
                                Keys.onReturnPressed: popup.copySelected()
                                Keys.onEnterPressed: popup.copySelected()
                                Keys.onDeletePressed: popup.deleteSelected()
                                Keys.onEscapePressed: root.open = false
                            }
                        }

                        // Clear all: second click confirms.
                        Rectangle {
                            implicitWidth: clearText.implicitWidth + 16
                            implicitHeight: 36
                            radius: 4
                            color: clearMouse.containsMouse ? Colors.accent : Colors.surface
                            border.color: Colors.border
                            border.width: clearMouse.containsMouse ? 0 : 1

                            Text {
                                id: clearText
                                anchors.centerIn: parent
                                text: popup.confirmClear ? "Clear all?" : "Clear"
                                color: clearMouse.containsMouse ? Colors.accentForeground
                                     : popup.confirmClear ? Colors.error : Colors.foreground
                                font.family: Fonts.family
                                font.pixelSize: root.fontSize - 1
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onExited: popup.confirmClear = false
                                onClicked: {
                                    if (!popup.confirmClear) {
                                        popup.confirmClear = true;
                                        return;
                                    }
                                    popup.confirmClear = false;
                                    popup.entries = [];
                                    wipeProc.running = true;
                                }
                            }
                        }
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: popup.results
                        currentIndex: popup.selectedIndex
                        highlightMoveDuration: 0

                        delegate: Rectangle {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === popup.selectedIndex

                            width: ListView.view.width
                            height: 32
                            radius: 4
                            color: selected ? Colors.accent : entryMouse.containsMouse ? Colors.surface : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.right: deleteButton.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                text: entry.modelData.text
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                color: entry.selected ? Colors.accentForeground : Colors.foreground
                                font.family: Fonts.family
                                font.pixelSize: root.fontSize
                            }

                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: popup.selectedIndex = entry.index
                                onClicked: popup.copySelected()
                            }

                            Text {
                                id: deleteButton
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                visible: entry.selected
                                text: ""
                                color: deleteMouse.containsMouse ? Colors.error : entry.selected ? Colors.accentForeground : Colors.foregroundMuted
                                font.family: Fonts.icons
                                font.pixelSize: root.fontSize

                                MouseArea {
                                    id: deleteMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    onClicked: popup.deleteSelected()
                                }
                            }
                        }
                    }

                    Text {
                        visible: popup.results.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        text: popup.entries.length === 0 ? "Clipboard history is empty" : "No matches"
                        color: Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: root.fontSize - 1
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Enter copy  ·  Del remove  ·  Esc close"
                        color: Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: root.fontSize - 3
                    }
                }
            }
        }
    }
}
