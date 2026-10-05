// Bar widget "visuals" - the timer popup. Managed by Ansible: do not edit
// by hand, see roles/quickshell in workstation-arch.
//
// Idle: one MM:SS field (minutes may exceed 59: 90:00) + Start; Enter
// starts too. Running: the remaining time + Stop. The countdown itself is
// Countdown.qml (absolute deadline) - closing this popup does not stop it.
// A BarPopup: exists only while open.

import QtQuick
import QtQuick.Layouts
import qs
import qs.bar

BarPopup {
    id: popup

    property string error: ""

    panelWidth: Fonts.px(240)

    function startFromInput() {
        const s = Countdown.parse(input.text);
        if (s < 0) {
            error = "Enter minutes:seconds, e.g. 05:00, 25:00, 90:00 or 00:30";
            return;
        }
        error = "";
        Countdown.start(s);
        popup.closeRequested();
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Text {
            text: "Timer"
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize + 1
            font.bold: true
        }

        // ---- running ----
        Text {
            visible: Countdown.active
            Layout.alignment: Qt.AlignHCenter
            text: Countdown.format(Countdown.remaining)
            color: Colors.accent
            font.family: Fonts.family
            font.pixelSize: popup.fontSize + 12
            font.bold: true
        }

        PopupButton {
            visible: Countdown.active
            Layout.alignment: Qt.AlignRight
            danger: true
            label: "Stop"
            onClicked: Countdown.stop()
        }

        // ---- idle ----
        RowLayout {
            visible: !Countdown.active
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Fonts.px(28)
                radius: 4
                color: Colors.surface
                border.color: popup.error !== "" ? Colors.error : Colors.border
                border.width: 1

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.margins: 6
                    text: "25:00"
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize
                    maximumLength: 6
                    inputMethodHints: Qt.ImhDigitsOnly
                    Component.onCompleted: { forceActiveFocus(); selectAll(); }
                    onTextEdited: popup.error = ""
                    Keys.onReturnPressed: popup.startFromInput()
                    Keys.onEnterPressed: popup.startFromInput()
                    Keys.onEscapePressed: popup.closeRequested()
                }
            }

            PopupButton {
                primary: true
                label: "Start"
                onClicked: popup.startFromInput()
            }
        }

        Text {
            visible: !Countdown.active
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: popup.error !== "" ? popup.error : "MM:SS"
            color: popup.error !== "" ? Colors.error : Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 2
        }
    }
}
