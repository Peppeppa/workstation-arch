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
//   suspend/hibernate: `systemctl <verb>` - logind's own polkit rules
//     allow these for the active local session, no sudo
//   reboot/shutdown: the same `systemctl reboot|poweroff`, but issued by
//     Hyprland's shutdown hook after the session ended like a logout
//     (`workstation_end_session`, roles/hyprland session.lua) - a direct
//     systemctl call killed the session scope at once and its helpers
//     crashed (coredumps)
//   logout: Hyprland's own exit dispatcher (same as mainMod+SHIFT+E)
//   lock: `loginctl lock-session` - the one lock path of the lock_idle
//     feature (logind Lock -> hypridle -> hyprlock); this menu never
//     locks by itself. Without lock_idle (lockAvailable false) it is
//     shown as unavailable - never a fake lock. Always the initial
//     selection (user decision): mainMod+Escape, Enter = lock.
//     Unavailable entries stay selectable so navigation stays linear;
//     only activating them does nothing.
// Every action runs immediately on Enter/click - no confirm step, by
// explicit user decision. Hibernate is listed only if logind
// reported it available when this host was provisioned
// (hibernateAvailable, templated by roles/quickshell) - a static host
// capability, never checked at runtime.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.bar

PanelWindow {
    id: menu

    required property int fontSize
    required property bool hibernateAvailable
    required property bool lockAvailable

    // danger: icon drawn in Colors.error (session-ending actions).
    readonly property var items: [
        { id: "lock",      label: "Lock",      icon: "", available: lockAvailable, hint: "not set up" },
        { id: "suspend",   label: "Suspend",   icon: "", available: true },
        { id: "hibernate", label: "Hibernate", icon: "", available: true },
        { id: "logout",    label: "Logout",    icon: "", available: true, danger: true },
        { id: "reboot",    label: "Reboot",    icon: "", available: true, danger: true },
        { id: "shutdown",  label: "Shutdown",  icon: "", available: true, danger: true }
    ].filter(item => item.id !== "hibernate" || hibernateAvailable)

    property int selectedIndex: 0

    // While open, the transparent surface covers the whole focused
    // output (Overlay layer: above the bar and fullscreen windows) so a
    // click anywhere outside the panel can close the menu. Closed, the
    // surface is unmapped - it takes no input and blocks nothing.
    // ExclusionMode.Ignore: an overlay must not reserve screen space.
    visible: false
    focusable: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-powermenu"

    // State is reset here, synchronously, rather than in
    // onVisibleChanged: a PanelWindow reports the visibility change only
    // once its surface is mapped, so the old selection would briefly
    // still apply.
    function open() {
        selectedIndex = 0;   // Lock - first entry, see header
        visible = true;
    }

    // One transient surface at a time (bar/BarPopups.qml).
    function closePopup() {
        visible = false;
    }
    onVisibleChanged: {
        if (visible) {
            BarPopups.request(menu);
            keyHandler.forceActiveFocus();
        } else {
            BarPopups.release(menu);
        }
    }

    function moveSelection(step) {
        selectedIndex = Math.max(0, Math.min(items.length - 1, selectedIndex + step));
    }

    function activate(item) {
        if (item.available) run(item.id);
    }

    // Fixed action table - the only place a command is defined.
    function commandFor(id) {
        switch (id) {
        case "lock":      return { argv: ["loginctl", "lock-session"] };
        case "suspend":   return { argv: ["systemctl", "suspend"] };
        case "hibernate": return { argv: ["systemctl", "hibernate"] };
        case "reboot":    return { dispatch: "workstation_end_session(\"reboot\")" };
        case "shutdown":  return { dispatch: "workstation_end_session(\"poweroff\")" };
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

    // Click outside the panel closes the menu. Declared before the panel, so the panel sits on top.
    MouseArea {
        anchors.fill: parent
        onClicked: menu.visible = false
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
        border.color: Colors.borderActive
        border.width: 1

        // Swallows clicks on the panel's own padding/header/gaps so they
        // never reach the close-on-outside-click area underneath.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 4   // uniform gap between all entries

            Text {
                Layout.leftMargin: 10
                Layout.bottomMargin: 4
                text: "System"
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: menu.fontSize
            }

            Repeater {
                model: menu.items

                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === menu.selectedIndex
                    readonly property color fg: selected ? Colors.accentForeground
                                              : !modelData.available ? Colors.foregroundMuted : Colors.foreground

                    Layout.fillWidth: true
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
                            font.family: Fonts.icons
                            font.pixelSize: menu.fontSize + 2
                            color: row.modelData.danger && !row.selected ? Colors.error : row.fg
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            font.family: Fonts.family
                            font.pixelSize: menu.fontSize
                            color: row.fg
                        }

                        Text {
                            visible: !row.modelData.available
                            text: row.modelData.hint || ""
                            font.family: Fonts.family
                            font.pixelSize: menu.fontSize - 2
                            color: row.selected ? Colors.accentForeground : Colors.foregroundMuted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: menu.selectedIndex = row.index
                        onClicked: menu.activate(row.modelData)
                    }
                }
            }
        }
    }
}
