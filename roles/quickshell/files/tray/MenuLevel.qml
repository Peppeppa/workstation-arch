// FEATURE: tray - one level of a DBusMenu (see Menu.qml). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// Entries come from Quickshell's QsMenuOpener (native DBusMenu support):
// separators, disabled entries (muted, inert), checkbox/radio state, and
// submenus - shown inline below their parent, indented, via a nested
// MenuLevel (no cascading popup surfaces). Choosing a leaf entry calls
// its `triggered()` (Quickshell sends the DBusMenu "clicked" event).

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

ColumnLayout {
    id: level

    required property var handle
    required property int fontSize
    property int depth: 0

    signal entryTriggered

    spacing: 1

    QsMenuOpener {
        id: opener
        menu: level.handle
    }

    Repeater {
        model: opener.children

        ColumnLayout {
            id: row

            required property var modelData
            property bool expanded: false

            Layout.fillWidth: true
            spacing: 1

            Rectangle {
                visible: row.modelData.isSeparator
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Colors.border
            }

            Rectangle {
                id: entryRect
                visible: !row.modelData.isSeparator
                Layout.fillWidth: true
                implicitHeight: Fonts.px(28)
                radius: 4
                color: hover.containsMouse && row.modelData.enabled ? Colors.accent : "transparent"

                readonly property color fg: !row.modelData.enabled ? Colors.foregroundMuted
                                            : hover.containsMouse ? Colors.accentForeground : Colors.foreground

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 + level.depth * 12
                    anchors.rightMargin: 8
                    spacing: 8

                    // Check/radio state (QsMenuButtonType), else the entry's icon.
                    Text {
                        visible: row.modelData.buttonType !== QsMenuButtonType.None
                        Layout.preferredWidth: 14
                        text: row.modelData.buttonType === QsMenuButtonType.RadioButton
                              ? (row.modelData.checkState === Qt.Checked ? "" : "")
                              : (row.modelData.checkState === Qt.Checked ? "" : "")
                        color: entryRect.fg
                        font.family: Fonts.icons
                        font.pixelSize: level.fontSize - 1
                    }

                    Image {
                        visible: row.modelData.buttonType === QsMenuButtonType.None && row.modelData.icon !== ""
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        sourceSize.width: 14
                        sourceSize.height: 14
                        source: row.modelData.icon
                    }

                    Text {
                        Layout.fillWidth: true
                        // Quickshell already strips DBusMenu mnemonics ("_File" ->
                        // "File"); any underscore left here is a real one.
                        text: row.modelData.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: entryRect.fg
                        font.family: Fonts.family
                        font.pixelSize: level.fontSize
                    }

                    Text {
                        visible: row.modelData.hasChildren
                        text: row.expanded ? "" : ""   // chevron down/right
                        color: entryRect.fg
                        font.family: Fonts.icons
                        font.pixelSize: level.fontSize - 3
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (!row.modelData.enabled) return;
                        if (row.modelData.hasChildren) {
                            row.expanded = !row.expanded;
                        } else {
                            row.modelData.triggered();
                            level.entryTriggered();
                        }
                    }
                }
            }

            // Submenu, inline. Only instantiated while expanded.
            Loader {
                Layout.fillWidth: true
                active: row.modelData.hasChildren && row.expanded
                visible: active
                onActiveChanged: if (active) setSource("MenuLevel.qml", {
                    handle: row.modelData,
                    fontSize: level.fontSize,
                    depth: level.depth + 1
                })
                onLoaded: item.entryTriggered.connect(level.entryTriggered)
            }
        }
    }
}
