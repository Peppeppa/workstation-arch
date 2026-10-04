// Appearance - the window's content. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// Sections: Theme (dark + light, from the theme directories via the shared
// services/ThemeModel - the same runtime path as the bar's theme popup),
// Wallpaper (opens WallpaperPicker.qml), Brightness (only with a real
// backlight, services/BrightnessModel), Text size (GTK text-scaling-factor,
// services/TextScaleModel), Display (each output as Hyprland reports it -
// read-only, see docs/feature-architecture.md "Appearance").

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.ui

FocusScope {
    id: root

    required property var window
    required property int fontSize

    property var monitors: []

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: {
        if (root.window.pickerOpen) root.window.pickerOpen = false;
        else root.window.close();
    }

    ThemeModel {
        id: themeModel
    }

    BrightnessModel {
        id: brightness
    }

    TextScaleModel {
        id: textScale
    }

    // Outputs as Hyprland has them now: one read per open.
    Process {
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text);
                } catch (e) {
                    root.monitors = [];
                    Log.warn("appearance", "`hyprctl monitors -j` returned no JSON - no display information");
                }
            }
        }
    }

    component SectionTitle: Text {
        Layout.topMargin: 10
        color: Colors.foreground
        font.family: Fonts.family
        font.pixelSize: root.fontSize
        font.bold: true
    }

    component Label: Text {
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: root.fontSize - 1
    }

    // Fixed top edge (placed for the tallest content, then centered once):
    // expanding a selector grows the panel downwards, nothing jumps.
    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(40, Math.round((root.height - 760) / 2))
        width: 480
        height: Math.min(column.implicitHeight + 32, root.height - y - 40)
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 6

                Text {
                    text: "Appearance"
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: root.fontSize + 3
                    font.bold: true
                }

                // ---- Theme ----------------------------------------------
                SectionTitle { text: "Theme" }

                Label { text: "Dark" + (themeModel.activeMode() === "dark" ? "  ·  active" : "") }
                ThemeSelect {
                    Layout.fillWidth: true
                    model: themeModel
                    slot: "dark"
                    fontSize: root.fontSize
                }

                Label { Layout.topMargin: 4; text: "Light" + (themeModel.activeMode() === "light" ? "  ·  active" : "") }
                ThemeSelect {
                    Layout.fillWidth: true
                    model: themeModel
                    slot: "light"
                    fontSize: root.fontSize
                }

                Text {
                    visible: themeModel.errorText !== ""
                    Layout.fillWidth: true
                    text: themeModel.errorText
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: root.fontSize - 2
                }

                // ---- Wallpaper ------------------------------------------
                SectionTitle { text: "Wallpaper" }

                Rectangle {
                    id: wallpaperCard
                    readonly property var current: themeModel.wallpaper
                        ? themeModel.backgrounds.find(b => b.file === themeModel.wallpaper.selected) || null : null
                    Layout.fillWidth: true
                    implicitHeight: 72
                    radius: 6
                    color: cardMouse.containsMouse ? Colors.surface : "transparent"
                    border.color: cardMouse.containsMouse ? Colors.borderActive : Colors.border
                    border.width: 1

                    Rectangle {
                        id: thumb
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 100
                        height: 56
                        radius: 4
                        color: Colors.surface
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: wallpaperCard.current !== null
                            source: wallpaperCard.current ? "file://" + wallpaperCard.current.path : ""
                            sourceSize.width: 200
                            sourceSize.height: 112
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }
                    }

                    Column {
                        anchors.left: thumb.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: wallpaperCard.current ? wallpaperCard.current.file
                                : themeModel.backgrounds.length === 0 ? "No wallpapers in this theme" : "None"
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize
                        }

                        Text {
                            visible: themeModel.backgrounds.length > 0
                            text: "Choose…"
                            color: Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize - 2
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: themeModel.backgrounds.length > 0
                        onClicked: root.window.pickerOpen = true
                    }
                }

                // ---- Brightness -----------------------------------------
                SectionTitle { text: "Brightness" }

                RowLayout {
                    visible: brightness.available
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "\u{F00DF}"
                        color: Colors.foreground
                        font.family: Fonts.icons
                        font.pixelSize: root.fontSize + 2
                    }

                    LevelSlider {
                        Layout.fillWidth: true
                        value: brightness.value
                        onMoved: v => brightness.set(v)
                    }

                    Text {
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(brightness.value * 100) + "%"
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: root.fontSize - 1
                    }
                }

                Label {
                    visible: !brightness.available
                    text: "Not available - no controllable backlight on this display"
                }

                // ---- Text size ------------------------------------------
                SectionTitle { text: "Text size" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: textScale.steps

                        Rectangle {
                            id: step
                            required property var modelData
                            readonly property bool current: Math.abs(textScale.factor - modelData.factor) < 0.01
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 4
                            color: current ? Colors.accent : stepMouse.containsMouse ? Colors.surface : "transparent"
                            border.color: current ? Colors.accent : Colors.border
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: step.modelData.label
                                color: step.current ? Colors.accentForeground : Colors.foreground
                                font.family: Fonts.family
                                font.pixelSize: root.fontSize - 2
                            }

                            MouseArea {
                                id: stepMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: textScale.set(step.modelData.factor)
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Applies to GTK apps (Files, ...) right away; the shell keeps its own size."
                    font.pixelSize: root.fontSize - 2
                }

                // ---- Display --------------------------------------------
                SectionTitle { text: "Display" }

                Repeater {
                    model: root.monitors

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "\u{F0379}"       // monitor
                            color: Colors.foreground
                            font.family: Fonts.icons
                            font.pixelSize: root.fontSize + 2
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize
                        }

                        Text {
                            text: modelData.width + "×" + modelData.height + " @ " + Math.round(modelData.refreshRate) + " Hz"
                                  + "   ·   scale " + Number(modelData.scale).toFixed(2).replace(/\.?0+$/, "")
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize - 1
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.monitors.length === 0 ? "No output information"
                        : "Resolution and scale are set per output in the host's hyprland_monitors."
                    font.pixelSize: root.fontSize - 2
                }
            }
        }
    }

    WallpaperPicker {
        anchors.fill: parent
        visible: root.window.pickerOpen
        model: themeModel
        fontSize: root.fontSize
        onDone: root.window.pickerOpen = false
    }
}
