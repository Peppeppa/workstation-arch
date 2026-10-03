// Bar widget "workspaces": Hyprland workspaces of this bar's monitor.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.
//
// Same data as before: Hyprland.workspaces (existing workspaces, live over
// Hyprland's IPC socket) filtered to this monitor; click focuses. Focused
// one: accent + underline.

import QtQuick
import Quickshell.Hyprland
import qs
import qs.bar

Item {
    id: root

    required property var bar

    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.monitor && bar.screen && w.monitor.name === bar.screen.name)

    implicitWidth: row.implicitWidth
    implicitHeight: bar.barHeight
    visible: workspaces.length > 0

    Row {
        id: row
        height: parent.height

        Repeater {
            model: root.workspaces

            BarWidget {
                id: ws
                required property var modelData
                readonly property bool focused: modelData.focused

                bar: root.bar
                text: modelData.name.length > 0 ? modelData.name : String(modelData.id)
                fixedWidth: text.length <= 2 ? 24 : -1
                active: focused
                onClicked: button => { if (button === Qt.LeftButton) ws.modelData.activate(); }

                Rectangle {
                    visible: ws.focused
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 12
                    height: BarStyle.underlineHeight
                    radius: height / 2
                    color: Colors.accent
                }
            }
        }
    }
}
