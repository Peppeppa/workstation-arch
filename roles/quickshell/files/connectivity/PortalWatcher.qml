// FEATURE: connectivity - opens a captive portal's login page by itself.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Instantiated once by shell.qml (not per bar).
//
// Event-driven: NetworkManager's own connectivity state (its check, never
// one of ours) turning "portal" starts the portal-login helper once - a
// Chromium window of its own (see portal-login.py) - the way phones and
// other desktops open their portal page. Re-armed only after connectivity
// has left "portal" (logged in, disconnected, another network), so a
// closed window is not reopened while the same portal stays; the bar's
// network popup keeps "Log in" for that. No timer, no process while idle.

import QtQuick
import Quickshell
import Quickshell.Networking

Scope {
    readonly property bool portal: Networking.connectivity === NetworkConnectivity.Portal
    readonly property string command: Quickshell.env("HOME") + "/.local/libexec/workstation/portal-login"

    function check() {
        if (!portal) return;
        Quickshell.execDetached(["systemd-cat", "-t", "app-launch", "-p", "err", "--",
                                 "systemd-run", "--user", "--quiet", "--collect", "--", command]);
    }

    onPortalChanged: check()
    Component.onCompleted: check()
}
