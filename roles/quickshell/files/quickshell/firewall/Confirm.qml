// Firewall -> a yes/no question over the window (reset to the factory
// rules). Managed by Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// "Cancel" is preselected: Enter on it, Escape and a click outside all
// cancel. Left/Right/Tab move between the two buttons. The question only
// asks - `accepted` is what the caller then runs.

import QtQuick
import QtQuick.Layouts
import qs
import qs.ui

FocusScope {
    id: dialog

    required property int fontSize
    property string title: ""
    property string text: ""
    property string warning: ""             // shown in the error color
    property string confirmLabel: "OK"
    property bool danger: false
    property int selected: 0                // 0 = Cancel, 1 = confirm
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

    DialogFrame {
        title: dialog.title

        DialogText {
            kind: "detail"
            text: dialog.text
        }

        DialogText {
            visible: dialog.warning !== ""
            kind: "error"
            text: dialog.warning
        }

        DialogButtons {
            buttons: [{ id: "cancel", label: "Cancel" }, { id: "confirm", label: dialog.confirmLabel, danger: dialog.danger }]
            selected: dialog.selected
            onPressed: id => dialog.answer(id === "confirm")
        }
    }
}
