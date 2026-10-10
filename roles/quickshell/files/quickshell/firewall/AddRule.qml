// Firewall -> Add / Edit (over the Firewall window). Managed by Ansible: do
// not edit by hand, see roles/quickshell in workstation-arch.
//
// Exactly three inputs: Label (free text, only for the user),
// Port (1-65535), Protocol (TCP or UDP, any case - shown and stored
// upper-case). Nothing else - no ranges, sources, interfaces or nft syntax.
// Checked here for feedback, decided by the root helper; the dialog closes
// only when the helper accepted the rule. A new rule is added DISABLED -
// the port opens only with the row's "Enable" (no accidental exposure
// from a typo). With `rule` set (a click on a row's text) the same dialog
// edits that rule ("Save"): label, port, protocol - for a factory rule
// with a fixed restriction (DHCP, DHCPv6, LocalSend discovery: `fixed`)
// only the label. Escape / a click outside / Cancel closes.

import QtQuick
import QtQuick.Layouts
import qs
import qs.ui
import qs.bar

Item {
    id: dialog

    required property var model
    required property int fontSize
    property var rule: null             // null = add a new rule, else edit this one
    readonly property bool fixed: rule !== null && rule.fixed === true
    signal done

    property bool tried: false          // show input errors only after a first submit
    property bool waiting: false        // our add is running in the helper
    readonly property string inputError: model.labelError(labelField.text)
        || model.portError(portField.text)
        || (model.normalizeProtocol(protoField.text) === "" ? "Protocol: TCP or UDP." : "")
    readonly property string message: waiting ? "" : tried && inputError !== "" ? inputError : model.errorText

    function reset() {
        labelField.text = rule ? rule.label : "";
        portField.text = rule ? String(rule.port) : "";
        protoField.text = rule ? rule.protocol : "";
        tried = false;
        waiting = false;
        model.errorText = "";
        labelField.input.forceActiveFocus();
    }

    function fill(label, port, protocol) {
        labelField.text = label;
        portField.text = port;
        protoField.text = protocol;
    }

    function submit() {
        tried = true;
        if (inputError !== "" || model.busy) return;
        const proto = model.normalizeProtocol(protoField.text);
        waiting = rule ? model.edit(rule, labelField.text, portField.text, proto)
                       : model.add(labelField.text, portField.text, proto);
    }

    Connections {
        target: dialog.model
        function onActionDone(ok) {
            if (!dialog.waiting) return;
            dialog.waiting = false;
            if (ok) dialog.done();
        }
    }

    // Hidden, the fields must not keep the keyboard: the window's FocusScope
    // would hand focus back to them and swallow the next Escape.
    onVisibleChanged: {
        if (visible) reset();
        else {
            labelField.input.focus = false;
            portField.input.focus = false;
            protoField.input.focus = false;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.done()
    }

    component Caption: Text {
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: Style.secondary
    }

    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string placeholder
        property Item tabTarget: null
        property Item backtabTarget: null
        property bool locked: false
        Layout.fillWidth: true
        implicitHeight: Fonts.px(30)
        radius: Style.controlRadius
        color: Colors.surface
        border.color: input.activeFocus ? Colors.borderActive : Colors.border
        border.width: 1

        TextInput {
            id: input
            readOnly: field.locked
            anchors.fill: parent
            anchors.leftMargin: Style.spacingMd
            anchors.rightMargin: Style.spacingMd
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: field.locked ? Colors.foregroundMuted : Colors.foreground
            selectionColor: Colors.accent
            selectedTextColor: Colors.accentForeground
            font.family: Fonts.family
            font.pixelSize: Style.secondary
            Keys.onReturnPressed: dialog.submit()
            Keys.onEnterPressed: dialog.submit()
            Keys.onEscapePressed: dialog.done()
            KeyNavigation.tab: field.tabTarget
            KeyNavigation.backtab: field.backtabTarget

            Text {
                visible: input.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Colors.foregroundMuted
                font: input.font
            }
        }
    }

    DialogFrame {
        panelWidth: Style.standardPanelWidth
        title: dialog.rule ? "Edit rule" : "Add rule"

        Caption { text: "Label" }
        Field {
            id: labelField
            placeholder: "e.g. Test Database"
            tabTarget: portField.input
        }

        Caption { text: "Port" }
        Field {
            id: portField
            locked: dialog.fixed
            placeholder: "1 to 65535, e.g. 1234"
            tabTarget: protoField.input
            backtabTarget: labelField.input
        }

        Caption { text: "Protocol" }
        Field {
            id: protoField
            locked: dialog.fixed
            placeholder: "TCP or UDP"
            backtabTarget: portField.input
        }

        Caption {
            visible: dialog.fixed
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Standard rule with a fixed restriction - port and protocol are fixed, only the label can be changed."
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingXs
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: dialog.message
                color: Colors.error
                font.family: Fonts.family
                font.pixelSize: Style.caption
            }
            PopupButton {
                label: "Cancel"
                fontSize: Style.secondary
                onClicked: dialog.done()
            }
            PopupButton {
                primary: dialog.inputError === "" && !dialog.model.busy
                muted: !primary
                label: dialog.waiting ? "…" : dialog.rule ? "Save" : "Add"
                fontSize: Style.secondary
                onClicked: dialog.submit()
            }
        }
    }
}
