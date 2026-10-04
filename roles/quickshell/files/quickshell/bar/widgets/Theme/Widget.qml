// Bar widget "theme": moon (dark) / sun (light) from the active theme.
// Left click: `theme toggle` (one-shot helper). Right click: the theme
// popup (Popup.qml: dark/light theme pickers + wallpapers). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.

import QtQuick
import Quickshell
import qs
import qs.bar

BarWidget {
    id: root

    icon: Colors.mode === "light" ? "" : ""
    onClicked: button => {
        if (button === Qt.RightButton) root.togglePopup();
        else if (button === Qt.LeftButton) Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/theme", "toggle"]);
    }

    Loader {
        active: root.popupOpen
        sourceComponent: Popup {
            owner: root
            onCloseRequested: root.closePopup()
        }
    }
}
