// FEATURE: wallpaper - thumbnail picker inside the theme dialog
// (ThemeDialog.qml loads it only while the feature is enabled). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// Shows the active theme's backgrounds (from the dialog's one
// `theme status --json` run - the directory is the list). A click runs
// `theme wallpaper set <file>`: remembered for this theme, applied live.
// Thumbnails are decoded small and only while the dialog is open.

import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: picker

    required property var dialog
    readonly property var info: dialog.status ? dialog.status.wallpaper : null
    readonly property var items: info ? info.backgrounds : []

    spacing: 4

    Text {
        Layout.topMargin: 6
        text: "Wallpaper"
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: picker.dialog.fontSize - 1
    }

    Text {
        visible: picker.info !== null && picker.items.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: picker.info ? "No wallpapers in themes/" + picker.info.theme + "/backgrounds/" : ""
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: picker.dialog.fontSize - 2
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 6
        rowSpacing: 6

        Repeater {
            model: picker.items

            Rectangle {
                id: thumb
                required property var modelData
                readonly property bool current: picker.info && modelData.file === picker.info.selected

                Layout.fillWidth: true
                Layout.preferredHeight: width * 9 / 16
                radius: 4
                color: Colors.surface
                border.color: current ? Colors.accent : thumbMouse.containsMouse ? Colors.borderActive : Colors.border
                border.width: current ? 2 : 1

                Image {
                    anchors.fill: parent
                    anchors.margins: thumb.border.width
                    source: "file://" + thumb.modelData.path
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 192
                    sourceSize.height: 108
                    asynchronous: true
                    cache: false
                }

                Text {
                    visible: thumb.modelData.animated
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    text: "GIF"
                    color: Colors.accentForeground
                    font.family: Fonts.family
                    font.pixelSize: picker.dialog.fontSize - 4
                    font.bold: true

                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: 2
                        color: Colors.accent
                    }
                }

                MouseArea {
                    id: thumbMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: picker.dialog.setWallpaper(thumb.modelData.file)
                }
            }
        }
    }
}
