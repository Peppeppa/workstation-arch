// The small text button used inside bar popups (one look for all of them).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.

import QtQuick
import qs

Rectangle {
    id: btn

    property string label
    property bool danger: false
    property bool primary: false
    property int fontSize: BarStyle.popupFontSize - 1
    signal clicked

    implicitWidth: btnText.implicitWidth + 16
    implicitHeight: 24
    radius: 4
    color: btnMouse.containsMouse || primary ? Colors.accent : Colors.surface
    border.color: Colors.border
    border.width: primary || btnMouse.containsMouse ? 0 : 1

    Text {
        id: btnText
        anchors.centerIn: parent
        text: btn.label
        color: btnMouse.containsMouse || btn.primary ? Colors.accentForeground
             : btn.danger ? Colors.error : Colors.foreground
        font.family: Fonts.family
        font.pixelSize: btn.fontSize
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
