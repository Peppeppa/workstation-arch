// Firewall - the window's content. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// The user's LAN sharing rules only ("Bezeichnung / Port / Protokoll"):
// each row's button shows what is LIVE in the kernel - enabled: red
// "Deaktivieren", disabled: green "Aktivieren" - and × deletes the rule
// (the helper closes the port first). The base policy (loopback, ICMP,
// DHCP, LocalSend, SSH) is infrastructure and not listed here. A rule
// opens a port in the firewall; it does not start or stop the service
// behind it. All work is the root helper's (services/FirewallModel).

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
        if (root.window.addOpen) root.window.addOpen = false;
        else root.window.close();
    }

    FirewallModel {
        id: fw
    }

    // For the IPC hooks (FirewallWindow): the same paths as the controls.
    function dialogMessage() {
        return dialog.message;
    }

    function submitDialog(label, port, protocol) {
        dialog.fill(label, port, protocol);
        dialog.submit();
    }

    function toggleRow(index) {
        const r = fw.rules[index];
        if (r && !fw.busy) fw.setEnabled(r, !r.active);
    }

    function removeRow(index) {
        const r = fw.rules[index];
        if (r && !fw.busy) fw.remove(r);
    }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(40, Math.round((root.height - 420) / 2))
        width: Fonts.px(480)
        height: Math.min(column.implicitHeight + 32, root.height - y - 40)
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
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
                        label: "Hinzufügen"
                        fontSize: root.fontSize - 2
                        onClicked: root.window.addOpen = true
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
                        spacing: 2

                        Text {
                            visible: fw.listed && fw.rules.length === 0
                            Layout.fillWidth: true
                            Layout.margins: 4
                            text: "Keine Regeln - nichts ist im LAN freigegeben."
                            color: Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize - 1
                        }

                        Text {
                            visible: !fw.listed
                            Layout.margins: 4
                            text: "…"
                            color: Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: root.fontSize - 1
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
                                radius: 4
                                color: rowMouse.containsMouse ? Colors.surface : "transparent"

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 4
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
                                            font.pixelSize: root.fontSize - 1
                                        }
                                        Text {
                                            visible: row.drift
                                            text: "Nicht wie gespeichert aktiv - bitte neu schalten."
                                            color: Colors.error
                                            font.family: Fonts.family
                                            font.pixelSize: root.fontSize - 3
                                        }
                                    }

                                    PopupButton {
                                        label: row.modelData.active ? "Deaktivieren" : "Aktivieren"
                                        danger: row.modelData.active
                                        positive: !row.modelData.active
                                        opacity: fw.busy ? 0.6 : 1
                                        fontSize: root.fontSize - 2
                                        onClicked: root.toggleRow(row.index)
                                    }

                                    PopupButton {
                                        label: "×"
                                        opacity: fw.busy ? 0.6 : 1
                                        fontSize: root.fontSize - 1
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
                    text: "Die Firewall ist nicht geladen (workstation-firewall.service)."
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: root.fontSize - 2
                }

                Text {
                    visible: fw.errorText !== "" && !root.window.addOpen
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: fw.errorText
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: root.fontSize - 2
                }
            }
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
        onVisibleChanged: if (!visible) root.forceActiveFocus()
    }
}
