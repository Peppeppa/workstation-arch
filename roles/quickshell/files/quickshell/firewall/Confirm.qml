// Firewall -> a yes/no question over the window (reset to the factory
// rules; disabling or removing the SSH rule). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// "Abbrechen" is preselected: Enter on it, Escape and a click outside all
// cancel. Left/Right/Tab move between the two buttons. The question only
// asks - `accepted` is what the caller then runs.

import QtQuick
import QtQuick.Layouts
import qs
import qs.bar

FocusScope {
    id: dialog

    required property int fontSize
    property string title: ""
    property string text: ""
    property string warning: ""             // shown in the error color
    property string confirmLabel: "OK"
    property bool danger: false
    property int selected: 0                // 0 = Abbrechen, 1 = confirm
    signal accepted
    signal cancelled

    function ask(t, body, warn, label, isDanger) {
        title = t;
        text = body;
        warning = warn;
        confirmLabel = label;
        danger = isDanger;
        selected = 0;
        visible = true;
        forceActiveFocus();
    }

    function answer(yes) {
        visible = false;
        if (yes) accepted();
        else cancelled();
    }

    function handleKey(key) {
        switch (key) {
        case Qt.Key_Left: case Qt.Key_Right: case Qt.Key_Tab: case Qt.Key_Backtab:
            selected = 1 - selected;
            return true;
        case Qt.Key_Return: case Qt.Key_Enter:
            answer(selected === 1);
            return true;
        case Qt.Key_Escape:
            answer(false);
            return true;
        }
        return false;
    }

    visible: false
    Keys.onPressed: event => event.accepted = dialog.handleKey(event.key)

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.answer(false)
    }

    Rectangle {
        anchors.centerIn: parent
        width: Fonts.px(460)
        height: box.implicitHeight + 32
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: box
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 8

            Text {
                text: dialog.title
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: dialog.fontSize + 1
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: dialog.text
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: dialog.fontSize - 1
            }

            Text {
                visible: dialog.warning !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: dialog.warning
                color: Colors.error
                font.family: Fonts.family
                font.pixelSize: dialog.fontSize - 1
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Item { Layout.fillWidth: true }

                PopupButton {
                    label: "Abbrechen"
                    primary: dialog.selected === 0
                    fontSize: dialog.fontSize - 1
                    onClicked: dialog.answer(false)
                }
                PopupButton {
                    label: dialog.confirmLabel
                    primary: dialog.selected === 1
                    danger: dialog.danger && dialog.selected !== 1
                    fontSize: dialog.fontSize - 1
                    onClicked: dialog.answer(true)
                }
            }
        }
    }
}
