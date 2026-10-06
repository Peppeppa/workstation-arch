// Appearance - Theme -> Import (over the Appearance window). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// Import an Omarchy-style theme repository: URL + the mode the user picks
// (authoritative) -> Add runs `theme import` (clone pinned to its current
// commit, safe compile, entry in the repository's themes/sources.yml; the
// theme then appears in the Dark/Light lists). Installed themes from
// repositories are listed; Remove runs `theme remove` - refused by the
// helper for a bundled theme or the selected dark/light theme, and the
// button says so before. All work is the helper's (services/ThemeModel);
// Escape / a click outside / Close closes.

import QtQuick
import QtQuick.Layouts
import qs
import qs.bar

Item {
    id: dialog

    required property var model
    required property int fontSize
    signal done

    property string mode: ""            // "dark" | "light" - no default: the user decides
    property string chosen: ""          // id selected in the installed list
    readonly property var chosenEntry: model.sources.find(e => e.id === chosen) || null
    readonly property bool urlOk: /^https:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?\/[A-Za-z0-9._~\/-]+$/.test(urlField.text.trim())
    readonly property string removeBlock: !chosenEntry ? ""
        : chosenEntry.bundled ? "Bundled with this system - not removable here."
        : chosenEntry.selected ? "Selected as a dark/light theme - select another one first."
        : ""

    function reset() {
        urlField.text = "";
        mode = "";
        chosen = "";
        model.sourceMessage = "";
        urlField.forceActiveFocus();
    }

    function add() {
        if (!urlOk || mode === "" || model.sourceBusy) return;
        model.importTheme(urlField.text.trim(), mode);
    }

    // Hidden, the URL field must not keep the keyboard: the Appearance
    // FocusScope would hand focus back to it and swallow the next Escape.
    onVisibleChanged: {
        if (visible) reset();
        else urlField.focus = false;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.done()
    }

    component ModeChip: Rectangle {
        id: chip
        property string value
        readonly property bool current: dialog.mode === value
        Layout.fillWidth: true
        implicitHeight: Fonts.px(28)
        radius: 4
        color: current ? Colors.accent : chipMouse.containsMouse ? Colors.surface : "transparent"
        border.color: current ? Colors.accent : Colors.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: chip.value === "dark" ? "Dark" : "Light"
            color: chip.current ? Colors.accentForeground : Colors.foreground
            font.family: Fonts.family
            font.pixelSize: dialog.fontSize - 1
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dialog.mode = chip.value
        }
    }

    component Caption: Text {
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: dialog.fontSize - 1
    }

    Rectangle {
        anchors.centerIn: parent
        width: Fonts.px(480)
        height: Math.min(box.implicitHeight + 32, dialog.height - 80)
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: box
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 8

            Text {
                text: "Import Theme"
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: dialog.fontSize + 1
                font.bold: true
            }

            Caption { text: "Repository URL (an Omarchy theme)" }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Fonts.px(30)
                radius: 4
                color: Colors.surface
                border.color: urlField.activeFocus ? Colors.borderActive : Colors.border
                border.width: 1

                TextInput {
                    id: urlField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Colors.foreground
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.accentForeground
                    font.family: Fonts.family
                    font.pixelSize: dialog.fontSize - 1
                    Keys.onReturnPressed: dialog.add()
                    Keys.onEnterPressed: dialog.add()
                    Keys.onEscapePressed: dialog.done()

                    Text {
                        visible: urlField.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "https://github.com/owner/omarchy-name-theme"
                        color: Colors.foregroundMuted
                        font: urlField.font
                    }
                }
            }

            Caption { text: "Mode" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                ModeChip { value: "dark" }
                ModeChip { value: "light" }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: dialog.model.sourceMessage !== "" ? dialog.model.sourceMessage
                        : urlField.text.trim() !== "" && !dialog.urlOk ? "Use a plain https:// repository URL."
                        : ""
                    color: dialog.model.sourceFailed || (urlField.text.trim() !== "" && !dialog.urlOk)
                        ? Colors.error : Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: dialog.fontSize - 2
                }
                PopupButton {
                    primary: dialog.urlOk && dialog.mode !== "" && !dialog.model.sourceBusy
                    opacity: primary ? 1 : 0.6
                    label: dialog.model.sourceBusy ? "Importing..." : "Add"
                    fontSize: dialog.fontSize - 1
                    onClicked: dialog.add()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 1
                color: Colors.border
            }

            Caption { text: "Installed themes from repositories" }

            Caption {
                visible: dialog.model.sources.length === 0
                text: "None yet."
            }

            Repeater {
                model: dialog.model.sources

                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool current: dialog.chosen === modelData.id
                    Layout.fillWidth: true
                    implicitHeight: Fonts.px(30)
                    radius: 4
                    color: current ? Colors.accent : rowMouse.containsMouse ? Colors.surface : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        color: row.current ? Colors.accentForeground : Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: dialog.fontSize - 1
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: (row.modelData.mode === "dark" ? "Dark" : "Light")
                            + (row.modelData.bundled ? "  ·  bundled" : "")
                            + (row.modelData.selected ? "  ·  selected" : "")
                        color: row.current ? Colors.accentForeground : Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: dialog.fontSize - 2
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dialog.chosen = row.current ? "" : row.modelData.id
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: dialog.removeBlock
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: dialog.fontSize - 2
                }
                PopupButton {
                    readonly property bool usable: dialog.chosenEntry !== null && dialog.removeBlock === "" && !dialog.model.sourceBusy
                    danger: usable
                    opacity: usable ? 1 : 0.6
                    label: "Remove"
                    fontSize: dialog.fontSize - 1
                    onClicked: if (usable) {
                        dialog.model.removeTheme(dialog.chosen);
                        dialog.chosen = "";
                    }
                }
                PopupButton {
                    label: "Close"
                    fontSize: dialog.fontSize - 1
                    onClicked: dialog.done()
                }
            }
        }
    }
}
