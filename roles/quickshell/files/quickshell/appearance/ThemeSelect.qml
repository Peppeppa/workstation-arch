// Appearance - one theme selector (dark or light): current choice +
// chevron, expands into the themes with that marker. Managed by Ansible:
// do not edit by hand, see roles/quickshell in workstation-arch. The list
// is the model's (`theme status`), picking runs the model's `theme select`
// - applied at once when that mode is active.

import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    id: sel

    required property var model
    required property string slot
    required property int fontSize
    property bool expanded: false

    spacing: 2

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Fonts.px(32)
        radius: 4
        color: Colors.surface
        border.color: sel.expanded || headMouse.containsMouse ? Colors.borderActive : Colors.border
        border.width: 1

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: chevron.left
            anchors.verticalCenter: parent.verticalCenter
            text: sel.model.status ? sel.model.nameOf(sel.slot, sel.model.selectedId(sel.slot)) : "…"
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: sel.fontSize
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: sel.expanded ? "\u{F0143}" : "\u{F0140}"
            color: Colors.foregroundMuted
            font.family: Fonts.icons
            font.pixelSize: sel.fontSize
        }

        MouseArea {
            id: headMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sel.expanded = !sel.expanded
        }
    }

    Repeater {
        model: sel.expanded ? sel.model.options(sel.slot) : []

        Rectangle {
            id: option
            required property var modelData
            readonly property bool current: modelData.id === sel.model.selectedId(sel.slot)
            Layout.fillWidth: true
            implicitHeight: Fonts.px(30)
            radius: 4
            color: optMouse.containsMouse ? Colors.accent : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: option.modelData.name
                textFormat: Text.PlainText
                color: optMouse.containsMouse ? Colors.accentForeground : Colors.foreground
                font.family: Fonts.family
                font.pixelSize: sel.fontSize
            }

            Text {
                visible: option.current
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F012C}"           // check
                color: optMouse.containsMouse ? Colors.accentForeground : Colors.accent
                font.family: Fonts.icons
                font.pixelSize: sel.fontSize
            }

            MouseArea {
                id: optMouse
                anchors.fill: parent
                hoverEnabled: true
                // Select first: collapsing destroys this row (and its scope).
                onClicked: {
                    sel.model.select(sel.slot, option.modelData.id);
                    sel.expanded = false;
                }
            }
        }
    }
}
