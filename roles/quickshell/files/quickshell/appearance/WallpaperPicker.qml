// Appearance - the wallpaper picker (over the Appearance window). Managed
// by Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// Previews of the ACTIVE theme's backgrounds/ (the directory is the list -
// from the shared ThemeModel, no second registry). A click applies that
// wallpaper through the helper (`theme wallpaper set`, remembered per
// theme) and closes; Cancel (or Escape / a click outside) closes without
// changing anything. Thumbnails are decoded small; GIFs show their first
// frame with a GIF badge.

import QtQuick
import QtQuick.Layouts
import qs

Item {
    id: picker

    required property var model
    required property int fontSize
    signal done

    readonly property var items: model.backgrounds

    // Clicks beside the panel cancel (the window's own handler would close
    // the whole Appearance window).
    MouseArea {
        anchors.fill: parent
        onClicked: picker.done()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Fonts.px(620)
        height: Math.min(box.implicitHeight + 2 * Style.spacingXl, picker.height - 80)
        radius: Style.panelRadius
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
            anchors.margins: Style.spacingXl
            spacing: Style.spacingMd

            Text {
                text: "Wallpaper  ·  " + (picker.model.wallpaper ? picker.model.nameOf(picker.model.activeMode(), picker.model.wallpaper.theme) : "")
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: Style.sectionTitle
                font.bold: true
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: picker.items

                    Rectangle {
                        id: cell
                        required property var modelData
                        readonly property bool current: picker.model.wallpaper && modelData.file === picker.model.wallpaper.selected

                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 9 / 16
                        radius: 6
                        color: Colors.surface
                        border.color: current ? Colors.accent : cellMouse.containsMouse ? Colors.borderActive : Colors.border
                        border.width: current ? 2 : 1

                        Image {
                            anchors.fill: parent
                            anchors.margins: cell.border.width
                            source: "file://" + cell.modelData.path
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 320
                            sourceSize.height: 180
                            asynchronous: true
                            cache: false
                        }

                        Text {
                            visible: cell.modelData.animated
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Style.spacingSm
                            text: "GIF"
                            color: Colors.accentForeground
                            font.family: Fonts.family
                            font.pixelSize: picker.fontSize - 4
                            font.bold: true

                            Rectangle {
                                z: -1
                                anchors.fill: parent
                                anchors.margins: -2
                                radius: Style.smallRadius
                                color: Colors.accent
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                picker.model.setWallpaper(cell.modelData.file);
                                picker.done();
                            }
                        }
                    }
                }
            }

            Text {
                visible: picker.items.length === 0
                text: "No wallpapers in this theme's backgrounds/"
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: Style.secondary
            }

            Rectangle {
                Layout.alignment: Qt.AlignRight
                implicitWidth: cancelText.implicitWidth + 24
                implicitHeight: Style.compactRowHeight
                radius: Style.controlRadius
                color: cancelMouse.containsMouse ? Colors.surface : "transparent"
                border.color: Colors.border
                border.width: 1

                Text {
                    id: cancelText
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: Style.secondary
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: picker.done()
                }
            }
        }
    }
}
