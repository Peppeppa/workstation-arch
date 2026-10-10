// The small text button of bar popups and dialogs (one look for all of them).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.

import QtQuick
import qs

Rectangle {
    id: btn

    property string label
    property bool danger: false             // destructive: text in Colors.error
    property bool positive: false           // enabling: text in Colors.success
    property bool primary: false
    property bool muted: false              // not usable right now: muted text, no hover plate (still clickable,
                                            // so the owner can say why)
    property int fontSize: Style.secondary
    signal clicked

    implicitWidth: btnText.implicitWidth + 2 * Style.spacingMd
    implicitHeight: Style.grow(24)           // below compactRowHeight: buttons sit inside rows
    radius: Style.controlRadius
    color: (btnMouse.containsMouse && !muted) || primary ? Colors.accent : Colors.surface
    border.color: Colors.border
    border.width: primary || (btnMouse.containsMouse && !muted) ? 0 : 1

    Text {
        id: btnText
        anchors.centerIn: parent
        text: btn.label
        color: (btnMouse.containsMouse && !btn.muted) || btn.primary ? Colors.accentForeground
             : btn.muted ? Colors.foregroundMuted : btn.danger ? Colors.error : btn.positive ? Colors.success : Colors.foreground
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
