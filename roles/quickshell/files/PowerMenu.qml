// FEATURE: power_menu (see group_vars/all.yml power_menu_enabled and
// docs/feature-architecture.md). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. Only deployed (and
// only instantiated by shell.qml) while the feature is enabled.
//
// A small centered session/power overlay inside the already-running
// Quickshell process, toggled like the launcher via Quickshell's own IPC
// (`qs ipc call powermenu toggle` from Hyprland's mainMod+Escape bind).
// Closed, it is an unmapped layer surface: no timer, no polling, no
// process - commands run only when an action is actually chosen.
//
// Actions are a fixed table mapped to fixed argv lists / one fixed
// Hyprland dispatch (see commandFor) - no shell, no string built from
// input, and the IPC handler exposes only toggle/close, never an action.
//   suspend/hibernate/reboot/shutdown: `systemctl <verb>` - logind's own
//     polkit rules allow these for the active local session, no sudo
//   logout: Hyprland's own exit dispatcher (same as mainMod+SHIFT+E)
//   lock: shown but unavailable - no lockscreen exists yet (Lock/Idle
//     is its own later milestone); never a fake lock
// Logout/Reboot/Shutdown need a second step (Cancel is preselected);
// Suspend/Hibernate run directly. Hibernate is listed only if logind
// reported it available when this host was provisioned
// (hibernateAvailable, templated by roles/quickshell) - a static host
// capability, never checked at runtime.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

