// The OS menu (mainMod+Space): the host - window, navigation, keyboard.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. See docs/feature-architecture.md "OS menu".
//
// Root list: Applications, Appearance, Network, Settings, System. Pages
// that live in the menu (RootPage, AppsPage, SettingsPage) are separate
// files; destinations outside it are handed over, never re-implemented:
//   Appearance -> close, open the Appearance window (appearance/)
//   Network    -> close, start nm-connection-editor (NetworkManager's own
//                 editor, on demand, as a transient systemd user unit; no
//                 applet)
//   System     -> close, open the existing Power Menu (sole owner of lock/
//                 suspend/hibernate/logout/reboot/shutdown)
//
// Keyboard (menu/list pages): j/Down next, k/Up previous, l/Right/Enter
// open, h/Left back. In Applications the search field has the focus and
// every letter is search input (no Vim keys); Up/Down/Enter work there.
// Escape ALWAYS closes the whole menu, from any page.
//
// While open the transparent surface covers the focused output below the
// bar strip; a click outside the panel closes it. Closed, the window is
// unmapped - no surface, no input region.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar

PanelWindow {
    id: menu

    required property int fontSize
    property var appearance: null           // AppearanceWindow (core)
    property var powerMenu: null            // PowerMenu (feature power_menu) or null

    property string page: "root"            // root | apps | settings

    function open(p) {
        page = p || "root";
        rootPage.reset();
        appsPage.reset();
        visible = true;
        focusPage();
    }

    function close() {
        visible = false;
    }

    // One transient surface at a time (bar/BarPopups.qml).
    function closePopup() {
        close();
    }
    onVisibleChanged: visible ? BarPopups.request(menu) : BarPopups.release(menu)

    function back() {
        if (page !== "root") {
            page = "root";
            focusPage();
        }
    }

    function focusPage() {
        if (page === "apps") appsPage.takeFocus();
        else if (page === "settings") settingsPage.forceActiveFocus();
        else rootPage.forceActiveFocus();
    }

    // Root entries; the destination decides what "open" means.
    function activate(id) {
        switch (id) {
        case "apps":
        case "settings":
            page = id;
            focusPage();
            break;
        case "appearance":
            close();
            if (appearance) appearance.open();
            break;
        case "network":
            close();
            // Its own transient user unit (detached from Quickshell; the
            // editor's output in the journal); a launch that fails before
            // that (systemd-run's own error) goes to the journal as
            // `-t app-launch` at err priority (with --quiet that is its only
            // output) - see repo-diagnose.
            Quickshell.execDetached(["systemd-cat", "-t", "app-launch", "-p", "err", "--",
                                     "systemd-run", "--user", "--quiet", "--collect", "--", "nm-connection-editor"]);
            break;
        case "system":
            close();
            if (powerMenu) powerMenu.open();
            else Log.warn("osmenu", "System: no power menu (power_menu_enabled is false)");
            break;
        }
    }

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
    WlrLayershell.namespace: "quickshell-osmenu"
    // The bar strip stays out of the input region (bar clicks reach the bar).
    mask: Region {
        item: outside
    }

    Item {
        id: outside
        y: BarStyle.height
        width: menu.width
        height: menu.height - BarStyle.height
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
    }

    // Fixed top edge (for the tallest page): switching pages never moves it.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(40, Math.round((menu.height - 420) / 2))
        width: 460
        height: menu.page === "apps" ? appsPage.implicitHeight + 24
              : menu.page === "settings" ? settingsPage.implicitHeight + 24
              : rootPage.implicitHeight + 24
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        // Clicks on the panel itself must not close the menu.
        MouseArea {
            anchors.fill: parent
        }

        RootPage {
            id: rootPage
            visible: menu.page === "root"
            anchors.fill: parent
            anchors.margins: 12
            menu: menu
        }

        AppsPage {
            id: appsPage
            visible: menu.page === "apps"
            anchors.fill: parent
            anchors.margins: 12
            menu: menu
        }

        SettingsPage {
            id: settingsPage
            visible: menu.page === "settings"
            anchors.fill: parent
            anchors.margins: 12
            menu: menu
        }
    }

    // IPC "osmenu": Hyprland's mainMod+Space runs `qs ipc call osmenu toggle`.
    IpcHandler {
        target: "osmenu"

        function toggle(): void {
            if (menu.visible) menu.close();
            else menu.open("root");
        }

        function close(): void {
            menu.close();
        }

        // Open directly on a page: root | apps | settings.
        function openPage(name: string): void {
            menu.open(name);
        }

        // For tests/diagnostics: {visible, page, index, query}.
        function state(): string {
            return JSON.stringify({ visible: menu.visible, page: menu.page,
                                    index: rootPage.index, query: appsPage.query });
        }
    }
}
