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
    property bool addOpen: false            // "Hinzufügen" dialog (AddRule.qml)

    function open() {
        addOpen = false;
        visible = true;
    }

    function close() {
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
        active: win.visible
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

        // {visible, add, busy, error, dialogError, rules: [...]}
        function state(): string {
            const c = content.item;
            return JSON.stringify({ visible: win.visible, add: win.addOpen,
                                    busy: c ? c.model.busy : false,
                                    error: c ? c.model.errorText : "",
                                    dialogError: c ? c.dialogMessage() : "",
                                    rules: c ? c.model.rules : [] });
        }

        // Type into the "Hinzufügen" dialog and press its button.
        function submit(label: string, port: string, protocol: string): void {
            if (!win.visible) win.open();
            win.addOpen = true;
            if (content.item) content.item.submitDialog(label, port, protocol);
        }

        // The row's state button / its ×, by list index.
        function toggleRow(index: int): void {
            if (content.item) content.item.toggleRow(index);
        }

        function removeRow(index: int): void {
            if (content.item) content.item.removeRow(index);
        }
    }
}
