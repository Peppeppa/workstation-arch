// Appearance - the window's content. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// Sections: Theme (dark + light, from the theme directories via the shared
// services/ThemeModel - the same runtime path as the bar's theme popup;
// Import opens ThemeImport.qml for theme repositories),
// Wallpaper (opens WallpaperPicker.qml), Bar (transparent background - the
// bar's own setting in BarLayout, the same one its right click flips),
// Brightness (only with a real backlight, services/BrightnessModel), Text
// size (the desktop's one text-size preference, `theme text-size`: shell,
// Ghostty, GTK - see Fonts.qml), Display (per output: scale presets as
// runtime state, Change opens the host's monitor config - services/
// DisplayModel; see docs/feature-architecture.md "Appearance").

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.bar
import qs.services
import qs.ui

FocusScope {
    id: root

    required property var window
    required property int fontSize
    required property string monitorConfig
    required property var terminal

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: {
        if (root.window.pickerOpen) root.window.pickerOpen = false;
        else if (root.window.importOpen) root.window.importOpen = false;
        else root.window.close();
    }

    ThemeModel {
        id: themeModel
    }

    BrightnessModel {
        id: brightness
    }

    DisplayModel {
        id: display
        configFile: root.monitorConfig
        terminal: root.terminal
    }

    // A row of preset chips (text size, display scale).
    component Chip: Rectangle {
        id: chip
        property string label
        property bool current: false
        signal picked
        Layout.fillWidth: true
        implicitHeight: Fonts.px(28)
        radius: 4
        color: current ? Colors.accent : chipMouse.containsMouse ? Colors.surface : "transparent"
        border.color: current ? Colors.accent : Colors.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: chip.label
            color: chip.current ? Colors.accentForeground : Colors.foreground
            font.family: Fonts.family
            font.pixelSize: root.fontSize - 2
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
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
        width: Fonts.px(480)
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
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    Text {
                        Layout.fillWidth: true
                        text: "Theme"
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: root.fontSize
                        font.bold: true
                    }
                    PopupButton {
                        label: "Import"
                        fontSize: root.fontSize - 2
                        onClicked: root.window.importOpen = true
                    }
                }

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
                    implicitHeight: Fonts.px(72)
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

                // ---- Bar ------------------------------------------------
                SectionTitle { text: "Bar" }

                // The bar's own background setting (BarLayout, persisted in
                // bar-layout.json) - right click on free bar space flips the
                // same value, so both always agree.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        implicitWidth: Fonts.px(16)
                        implicitHeight: Fonts.px(16)
                        radius: 3
                        color: BarLayout.background === "transparent" ? Colors.accent : "transparent"
                        border.color: BarLayout.background === "transparent" ? Colors.accent : Colors.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            visible: BarLayout.background === "transparent"
                            text: "\u{F012C}"         // check
                            color: Colors.accentForeground
                            font.family: Fonts.icons
                            font.pixelSize: root.fontSize - 2
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Transparent bar background"
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: root.fontSize - 1

                        MouseArea {
                            anchors.fill: parent
                            anchors.leftMargin: -Fonts.px(24)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BarLayout.setBackground(BarLayout.background === "transparent" ? "solid" : "transparent")
                        }
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
                        Layout.preferredWidth: Fonts.px(40)
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
                        model: themeModel.textSizes

                        Chip {
                            required property int modelData
                            label: String(modelData)
                            current: themeModel.textSize === modelData
                            onPicked: themeModel.setTextSize(modelData)
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "px - the shell, Ghostty (and Neovim in it) and GTK apps follow; other apps keep their own zoom."
                    font.pixelSize: root.fontSize - 2
                }

                // ---- Display --------------------------------------------
                SectionTitle { text: "Display" }

                Repeater {
                    model: display.monitors

                    ColumnLayout {
                        id: mon
                        required property var modelData
                        readonly property bool overridden: display.overrides[modelData.name] !== undefined
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "\u{F0379}"       // monitor
                                color: Colors.foreground
                                font.family: Fonts.icons
                                font.pixelSize: root.fontSize + 2
                            }

                            Column {
                                Layout.fillWidth: true

                                Text {
                                    width: parent.width
                                    text: mon.modelData.name
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    color: Colors.foreground
                                    font.family: Fonts.family
                                    font.pixelSize: root.fontSize
                                }

                                Text {
                                    text: mon.modelData.width + "×" + mon.modelData.height + " @ " + Math.round(mon.modelData.refreshRate) + " Hz"
                                    color: Colors.foregroundMuted
                                    font.family: Fonts.family
                                    font.pixelSize: root.fontSize - 1
                                }
                            }

                            // The real monitor configuration (host_vars) in Neovim.
                            PopupButton {
                                label: "Change"
                                fontSize: root.fontSize - 1
                                onClicked: {
                                    display.openConfig();
                                    root.window.close();
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: display.scales

                                Chip {
                                    required property real modelData
                                    label: modelData + "×"
                                    current: display.isCurrent(mon.modelData, modelData)
                                    onPicked: display.setScale(mon.modelData.name, modelData)
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "Scale " + Number(mon.modelData.scale).toFixed(2).replace(/\.?0+$/, "") + "×"
                                  + (mon.overridden ? " - chosen here (the host default is in its monitor config)" : " - the host default")
                            font.pixelSize: root.fontSize - 2
                        }

                        Text {
                            visible: mon.overridden
                            text: "Use the host default"
                            color: Colors.accent
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize - 2
                            font.underline: resetMouse.containsMouse

                            MouseArea {
                                id: resetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: display.resetScale(mon.modelData.name)
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: display.monitors.length === 0
                    text: "No output information"
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

    ThemeImport {
        anchors.fill: parent
        visible: root.window.importOpen
        model: themeModel
        fontSize: root.fontSize
        onDone: root.window.importOpen = false
        // keyboard back to the window (ThemeImport drops its field's focus),
        // so the next Escape closes Appearance
        onVisibleChanged: if (!visible) root.forceActiveFocus()
    }
}
