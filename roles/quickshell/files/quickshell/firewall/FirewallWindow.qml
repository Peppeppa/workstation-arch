// Firewall - the floating window (OS menu -> Settings -> Firewall). Managed
// by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. See docs/feature-architecture.md "Firewall".
//
// Frame only, the same as Appearance: overlay surface on the focused output
// below the bar strip, click outside / Escape closes. Its content
// (FirewallContent.qml) and with it the model's helper calls exist only
// while the window is open; closed, the window is unmapped - no surface,
// no process, no timer.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar

PanelWindow {
    id: win

    required property int fontSize
    property bool addOpen: false            // "Add" dialog (AddRule.qml)

    function open() {
        if (hiddenForAuth) return;             // the polkit prompt is up - do not cover it
        addOpen = false;
        visible = true;
    }

    // While the root helper runs (a rule change in flight) the window stays:
    // closing destroys the content and with it the helper's Process. Every
    // close path (Escape, click outside, Super+Q, another popup) comes here.
    readonly property bool busy: content.item !== null && content.item.model.busy

    // A change needs the administrator password (polkit auth_admin_keep,
    // Security Hardening v1.1, S3-A): while it runs the window is hidden -
    // this overlay would sit over the polkit agent's window and keep the
    // keyboard - but its content (and the helper's Process) stays loaded;
    // it comes back with the result. Within polkit's ~5 min no prompt
    // appears and the window is gone only for the helper's run.
    property bool hiddenForAuth: false
    onBusyChanged: {
        if (busy && visible) {
            hiddenForAuth = true;
            visible = false;
        } else if (!busy && hiddenForAuth) {
            hiddenForAuth = false;
            visible = true;
        }
    }

    function close() {
        if (busy) return;
        addOpen = false;
        visible = false;
    }

    // One transient surface at a time (bar/BarPopups.qml).
    function closePopup() {
        close();
    }
    onVisibleChanged: visible ? BarPopups.request(win) : BarPopups.release(win)

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
    WlrLayershell.namespace: "quickshell-firewall"
    mask: Region {
        item: outside
    }

    Item {
        id: outside
        y: BarStyle.height
        width: win.width
        height: win.height - BarStyle.height
    }

    MouseArea {
        anchors.fill: parent
        onClicked: win.addOpen ? win.addOpen = false : win.close()
    }

    Loader {
        id: content
        anchors.fill: parent
        active: win.visible || win.hiddenForAuth
        sourceComponent: FirewallContent {
            window: win
            fontSize: win.fontSize
        }
    }

    // IPC "firewall". The actions go through the same functions as the
    // buttons (tests drive the window with them; every change still runs
    // the root helper through pkexec + polkit, nothing is bypassed).
    IpcHandler {
        target: "firewall"

        function toggle(): void {
            if (win.visible) win.close();
            else win.open();
        }

        function close(): void {
            win.close();
        }

        // {visible, hiddenForAuth, add, busy, error, dialogError, rules: [...]}
        function state(): string {
            const c = content.item;
            return JSON.stringify({ visible: win.visible, hiddenForAuth: win.hiddenForAuth, add: win.addOpen,
                                    busy: c ? c.model.busy : false,
                                    error: c ? c.model.errorText : "",
                                    dialogError: c ? c.dialogMessage() : "",
                                    rules: c ? c.model.rules : [] });
        }

        // Type into the "Add" dialog and press its button.
        function submit(label: string, port: string, protocol: string): void {
            if (!win.visible) win.open();
            win.addOpen = true;
            if (content.item) content.item.submitDialog(label, port, protocol);
        }

        // "Standardregeln wiederherstellen" (asks; answer with confirm(true/false)).
        function reset(): void {
            if (!win.visible) win.open();
            if (content.item) content.item.resetRow();
        }

        function confirm(yes: bool): void {
            if (content.item) content.item.answerConfirm(yes);
        }

        // {visible, title, warning, selected}
        function confirmState(): string {
            return JSON.stringify(content.item ? content.item.confirmState() : null);
        }

        // The row's state button / its ×, by list index.
        function toggleRow(index: int): void {
            if (content.item) content.item.toggleRow(index);
        }

        function editRow(index: int, label: string, port: string, protocol: string): void {
            if (content.item) content.item.editRow(index, label, port, protocol);
        }

        function removeRow(index: int): void {
            if (content.item) content.item.removeRow(index);
        }
    }
}
