// Appearance - the floating window (opened from the OS menu). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
// See docs/feature-architecture.md "Appearance".
//
// Frame only: overlay surface on the focused output below the bar strip,
// click outside / Escape closes. Its content (AppearanceContent.qml) and
// with it every model process exists only while the window is open;
// closed, the window is unmapped - no surface, no process, no timer.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar

PanelWindow {
    id: win

    required property int fontSize
    property bool pickerOpen: false

    function open() {
        pickerOpen = false;
        visible = true;
    }

    function close() {
        pickerOpen = false;
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
    WlrLayershell.namespace: "quickshell-appearance"
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
        onClicked: win.pickerOpen ? win.pickerOpen = false : win.close()
    }

    Loader {
        id: content
        anchors.fill: parent
        active: win.visible
        sourceComponent: AppearanceContent {
            window: win
            fontSize: win.fontSize
        }
    }

    IpcHandler {
        target: "appearance"

        function toggle(): void {
            if (win.visible) win.close();
            else win.open();
        }

        function close(): void {
            win.close();
        }

        // For tests/diagnostics.
        function state(): string {
            return JSON.stringify({ visible: win.visible, picker: win.pickerOpen });
        }
    }
}
