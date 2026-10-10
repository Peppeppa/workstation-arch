// The OS menu (mainMod+Space): the host - window, navigation, keyboard.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. See docs/feature-architecture.md "OS menu".
//
// Root list: Applications, Settings (Appearance, Network, Firewall),
// Packages (Install / Remove: Arch, AUR, Flatpak), System. Pages
// that live in the menu (RootPage, AppsPage, SettingsPage) are separate
// files; destinations outside it are handed over, never re-implemented:
//   Appearance -> close, open the Appearance window (appearance/)
//   Network    -> close, start nm-connection-editor (NetworkManager's own
//                 editor, on demand, as a transient systemd user unit; no
//                 applet)
//   Firewall   -> close, open the Firewall window (firewall/: the user's LAN
//                 sharing rules)
//   Packages   -> Install / Remove -> Arch / AUR / Flatpak: close, start
//                 `workstation-pkg <action>` (roles/packages, fzf) in the
//                 terminal, as a transient systemd user unit
//   System     -> close, open the existing Power Menu (sole owner of lock/
//                 suspend/hibernate/logout/reboot/shutdown)
//
// Keyboard: type to search - the first printable key on a list page opens
// the search (SearchPage: the menu's own entries + applications, best
// match preselected, Enter runs it); an emptied query or Escape returns to
// the normal menu. On the lists: Down/Up (or Ctrl+J/Ctrl+K) move,
// Right/Enter open, Left back; plain letters are always search text. In
// Applications the search field has the focus (Up/Down/Enter). Escape
// with no query closes the whole menu.
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
    property var firewall: null             // FirewallWindow (core)
    property var powerMenu: null            // PowerMenu (feature power_menu) or null
    required property var terminal          // argv of the terminal (hyprland_terminal)

    property string page: "root"            // root | apps | settings | packages | packages-install | packages-remove | search

    // The menu's entries - the ONE list the pages show and the search finds
    // (keywords only help finding); OsMenu.activate() is what each does.
    readonly property var rootEntries: [
        { id: "apps", label: "Applications", icon: "\u{F003B}", sub: true, keywords: "apps programs launcher" },
        { id: "settings", label: "Settings", icon: "\u{F0493}", sub: true, keywords: "preferences configuration" },
        { id: "packages", label: "Packages", icon: "\u{F03D6}", sub: true,
          keywords: "install remove uninstall software arch pacman aur yay flatpak flathub" },
        { id: "system", label: "System", icon: "\u{F0425}", sub: false,
          keywords: "power lock suspend hibernate logout reboot restart shutdown update upgrade snapshot" }
    ].filter(e => e.id !== "system" || powerMenu !== null)
    readonly property var settingsEntries: [
        { id: "appearance", label: "Appearance", icon: "\u{F03D8}", sub: false,
          keywords: "theme dark light wallpaper bar brightness text size font display scale monitor" },
        { id: "network", label: "Network", icon: "\u{F06F3}", sub: false,
          keywords: "wifi wi-fi wlan ethernet vpn connections dns ip eduroam" },
        { id: "firewall", label: "Firewall", icon: "\u{F0565}", sub: false,
          keywords: "ports sharing lan share rules" }
    ]
    readonly property var packagesEntries: [
        { id: "packages-install", label: "Install", icon: "\u{F0120}", sub: true, title: "Install Packages",
          keywords: "install add software" },
        { id: "packages-remove", label: "Remove", icon: "\u{F09E7}", sub: true, title: "Remove Packages",
          keywords: "remove uninstall delete software" }
    ]
    // Leaves: label in the list, title in the search (both levels named).
    readonly property var installEntries: [
        { id: "pkg-install-arch", label: "Arch Packages", title: "Install Arch Packages", icon: "\u{F08C7}", sub: false,
          keywords: "install arch pacman official repository packages" },
        { id: "pkg-install-aur", label: "AUR Packages", title: "Install AUR Packages", icon: "\u{F0B58}", sub: false,
          keywords: "install aur yay arch user repository packages" },
        { id: "pkg-install-flatpak", label: "Flatpaks", title: "Install Flatpaks", icon: "\u{F0614}", sub: false,
          keywords: "install flatpak flathub apps applications" }
    ]
    readonly property var removeEntries: [
        { id: "pkg-remove-arch", label: "Arch Packages", title: "Remove Arch Packages", icon: "\u{F08C7}", sub: false,
          keywords: "remove uninstall arch pacman packages" },
        { id: "pkg-remove-aur", label: "AUR Packages", title: "Remove AUR Packages", icon: "\u{F0B58}", sub: false,
          keywords: "remove uninstall aur yay packages" },
        { id: "pkg-remove-flatpak", label: "Flatpaks", title: "Remove Flatpaks", icon: "\u{F0614}", sub: false,
          keywords: "remove uninstall flatpak flathub apps applications" }
    ]
    // Everything the type-to-search finds: [{e, hint}] - the same entries.
    readonly property var searchEntries: rootEntries.map(e => ({ e: e, hint: "" }))
        .concat(settingsEntries.map(e => ({ e: e, hint: "Settings" })))
        .concat(packagesEntries.concat(installEntries, removeEntries).map(e => ({ e: e, hint: "Packages" })))

    function open(p) {
        page = p || "root";
        rootPage.reset();
        appsPage.reset();
        settingsPage.reset();
        packagesPage.reset();
        installPage.reset();
        removePage.reset();
        searchPage.reset();
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

    // Type-to-search: the first printable key on a list page.
    function startSearch(text) {
        page = "search";
        searchPage.begin(text);
    }

    // Query emptied or Escape: back to the normal menu.
    function endSearch() {
        searchPage.reset();
        page = "root";
        rootPage.reset();
        focusPage();
    }

    function back() {
        if (page === "packages-install" || page === "packages-remove") page = "packages";
        else if (page !== "root") page = "root";
        else return;
        focusPage();
    }

    // A Packages leaf: the picker in the terminal, detached from Quickshell.
    function runPackages(action) {
        Quickshell.execDetached(["systemd-cat", "-t", "app-launch", "-p", "err", "--",
                                 "systemd-run", "--user", "--quiet", "--collect", "--"]
                                .concat(menu.terminal, ["-e", Quickshell.env("HOME") + "/.local/bin/workstation-pkg", action]));
    }

    function focusPage() {
        if (page === "apps") appsPage.takeFocus();
        else if (page === "search") searchPage.takeFocus();
        else if (page === "settings") settingsPage.forceActiveFocus();
        else if (page === "packages") packagesPage.forceActiveFocus();
        else if (page === "packages-install") installPage.forceActiveFocus();
        else if (page === "packages-remove") removePage.forceActiveFocus();
        else rootPage.forceActiveFocus();
    }

    // Root entries; the destination decides what "open" means.
    function activate(id) {
        switch (id) {
        case "apps":
        case "settings":
            page = id;
            if (id === "settings") settingsPage.reset();
            searchPage.reset();             // opened from the search: no stale query
            focusPage();
            break;
        case "packages":
        case "packages-install":
        case "packages-remove":
            page = id;
            ({ "packages": packagesPage, "packages-install": installPage, "packages-remove": removePage })[id].reset();
            searchPage.reset();
            focusPage();
            break;
        case "pkg-install-arch":
        case "pkg-install-aur":
        case "pkg-install-flatpak":
        case "pkg-remove-arch":
        case "pkg-remove-aur":
        case "pkg-remove-flatpak":
            close();
            runPackages(id.replace(/^pkg-/, ""));
            break;
        case "appearance":
            close();
            if (appearance) appearance.open();
            break;
        case "firewall":
            close();
            if (firewall) firewall.open();
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
        width: Fonts.px(460)
        height: menu.page === "apps" ? appsPage.implicitHeight + 24
              : menu.page === "settings" ? settingsPage.implicitHeight + 24
              : menu.page === "search" ? searchPage.implicitHeight + 24
              : menu.page === "packages" ? packagesPage.implicitHeight + 24
              : menu.page === "packages-install" ? installPage.implicitHeight + 24
              : menu.page === "packages-remove" ? removePage.implicitHeight + 24
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
            entries: menu.rootEntries
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

        ListPage {
            id: packagesPage
            visible: menu.page === "packages"
            anchors.fill: parent
            anchors.margins: 12
            menu: menu
            title: "Packages"
            entries: menu.packagesEntries
        }

        ListPage {
            id: installPage
            visible: menu.page === "packages-install"
            anchors.fill: parent
            anchors.margins: 12
            menu: menu
            title: "Packages \u203A Install"
            entries: menu.installEntries
        }

        ListPage {
            id: removePage
            visible: menu.page === "packages-remove"
            anchors.fill: parent
            anchors.margins: 12
            menu: menu
            title: "Packages \u203A Remove"
            entries: menu.removeEntries
        }

        SearchPage {
            id: searchPage
            visible: menu.page === "search"
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

        // Open directly on a page: root | apps | settings | packages
        // (search starts by typing).
        function openPage(name: string): void {
            menu.open(name);
        }

        // For tests/diagnostics: {visible, page, index, query, search,
        // results: [labels], selected}.
        function state(): string {
            return JSON.stringify({ visible: menu.visible, page: menu.page,
                                    index: rootPage.index, query: appsPage.query,
                                    search: searchPage.query,
                                    results: searchPage.results.map(r => r.kind === "app" ? "app:" + r.entry.name : "entry:" + r.id),
                                    selected: searchPage.selectedIndex });
        }
    }
}
