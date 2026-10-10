// The action row of a DialogFrame (RICE v1 phase 3): right-aligned buttons,
// the keyboard selection drawn as the primary one. Managed by Ansible: do
// not edit by hand, see roles/quickshell in workstation-arch.
//
// buttons: [{ id, label, danger? }]; the owner keeps `selected`, the keys and
// what a press does (pressed(id)) - pointer hover never moves the selection.

import QtQuick
import QtQuick.Layouts
import qs
import qs.bar

RowLayout {
    id: row

    property var buttons: []
    property int selected: 0
    signal pressed(string id)

    Layout.fillWidth: true
    Layout.topMargin: Style.spacingSm
    spacing: Style.spacingMd

    Item { Layout.fillWidth: true }

    Repeater {
        model: row.buttons

        PopupButton {
            required property var modelData
            required property int index
            label: modelData.label
            primary: index === row.selected
            danger: modelData.danger === true
            onClicked: row.pressed(modelData.id)
        }
    }
}
