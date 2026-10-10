// Firewall - the window's content. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// ALL port rules of this firewall ("Bezeichnung / Port / Protokoll"): the
// factory rules (DHCP, DHCPv6, LocalSend discovery + transfer, SSH) and the
// user's own, one list, all handled the same: each row's button shows what
// is LIVE in the kernel - enabled: red "Deaktivieren", disabled: green
// "Aktivieren"; × deletes the rule; a click on the row's text edits it
// (AddRule.qml). "Restore standard rules" (bottom) brings back the
// five factory rules and removes the user's - after a question (Confirm.qml,
// Abbrechen preselected). The SSH rule is a rule like any other: switch and
// × act at once, no question of its own. Infrastructure that is not a port rule (loopback,
// replies, ICMP, Docker bridges) is not listed. A rule opens a port in the
// firewall; it does not start or stop the service behind it. All work is
// the root helper's (services/FirewallModel).

import QtQuick
import QtQuick.Layouts
import qs
import qs.bar
import qs.services

FocusScope {
    id: root

    required property var window
    required property int fontSize
    readonly property alias model: fw

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: {
        if (confirm.visible) confirm.answer(false);
        else if (root.window.addOpen) root.window.addOpen = false;
        else root.window.close();
    }

    // Where the keyboard goes back to after the confirm / add dialog closes:
    // root.forceActiveFocus() handed it to the scope's remembered focus child
    // - the dialog that had just been hidden - so Escape reached nothing and
    // the window no longer closed (laptop GUI test 2026-10-10). Keys pressed
    // here propagate to root's Keys.onEscapePressed.
    Item {
        id: keySink
    }

    // The question before a reset; `pending` runs on Ja.
    property var pending: null

    function askThen(title, body, warning, label, action) {
        pending = action;
        confirm.ask(title, body, warning, label, true);
    }

    function openEdit(rule) {
        dialog.rule = rule;
        root.window.addOpen = true;
    }

    function openAdd() {
        dialog.rule = null;
        root.window.addOpen = true;
    }

    function askReset() {
        askThen("Restore the standard rules?",
                "The firewall rules are reset to the five standard rules: DHCP (UDP 68), DHCPv6 (UDP 546), LocalSend discovery (UDP 53317), LocalSend file transfer (TCP 53317) and SSH (TCP 22), all enabled. Your own rules are removed; deleted or disabled standard rules come back enabled.",
                "", "Restore", () => fw.reset());
    }

    FirewallModel {
        id: fw
    }

    // For the IPC hooks (FirewallWindow): the same paths as the controls.
    function dialogMessage() {
        return dialog.message;
    }

    function submitDialog(label, port, protocol) {
        if (dialog.rule !== null) {
            dialog.rule = null;
            dialog.reset();
        }
        dialog.fill(label, port, protocol);
        dialog.submit();
    }

    // Edit row `index` through the dialog (same path as a click on the row).
    function editRow(index, label, port, protocol) {
        const r = fw.rules[index];
        if (!r) return;
        openEdit(r);
        dialog.fill(label, port, protocol);
        dialog.submit();
    }

    function toggleRow(index) {
        const r = fw.rules[index];
        if (!r || fw.busy) return;
        fw.setEnabled(r, !r.active);
    }

    function removeRow(index) {
        const r = fw.rules[index];
        if (!r || fw.busy) return;
        fw.remove(r);
    }

    // For the IPC hooks: the reset question / its answer, the edit dialog.
    function resetRow() {
        askReset();
    }

    function answerConfirm(yes) {
        if (confirm.visible) confirm.answer(yes);
    }

    function confirmState() {
        return { visible: confirm.visible, title: confirm.title, warning: confirm.warning,
                 selected: confirm.selected === 0 ? "Cancel" : confirm.confirmLabel };
    }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(40, Math.round((root.height - 420) / 2))
        width: Style.widePanelWidth             // room for the longest factory row label / port / protocol
        height: Math.min(column.implicitHeight + 32, root.height - y - 40)
        radius: Style.panelRadius
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: Style.spacingXl
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Firewall"
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: root.fontSize + 3
                        font.bold: true
                    }
                    PopupButton {
                        label: "Add"
                        fontSize: Style.caption
                        onClicked: root.openAdd()
                    }
                }

                // The rules box.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    implicitHeight: rows.implicitHeight + 12
                    radius: 6
                    color: "transparent"
                    border.color: Colors.border
                    border.width: 1

                    ColumnLayout {
                        id: rows
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: Style.spacingXs

                        Text {
                            visible: fw.listed && fw.rules.length === 0
                            Layout.fillWidth: true
                            Layout.margins: Style.spacingSm
                            text: "No rules - no port is reachable from outside."
                            color: Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: Style.secondary
                        }

                        Text {
                            visible: !fw.listed
                            Layout.margins: Style.spacingSm
                            text: "…"
                            color: Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: Style.secondary
                        }

                        Repeater {
                            model: fw.rules

                            Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                // desired and live disagree (e.g. the table was
                                // reloaded without a restore): said, not hidden
                                readonly property bool drift: modelData.enabled !== modelData.active
                                Layout.fillWidth: true
                                implicitHeight: Fonts.px(34)
                                radius: Style.controlRadius
                                color: rowMouse.containsMouse ? Colors.surface : "transparent"

                                // A click on the row (not its buttons) edits the rule.
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!fw.busy) root.openEdit(row.modelData)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.spacingMd
                                    anchors.rightMargin: Style.spacingSm
                                    spacing: 6

                                    Column {
                                        Layout.fillWidth: true
                                        Text {
                                            width: parent.width
                                            text: row.modelData.label + " / " + row.modelData.port + " / " + row.modelData.protocol
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            color: row.modelData.active ? Colors.foreground : Colors.foregroundMuted
                                            font.family: Fonts.family
                                            font.pixelSize: Style.secondary
                                        }
                                        Text {
                                            visible: row.drift
                                            text: "Not active as saved - switch it again."
                                            color: Colors.error
                                            font.family: Fonts.family
                                            font.pixelSize: root.fontSize - 3
                                        }
                                    }

                                    PopupButton {
                                        label: row.modelData.active ? "Disable" : "Enable"
                                        danger: row.modelData.active
                                        positive: !row.modelData.active
                                        muted: fw.busy
                                        fontSize: Style.caption
                                        onClicked: root.toggleRow(row.index)
                                    }

                                    PopupButton {
                                        label: "×"
                                        muted: fw.busy
                                        fontSize: Style.secondary
                                        onClicked: root.removeRow(row.index)
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: fw.listed && !fw.loaded
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "The firewall is not loaded (workstation-firewall.service)."
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: Style.caption
                }

                Text {
                    visible: fw.errorText !== "" && !root.window.addOpen
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: fw.errorText
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: Style.caption
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Item { Layout.fillWidth: true }
                    PopupButton {
                        label: "Restore standard rules"
                        muted: fw.busy
                        fontSize: Style.caption
                        onClicked: if (!fw.busy) root.askReset()
                    }
                }
            }
        }
    }

    Confirm {
        id: confirm
        anchors.fill: parent
        fontSize: root.fontSize
        onAccepted: {
            const action = root.pending;
            root.pending = null;
            if (action) action();
            keySink.forceActiveFocus();
        }
        onCancelled: {
            root.pending = null;
            keySink.forceActiveFocus();
        }
    }

    AddRule {
        id: dialog
        anchors.fill: parent
        visible: root.window.addOpen
        model: fw
        fontSize: root.fontSize
        onDone: root.window.addOpen = false
        // keyboard back to the window (AddRule drops its fields' focus), so
        // the next Escape closes the window
        onVisibleChanged: if (!visible) keySink.forceActiveFocus()
    }
}
