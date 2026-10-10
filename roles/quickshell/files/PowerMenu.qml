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
// input, and the IPC handler exposes only toggle/close (+ a read-only
// state), never an action.
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
// explicit user decision.
//
// Keyboard: the search field has the focus from the moment the menu opens -
// typing filters the actions (case-insensitive, every word must occur in
// the label or the entry's search words), an empty query shows all. Up/Down
// move the selection and wrap around (last -> first, first -> last, also in
// a filtered list); Enter runs the selected action, nothing with no match;
// Escape clears the query, or closes the menu when it is already empty.
// Letters (h/j/k/l included) are always search text. Hibernate is listed only if logind
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

    // danger: icon drawn in Colors.error (session-ending actions);
    // keywords: extra search words (the label always counts).
    readonly property var items: [
        { id: "lock",      label: "Lock",      icon: "", available: lockAvailable, hint: "not set up", keywords: "screen lock-screen" },
        { id: "suspend",   label: "Suspend",   icon: "", available: true, keywords: "sleep standby" },
        { id: "hibernate", label: "Hibernate", icon: "", available: true, keywords: "disk sleep" },
        { id: "logout",    label: "Logout",    icon: "", available: true, danger: true, keywords: "log out sign out exit session" },
        { id: "reboot",    label: "Reboot",    icon: "", available: true, danger: true, keywords: "restart" },
        { id: "shutdown",  label: "Shutdown",  icon: "", available: true, danger: true, keywords: "power off poweroff halt" }
    ].filter(item => item.id !== "hibernate" || hibernateAvailable)

    property string query: ""
    readonly property var shown: filterItems(items, query)
    property int selectedIndex: 0           // index into `shown`

    // Every word of the query occurs in the label or the keywords
    // (case-insensitive); an empty query matches everything.
    function matches(item, q) {
        const hay = (item.label + " " + (item.keywords || "")).toLowerCase();
        return q.toLowerCase().split(/\s+/).filter(w => w !== "").every(w => hay.indexOf(w) !== -1);
    }

    function filterItems(list, q) {
        return list.filter(item => matches(item, q));
    }

    // index + step, wrapped into 0..count-1 (0 for an empty list).
    function wrapIndex(index, step, count) {
        if (count <= 0) return 0;
        return ((index + step) % count + count) % count;
    }

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
        query = "";
        search.text = "";
        selectedIndex = 0;   // Lock - first entry, see header
        pointerAtOpen = Qt.point(-1, -1);
        visible = true;
    }

    // Hover moves the selection only once the pointer really moved: the
    // overlay maps under a resting pointer, and Qt reports that as hover
    // enter/position events - which replaced the Lock preselection with
    // whatever row lay under the pointer, so Enter logged out or shut down
    // (arch-dev). The first report after opening is only the anchor.
    property point pointerAtOpen: Qt.point(-1, -1)
    function hoverRow(area, mouse, index) {
        const p = area.mapToItem(null, mouse.x, mouse.y);
        if (pointerAtOpen.x < 0) pointerAtOpen = p;
        else if (p.x !== pointerAtOpen.x || p.y !== pointerAtOpen.y) selectedIndex = index;
    }

    // One transient surface at a time (bar/BarPopups.qml).
    function closePopup() {
        visible = false;
    }
    onVisibleChanged: {
        if (visible) {
            BarPopups.request(menu);
            search.forceActiveFocus();
        } else {
            BarPopups.release(menu);
        }
    }

    function moveSelection(step) {
        selectedIndex = wrapIndex(selectedIndex, step, shown.length);
    }

    function activate(item) {
        if (item && item.available) run(item.id);
    }

    // A new query selects its first (best) match.
    function setQuery(text) {
        query = text;
        selectedIndex = 0;
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
            if (shown.length > 0) activate(shown[selectedIndex]);
            return true;
        case Qt.Key_Escape:
            if (query !== "") search.text = "";
            else visible = false;
            return true;
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

        // For tests/diagnostics (read-only): {visible, query, shown: [ids], selected: id|null}.
        function state(): string {
            const sel = menu.shown.length > 0 ? menu.shown[menu.selectedIndex].id : null;
            return JSON.stringify({ visible: menu.visible, query: menu.query,
                                    shown: menu.shown.map(i => i.id), selected: sel });
        }
    }

    // Click outside the panel closes the menu. Declared before the panel, so the panel sits on top.
    MouseArea {
        anchors.fill: parent
        onClicked: menu.visible = false
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Fonts.px(260)
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

            // The search field: always focused while open; keys it does
            // not use for text go to handleKey first.
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                implicitHeight: Fonts.px(32)
                radius: 4
                color: Colors.surface
                border.color: Colors.borderActive
                border.width: 1

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text === ""
                    text: "System - type to search"
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: menu.fontSize
                }

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    focus: true
                    clip: true
                    color: Colors.foreground
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.accentForeground
                    font.family: Fonts.family
                    font.pixelSize: menu.fontSize
                    onTextChanged: menu.setQuery(text)
                    Keys.onPressed: event => event.accepted = menu.handleKey(event.key)
                }
            }

            Text {
                visible: menu.shown.length === 0
                Layout.leftMargin: 10
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                text: "No matching action"
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: menu.fontSize
            }

            Repeater {
                model: menu.shown

                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === menu.selectedIndex
                    readonly property color fg: selected ? Colors.accentForeground
                                              : !modelData.available ? Colors.foregroundMuted : Colors.foreground

                    Layout.fillWidth: true
                    implicitHeight: Fonts.px(36)
                    radius: 4
                    color: selected ? Colors.accent : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            Layout.preferredWidth: Fonts.px(18)
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
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: mouse => menu.hoverRow(rowArea, mouse, row.index)
                        onClicked: menu.activate(row.modelData)
                    }
                }
            }
        }
    }
}