PanelWindow {
    id: menu

    required property int fontSize
    required property bool hibernateAvailable

    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"

    // group: visual block (session vs. power). confirm: needs the
    // second step. danger: icon/confirm label drawn in Colors.error.
    readonly property var items: [
        { id: "lock",      label: "Lock",      icon: "", group: 0, available: false, hint: "not set up" },
        { id: "suspend",   label: "Suspend",   icon: "", group: 0, available: true },
        { id: "hibernate", label: "Hibernate", icon: "", group: 0, available: true },
        { id: "logout",    label: "Logout",    icon: "", group: 0, available: true, confirm: true, danger: true },
        { id: "reboot",    label: "Reboot",    icon: "", group: 1, available: true, confirm: true, danger: true },
        { id: "shutdown",  label: "Shutdown",  icon: "", group: 1, available: true, confirm: true, danger: true }
    ].filter(item => item.id !== "hibernate" || hibernateAvailable)

    property int selectedIndex: 0
    property var confirming: null   // the item awaiting confirmation, or null
    property int confirmChoice: 0   // 0 = Cancel, 1 = confirm

    visible: false
    focusable: true
    color: "transparent"
    implicitWidth: 280
    implicitHeight: panel.implicitHeight + 20

    // State is reset here, synchronously, rather than in
    // onVisibleChanged: a PanelWindow reports the visibility change only
    // once its surface is mapped, so the old selection would briefly
    // still apply.
    function open() {
        confirming = null;
        confirmChoice = 0;
        selectedIndex = firstAvailable();
        visible = true;
    }

    onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

    function firstAvailable() {
        for (let i = 0; i < items.length; i++)
            if (items[i].available) return i;
        return 0;
    }

    function moveSelection(step) {
        for (let i = selectedIndex + step; i >= 0 && i < items.length; i += step) {
            if (items[i].available) {
                selectedIndex = i;
                return;
            }
        }
    }

    function activate(item) {
        if (!item.available) return;
        if (item.confirm) {
            confirming = item;
            confirmChoice = 0;
        } else {
            run(item.id);
        }
    }

    // Fixed action table - the only place a command is defined.
    function commandFor(id) {
        switch (id) {
        case "suspend":   return { argv: ["systemctl", "suspend"] };
        case "hibernate": return { argv: ["systemctl", "hibernate"] };
        case "reboot":    return { argv: ["systemctl", "reboot"] };
        case "shutdown":  return { argv: ["systemctl", "poweroff"] };
        case "logout":    return { dispatch: "hl.dsp.exit()" };
        default:          return null;
        }
    }

    function run(id) {
        const cmd = commandFor(id);
        // Close first so the menu is not still showing after resume.
        visible = false;
        if (!cmd) return;
        if (cmd.argv) Quickshell.execDetached(cmd.argv);
        else Hyprland.dispatch(cmd.dispatch);
    }

    function handleKey(key) {
        if (confirming) {
            switch (key) {
            case Qt.Key_Left: case Qt.Key_Right: case Qt.Key_Tab: case Qt.Key_Backtab:
                confirmChoice = 1 - confirmChoice;
                return true;
            case Qt.Key_Return: case Qt.Key_Enter:
                if (confirmChoice === 1) run(confirming.id);
                else confirming = null;
                return true;
            case Qt.Key_Escape:
                confirming = null;
                return true;
            }
            return false;
        }
        switch (key) {
        case Qt.Key_Up:     moveSelection(-1); return true;
        case Qt.Key_Down:   moveSelection(1); return true;
        case Qt.Key_Return: case Qt.Key_Enter:
            activate(items[selectedIndex]);
            return true;
        case Qt.Key_Escape: visible = false; return true;
        }
        return false;
    }

    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            if (menu.visible) menu.visible = false;
            else menu.open();
        }

        function close(): void {
            menu.visible = false;
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => event.accepted = menu.handleKey(event.key)
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 260
        implicitHeight: content.implicitHeight + 20
        radius: 8
        color: Colors.background
        border.color: Colors.border
        border.width: 1

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 2

            Text {
                Layout.leftMargin: 10
                Layout.bottomMargin: 4
                text: menu.confirming ? menu.confirming.label + "?" : "System"
                color: menu.confirming ? Colors.text : Colors.textMuted
                font.pixelSize: menu.fontSize
                font.bold: menu.confirming !== null
            }

            // Normal state: the action list.
            Repeater {
                model: menu.confirming ? [] : menu.items

                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === menu.selectedIndex && modelData.available
                    readonly property color fg: !modelData.available ? Colors.textMuted
                                              : selected ? Colors.accentText : Colors.text

                    Layout.fillWidth: true
                    Layout.topMargin: index > 0 && menu.items[index - 1].group !== modelData.group ? 10 : 0
                    implicitHeight: 36
                    radius: 4
                    color: selected ? Colors.accent : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: row.modelData.icon
                            font.family: menu.iconFont
                            font.pixelSize: menu.fontSize + 2
                            color: row.modelData.danger && !row.selected ? Colors.error : row.fg
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            font.pixelSize: menu.fontSize
                            color: row.fg
                        }

                        Text {
                            visible: !row.modelData.available
                            text: row.modelData.hint || ""
                            font.pixelSize: menu.fontSize - 2
                            color: Colors.textMuted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (row.modelData.available) menu.selectedIndex = row.index
                        onClicked: menu.activate(row.modelData)
                    }
                }
            }

            // Confirmation state: Cancel (preselected) / <Action>.
            RowLayout {
                visible: menu.confirming !== null
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                Repeater {
                    model: menu.confirming ? ["Cancel", menu.confirming.label] : []

                    Rectangle {
                        id: button
                        required property string modelData
                        required property int index
                        readonly property bool selected: index === menu.confirmChoice

                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 4
                        color: selected ? Colors.accent : Colors.surface

                        Text {
                            anchors.centerIn: parent
                            text: button.modelData
                            font.pixelSize: menu.fontSize
                            color: button.selected ? Colors.accentText
                                 : button.index === 1 ? Colors.error : Colors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: menu.confirmChoice = button.index
                            onClicked: {
                                if (button.index === 1) menu.run(menu.confirming.id);
                                else menu.confirming = null;
                            }
                        }
                    }
                }
            }
        }
    }
}
