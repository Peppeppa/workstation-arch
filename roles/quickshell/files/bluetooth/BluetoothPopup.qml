// FEATURE: bluetooth - the popup opened from the bar's Bluetooth icon
// (BluetoothButton.qml). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch.
//
// Same overlay pattern as the power menu / tray menu: while open the
// transparent surface covers the output, a click outside or Escape
// closes it; it is created by a Loader only while open, so a closed popup
// leaves no surface and no keyboard focus behind.
//
// Everything goes through Quickshell's native Bluetooth module (BlueZ
// D-Bus): adapter.enabled (Powered) for on/off, adapter.discovering for
// scanning, device.connect/disconnect/pair/cancelPair/forget. Only two
// on-demand processes, both fixed argv, no shell:
//   - `rfkill --json` once when the adapter reports Blocked (soft vs.
//     hard), `rfkill unblock bluetooth` for a soft block;
//   - the pairing agent (bluetooth-agent), only while the user pairs.
// Scanning is started only by the user, auto-stops after scanTimeoutMs,
// and is stopped when the popup closes if we started it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: popup

    required property var adapter
    required property real anchorX
    required property int barHeight
    required property int fontSize

    readonly property string agentCommand: Quickshell.env("HOME") + "/.local/libexec/workstation/bluetooth-agent"
    readonly property int scanTimeoutMs: 30000

    readonly property bool blocked: adapter.state === BluetoothAdapterState.Blocked
    readonly property var allDevices: adapter.devices.values.slice().sort((a, b) => (a.name || a.address).localeCompare(b.name || b.address))
    readonly property var connectedDevices: allDevices.filter(d => d.connected)
    readonly property var pairedDevices: allDevices.filter(d => d.paired && !d.connected)
    // Unpaired devices without a name are mostly anonymous BLE beacons - noise.
    readonly property var availableDevices: allDevices.filter(d => !d.paired && d.deviceName !== "")

    property bool scanStartedHere: false
    property string rfkillState: ""          // "", "soft" or "hard" (only read while blocked)
    property var pairingDevice: null
    property bool pairingSeen: false
    property var agentRequest: null           // pending agent event the user must answer
    property string message: ""

    signal closeRequested

    function stopScan() {
        if (scanStartedHere && adapter.discovering) adapter.discovering = false;
        scanStartedHere = false;
        scanTimer.stop();
    }

    function toggleScan() {
        if (adapter.discovering) {
            stopScan();
        } else {
            adapter.discovering = true;
            scanStartedHere = true;
            scanTimer.restart();
        }
    }

    function startPair(device) {
        if (pairingDevice !== null) return;
        message = "";
        pairingDevice = device;
        pairingSeen = false;
        agent.running = true;               // pair() follows the agent's "ready"
    }

    function finishPairing(text) {
        if (agent.running) agent.write(JSON.stringify({ quit: true }) + "\n");
        pairingDevice = null;
        agentRequest = null;
        message = text;
    }

    function answer(accept, value) {
        agent.write(JSON.stringify({ accept: accept, value: value || "" }) + "\n");
        agentRequest = null;
    }

    function onAgentEvent(ev) {
        if (ev.event === "ready") {
            if (pairingDevice) pairingDevice.pair();
        } else if (ev.event === "cancel") {
            agentRequest = null;
        } else {
            agentRequest = ev;
        }
    }

    function deviceLabel(d) {
        return d.name || d.address;
    }

    function batteryText(d) {
        if (!d.batteryAvailable) return "";
        return Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) + "%";
    }

    Component.onCompleted: {
        keyHandler.forceActiveFocus();
        if (blocked) rfkillProc.running = true;
    }
    Component.onDestruction: {
        stopScan();
        if (pairingDevice !== null) pairingDevice.cancelPair();
        if (agent.running) agent.write(JSON.stringify({ quit: true }) + "\n");
    }

    Timer {
        id: scanTimer
        interval: popup.scanTimeoutMs
        onTriggered: popup.stopScan()
    }

    Process {
        id: rfkillProc
        command: ["rfkill", "--json", "--output", "TYPE,SOFT,HARD"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const bt = JSON.parse(text).rfkilldevices.filter(r => r.type === "bluetooth");
                    popup.rfkillState = bt.some(r => r.hard === "blocked") ? "hard"
                                      : bt.some(r => r.soft === "blocked") ? "soft" : "";
                } catch (e) {
                    popup.rfkillState = "";
                }
            }
        }
    }

    Process {
        id: unblockProc
        command: ["rfkill", "unblock", "bluetooth"]
        onExited: exitCode => {
            if (exitCode !== 0) popup.message = "Could not unblock Bluetooth";
            popup.rfkillState = "";
        }
    }

    Process {
        id: agent
        command: [popup.agentCommand]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    popup.onAgentEvent(JSON.parse(line));
                } catch (e) {}
            }
        }
        onExited: exitCode => {
            if (popup.pairingDevice !== null && !popup.pairingDevice.paired)
                popup.finishPairing(exitCode === 0 ? "Pairing ended" : "Pairing agent unavailable");
        }
    }

    // Pairing outcome, from the device's own properties (event-driven).
    Connections {
        target: popup.pairingDevice
        function onPairingChanged() {
            if (popup.pairingDevice.pairing) {
                popup.pairingSeen = true;
            } else if (popup.pairingSeen && !popup.pairingDevice.paired) {
                popup.finishPairing("Pairing failed");
            }
        }
        function onPairedChanged() {
            if (!popup.pairingDevice.paired) return;
            const d = popup.pairingDevice;
            d.trusted = true;          // reconnect without asking again (user-initiated pairing)
            popup.finishPairing("");
            d.connect();
        }
    }

    visible: true
    focusable: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-bluetooth"

    MouseArea {
        anchors.fill: parent
        onClicked: popup.closeRequested()
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (popup.agentRequest !== null) popup.answer(false);
            else popup.closeRequested();
        }
    }

    // Small text button used throughout.
    component ActionButton: Rectangle {
        id: btn
        property string label
        property bool danger: false
        property bool primary: false
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
            font.pixelSize: popup.fontSize - 1
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }

    component SectionTitle: Text {
        Layout.topMargin: 6
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: popup.fontSize - 2
    }

    component DeviceRow: Rectangle {
        id: row
        required property var device
        property bool confirmForget: false

        Layout.fillWidth: true
        implicitHeight: 34
        radius: 4
        color: rowMouse.containsMouse ? Colors.surface : "transparent"

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onExited: row.confirmForget = false
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 8

            Image {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                sourceSize.width: 18
                sourceSize.height: 18
                visible: source != ""
                source: row.device.icon ? Quickshell.iconPath(row.device.icon, true) : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: popup.deviceLabel(row.device)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize
                }

                Text {
                    readonly property string stateText:
                        row.device.state === BluetoothDeviceState.Connecting ? "Connecting…"
                        : row.device.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                        : row.device.pairing ? "Pairing…" : ""
                    visible: text !== ""
                    text: [stateText, popup.batteryText(row.device)].filter(s => s !== "").join("  ·  ")
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize - 3
                }
            }

            // Forget: explicit, needs a second click (paired devices only).
            ActionButton {
                visible: row.device.paired
                label: row.confirmForget ? "Forget?" : ""
                danger: true
                onClicked: {
                    if (row.confirmForget) row.device.forget();
                    else row.confirmForget = true;
                }
            }

            ActionButton {
                visible: popup.pairingDevice === null || popup.pairingDevice === row.device
                label: row.device.connected ? "Disconnect"
                     : row.device.paired ? "Connect"
                     : popup.pairingDevice === row.device ? "Cancel" : "Pair"
                onClicked: {
                    const d = row.device;
                    if (d.connected) d.disconnect();
                    else if (d.paired) d.connect();
                    else if (popup.pairingDevice === d) { d.cancelPair(); popup.finishPairing(""); }
                    else popup.startPair(d);
                }
            }
        }
    }

    Rectangle {
        id: panel

        readonly property int panelWidth: 320

        x: Math.max(6, Math.min(popup.anchorX - panelWidth / 2, popup.width - panelWidth - 6))
        y: popup.barHeight + 4
        width: panelWidth
        implicitHeight: content.implicitHeight + 20
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 4

            // Header: title + on/off.
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Bluetooth"
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize + 1
                    font.bold: true
                }

                ActionButton {
                    visible: !popup.blocked
                    label: popup.adapter.enabled ? "On" : "Off"
                    primary: popup.adapter.enabled
                    onClicked: {
                        if (popup.adapter.enabled) popup.stopScan();
                        popup.adapter.enabled = !popup.adapter.enabled;
                    }
                }
            }

            // rfkill: soft block can be lifted, hard block is a switch/key.
            RowLayout {
                visible: popup.blocked
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: popup.rfkillState === "hard" ? "Blocked by a hardware switch"
                        : popup.rfkillState === "soft" ? "Blocked (rfkill)" : "Blocked"
                    wrapMode: Text.Wrap
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize - 1
                }

                ActionButton {
                    visible: popup.rfkillState === "soft"
                    label: "Unblock"
                    onClicked: unblockProc.running = true
                }
            }

            // Pairing dialog (agent requests), replaces nothing - shown on top of the lists.
            Rectangle {
                visible: popup.agentRequest !== null
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: pairBox.implicitHeight + 16
                radius: 6
                color: Colors.surface
                border.color: Colors.borderActive
                border.width: 1

                ColumnLayout {
                    id: pairBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    readonly property var req: popup.agentRequest || ({})
                    readonly property string who: popup.pairingDevice ? popup.deviceLabel(popup.pairingDevice) : "device"

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: popup.fontSize
                        text: pairBox.req.event === "confirm" ? "Does " + pairBox.who + " show this code?"
                            : pairBox.req.event === "authorize" ? "Pair with " + pairBox.who + "?"
                            : pairBox.req.event === "pin" ? "Enter the PIN for " + pairBox.who
                            : pairBox.req.event === "passkey" ? "Enter the passkey shown on " + pairBox.who
                            : pairBox.req.event === "display" ? "Type this code on " + pairBox.who : ""
                    }

                    Text {
                        visible: pairBox.req.event === "confirm" || pairBox.req.event === "display"
                        text: pairBox.req.passkey || pairBox.req.code || ""
                        color: Colors.accent
                        font.family: Fonts.family
                        font.pixelSize: popup.fontSize + 8
                        font.bold: true
                    }

                    Rectangle {
                        visible: pairBox.req.event === "pin" || pairBox.req.event === "passkey"
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 4
                        color: Colors.background
                        border.color: Colors.border
                        border.width: 1

                        TextInput {
                            id: codeInput
                            anchors.fill: parent
                            anchors.margins: 6
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize
                            maximumLength: 16
                            onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                            Keys.onReturnPressed: popup.answer(true, text)
                            Keys.onEscapePressed: popup.answer(false)
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 6

                        ActionButton {
                            label: "Cancel"
                            onClicked: {
                                if (pairBox.req.event === "display") {
                                    if (popup.pairingDevice) popup.pairingDevice.cancelPair();
                                    popup.finishPairing("");
                                } else popup.answer(false);
                            }
                        }

                        ActionButton {
                            visible: pairBox.req.event !== "display"
                            primary: true
                            label: "Pair"
                            onClicked: popup.answer(true, codeInput.text)
                        }
                    }
                }
            }

            Text {
                visible: popup.message !== ""
                Layout.fillWidth: true
                text: popup.message
                wrapMode: Text.Wrap
                color: Colors.error
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 2
            }

            // Device lists (only with the adapter on).
            Flickable {
                visible: popup.adapter.enabled && !popup.blocked
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(lists.implicitHeight, 360)
                contentHeight: lists.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: lists
                    width: parent.width
                    spacing: 2

                    SectionTitle { visible: popup.connectedDevices.length > 0; text: "Connected" }
                    Repeater { model: popup.connectedDevices; DeviceRow { required property var modelData; device: modelData } }

                    SectionTitle { visible: popup.pairedDevices.length > 0; text: "Paired" }
                    Repeater { model: popup.pairedDevices; DeviceRow { required property var modelData; device: modelData } }

                    SectionTitle { visible: popup.availableDevices.length > 0; text: "Available" }
                    Repeater { model: popup.availableDevices; DeviceRow { required property var modelData; device: modelData } }

                    Text {
                        visible: popup.allDevices.length === 0
                        Layout.topMargin: 6
                        text: popup.adapter.discovering ? "Searching…" : "No devices - use Scan to find new ones"
                        color: Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: popup.fontSize - 1
                    }
                }
            }

            RowLayout {
                visible: popup.adapter.enabled && !popup.blocked
                Layout.fillWidth: true
                Layout.topMargin: 6

                Text {
                    Layout.fillWidth: true
                    visible: popup.adapter.discovering
                    text: "Scanning…"
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize - 2
                }

                Item { Layout.fillWidth: !popup.adapter.discovering }

                ActionButton {
                    label: popup.adapter.discovering ? "Stop" : "Scan"
                    onClicked: popup.toggleScan()
                }
            }
        }
    }
}
