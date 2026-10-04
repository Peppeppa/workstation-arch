// Bar widget "theme" - its popup (right click on the theme icon). Managed
// by Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// Two dropdowns: the preferred dark theme and the preferred light theme.
// Their entries come from the `theme` helper (`theme status --json`), run
// when the popup opens and again whenever the applied theme changes while
// it is open - the theme directories are the only registry, nothing is
// listed here. Picking an entry runs
// `theme select <slot> <id>`: the choice is persisted, and applied right
// away only if that slot's mode is the active one (it never switches the
// mode). The helper validates first, so a broken theme can't be applied.
//
// With the wallpaper feature (WallpaperPicker.qml, loaded only then) the
// popup also shows the active theme's wallpapers as thumbnails.
//
// A BarPopup: exists only while open - no process, no timer while closed.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.bar

BarPopup {
    id: dialog

    readonly property bool wallpaperEnabled: BarFeatures.wallpaper

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/theme"

    // `theme status --json`: {state: {dark, light, mode}, dark: [{id, name}], light: [...], invalid: {...}}
    property var status: null
    property string openSlot: ""      // "", "dark" or "light": which dropdown is expanded
    property int highlighted: -1      // keyboard/hover row in the open dropdown
    property string errorText: ""

    // A request while a status run is in flight is not dropped: that run may
    // have read the state before the change, so one more run follows it.
    property bool refreshPending: false

    function refresh() {
        if (statusProc.running) refreshPending = true;
        else statusProc.running = true;
    }

    // Every applied change - mode toggle from the bar icon, `theme` on the
    // CLI, a pick in this dialog - ends in the helper's
    // `qs ipc call theme reload`, which reloads Colors from colors.json.
    // That is the event: re-read the status (wallpaper list + selection of
    // the now active theme). No watcher, no timer.
    Connections {
        target: Colors
        function onDataChanged() {
            dialog.refresh();
        }
    }

    function options(slot) {
        return status ? status[slot] : [];
    }

    function selectedId(slot) {
        return status && status.state ? status.state[slot] : "";
    }

    function nameOf(slot, id) {
        const hit = options(slot).find(t => t.id === id);
        return hit ? hit.name : id;
    }

    function toggleDropdown(slot) {
        if (openSlot === slot) {
            openSlot = "";
            return;
        }
        openSlot = slot;
        highlighted = options(slot).findIndex(t => t.id === selectedId(slot));
    }

    function choose(slot, id) {
        openSlot = "";
        if (id === selectedId(slot) || actionProc.running) return;
        actionProc.command = [helper, "select", slot, id];
        actionProc.running = true;
    }

    function setWallpaper(file) {
        if (actionProc.running) return;
        actionProc.command = [helper, "wallpaper", "set", file];
        actionProc.running = true;
    }

    function handleKey(key) {
        if (key === Qt.Key_Escape) {
            if (openSlot !== "") {
                openSlot = "";
                return true;
            }
            return false;
        }
        if (openSlot === "") return false;
        const count = options(openSlot).length;
        if (key === Qt.Key_Down) { highlighted = Math.min(highlighted + 1, count - 1); return true; }
        if (key === Qt.Key_Up) { highlighted = Math.max(highlighted - 1, 0); return true; }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && highlighted >= 0 && highlighted < count) {
            choose(openSlot, options(openSlot)[highlighted].id);
            return true;
        }
        return false;
    }

    Process {
        id: statusProc
        command: [dialog.helper, "status", "--json"]
        onExited: {
            if (dialog.refreshPending) {
                dialog.refreshPending = false;
                running = true;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    dialog.status = JSON.parse(text);
                } catch (e) {
                    dialog.errorText = "theme helper returned no status";
                }
            }
        }
    }

    Process {
        id: actionProc
        stderr: StdioCollector { id: actionErr }
        onExited: exitCode => {
            dialog.errorText = exitCode === 0 ? "" : actionErr.text.trim();
            dialog.refresh();
        }
    }

    panelWidth: wallpaperEnabled ? 340 : 280
    keyFilter: event => dialog.handleKey(event.key)
    Component.onCompleted: refresh()

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        Repeater {
            model: ["dark", "light"]

            ColumnLayout {
                id: section
                required property string modelData
                readonly property string slot: modelData
                readonly property bool active: dialog.status && dialog.status.state
                                               && dialog.status.state.mode === slot

                Layout.fillWidth: true
                Layout.topMargin: slot === "light" ? 6 : 0
                spacing: 4

                Text {
                    text: (section.slot === "dark" ? "Dark theme" : "Light theme")
                          + (section.active ? "  ·  active" : "")
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: dialog.fontSize - 1
                }

                // The dropdown button: current choice + chevron.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 4
                    color: Colors.surface
                    border.color: dialog.openSlot === section.slot ? Colors.borderActive : Colors.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10

                        Text {
                            Layout.fillWidth: true
                            text: dialog.status ? dialog.nameOf(section.slot, dialog.selectedId(section.slot)) : "…"
                            elide: Text.ElideRight
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: dialog.fontSize
                        }

                        Text {
                            text: dialog.openSlot === section.slot ? "" : ""   // chevron up/down
                            color: Colors.foregroundMuted
                            font.family: Fonts.icons
                            font.pixelSize: dialog.fontSize - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: dialog.toggleDropdown(section.slot)
                    }
                }

                // Expanded list: only themes whose marker matches this slot.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: dialog.openSlot === section.slot
                    spacing: 2

                    Repeater {
                        model: dialog.openSlot === section.slot ? dialog.options(section.slot) : []

                        Rectangle {
                            id: option
                            required property var modelData
                            required property int index
                            readonly property bool current: modelData.id === dialog.selectedId(section.slot)
                            readonly property bool lit: index === dialog.highlighted

                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 4
                            color: lit ? Colors.accent : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                Text {
                                    Layout.fillWidth: true
                                    text: option.modelData.name
                                    elide: Text.ElideRight
                                    color: option.lit ? Colors.accentForeground : Colors.foreground
                                    font.family: Fonts.family
                                    font.pixelSize: dialog.fontSize
                                }

                                Text {
                                    visible: option.current
                                    text: ""   // check: the current choice
                                    color: option.lit ? Colors.accentForeground : Colors.accent
                                    font.family: Fonts.icons
                                    font.pixelSize: dialog.fontSize - 1
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: dialog.highlighted = option.index
                                onClicked: dialog.choose(section.slot, option.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // FEATURE: wallpaper.
        Loader {
            Layout.fillWidth: true
            active: dialog.wallpaperEnabled
            visible: active
            Component.onCompleted: if (dialog.wallpaperEnabled) setSource("WallpaperPicker.qml", { dialog: dialog })
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: dialog.errorText !== ""
            text: dialog.errorText
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: Colors.error
            font.family: Fonts.family
            font.pixelSize: dialog.fontSize - 2
        }
    }
}
