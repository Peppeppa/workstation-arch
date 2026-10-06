// Bar widget "visuals" - the timer popup. Managed by Ansible: do not edit
// by hand, see roles/quickshell in workstation-arch.
//
// Idle: one duration field + Start; Enter and Start run the same
// startFromInput(). Digits are read from the right (230 = 02:30, 9000 =
// 90:00), colons work too (2:30, 3:30:00) - Countdown.parse(). The hint
// line below shows what the typed text means; the field itself is never
// reformatted while typing (no cursor jumps). Running: the remaining time + Stop. The countdown itself is
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
            error = "Enter e.g. 5 (seconds), 230 (2:30), 2500 (25:00) or 1:30:00";
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
                    maximumLength: 8
                    inputMethodHints: Qt.ImhDigitsOnly
                    // Deferred: BarPopup's own onCompleted runs after this
                    // one and gives the keyboard to its key handler (the
                    // field then never got the typing - measured).
                    Component.onCompleted: Qt.callLater(() => { forceActiveFocus(); selectAll(); })
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
            text: {
                if (popup.error !== "") return popup.error;
                const s = Countdown.parse(input.text);
                return s > 0 ? "= " + Countdown.format(s) : "MMSS or H:MM:SS";
            }
            color: popup.error !== "" ? Colors.error : Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 2
        }
    }
}
