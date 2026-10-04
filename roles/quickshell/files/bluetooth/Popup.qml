// FEATURE: bluetooth - bar widget "bluetooth", its popup. Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// A BarPopup: a click outside or Escape closes it; it exists only while
// open, so a closed popup leaves no surface and no keyboard focus behind.
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
import qs
import qs.bar

BarPopup {
    id: popup

    required property var adapter

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
        if (text !== "") Log.warn("bluetooth", "pairing " + (pairingDevice ? deviceLabel(pairingDevice) : "device") + ": " + text);
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

    // Device type from BlueZ's own Icon property (derived by BlueZ from the
    // device class / appearance) -> a monochrome Nerd Font glyph, drawn in
    // theme colors like every other icon. Never guessed from the name;
    // unknown or missing -> the Bluetooth glyph.
    function deviceGlyph(d) {
        const icon = d.icon || "";
        if (icon === "audio-headphones") return "\u{F02CB}";           // headphones
        if (icon === "audio-headset") return "\u{F02CE}";              // headset
        if (icon.startsWith("audio") || icon === "multimedia-player") return "\u{F04C3}"; // speaker
        if (icon === "input-keyboard") return "\u{F030C}";             // keyboard
        if (icon === "input-mouse" || icon === "input-tablet") return "\u{F037D}"; // mouse
        if (icon === "input-gaming") return "\u{F0297}";               // gamepad
        if (icon === "phone" || icon === "modem") return "\u{F011C}";  // cellphone
        if (icon === "computer") return "\u{F0322}";                   // laptop
        if (icon === "video-display") return "\u{F0379}";              // monitor
        if (icon === "printer" || icon === "scanner") return "\u{F042A}"; // printer
        if (icon.startsWith("camera")) return "\u{F0100}";             // camera
        return "\u{F00AF}";                                            // bluetooth
    }

    function batteryText(d) {
        if (!d.batteryAvailable) return "";
        return Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) + "%";
    }

    keyFilter: event => {
        if (event.key !== Qt.Key_Escape || agentRequest === null) return false;
        answer(false);
        return true;
    }

    Component.onCompleted: {
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
                    Log.warn("bluetooth", "`rfkill --json` returned no JSON - block state unknown");
                }
            }
        }
    }

    Process {
        id: unblockProc
        command: ["rfkill", "unblock", "bluetooth"]
        onExited: exitCode => {
            if (exitCode !== 0) {
                popup.message = "Could not unblock Bluetooth";
                Log.warn("bluetooth", "`rfkill unblock bluetooth` failed (exit " + exitCode + ")");
            }
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

    component SectionTitle: Text {
        Layout.topMargin: 6
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: popup.fontSize - 2
    }

    // Row click = the action: disconnect (connected), connect (known),
    // pair (new; click again while pairing cancels). Right side: a state
    // icon - for a known (paired) device an X replaces it while hovered:
    // forget, in its own click area, never the row action.
    function rowAction(d) {
        if (d.connected) d.disconnect();
        else if (d.paired) d.connect();
        else if (pairingDevice === d) { d.cancelPair(); finishPairing(""); }
        else startPair(d);
    }

    component DeviceRow: Rectangle {
        id: row
        required property var device
        readonly property bool hovered: rowMouse.containsMouse || forgetMouse.containsMouse
        readonly property bool busy: device.state === BluetoothDeviceState.Connecting
                                     || device.state === BluetoothDeviceState.Disconnecting || device.pairing

        Layout.fillWidth: true
        implicitHeight: 36
        radius: 4
        color: row.device.connected || row.hovered ? Colors.surface : "transparent"
        border.color: row.device.connected ? Colors.accent : "transparent"
        border.width: row.device.connected ? 1 : 0
        opacity: popup.pairingDevice !== null && popup.pairingDevice !== row.device ? 0.5 : 1

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: popup.pairingDevice === null || popup.pairingDevice === row.device
            onClicked: popup.rowAction(row.device)
        }

        Text {
            id: devIcon
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: popup.deviceGlyph(row.device)
            color: row.device.connected ? Colors.accent : Colors.foreground
            font.family: Fonts.icons
            font.pixelSize: popup.fontSize + 2
        }

        Column {
            anchors.left: devIcon.right
            anchors.leftMargin: 8
            anchors.right: right.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: popup.deviceLabel(row.device)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 1
            }

            Text {
                readonly property string stateText:
                    row.device.state === BluetoothDeviceState.Connecting ? "Connecting…"
                    : row.device.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                    : row.device.pairing || popup.pairingDevice === row.device ? "Pairing…"
                    : row.device.connected ? "Connected" : ""
                readonly property string battery: popup.batteryText(row.device)
                visible: text !== ""
                text: [stateText, battery !== "" ? "\u{F0079} " + battery : ""].filter(s => s !== "").join("   ")
                color: row.device.connected ? Colors.accent : Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 3
            }
        }

        Item {
            id: right
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24

            Text {
                anchors.centerIn: parent
                visible: !(row.device.paired && row.hovered)
                text: row.busy ? "…"
                    : row.device.connected ? "\u{F00B1}"           // bluetooth-connect
                    : row.device.paired ? "\u{F00AF}"              // bluetooth
                    : "\u{F0415}"                                  // plus: pair
                color: row.device.connected ? Colors.accent : Colors.foregroundMuted
                font.family: Fonts.icons
                font.pixelSize: popup.fontSize
            }

            Rectangle {
                anchors.fill: parent
                visible: row.device.paired && row.hovered
                radius: 4
                color: forgetMouse.containsMouse ? Colors.error : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u{F0156}"                               // close (X)
                    color: forgetMouse.containsMouse ? Colors.background : Colors.error
                    font.family: Fonts.icons
                    font.pixelSize: popup.fontSize
                }
            }

            // Above the row's own MouseArea: forget, nothing else.
            MouseArea {
                id: forgetMouse
                anchors.fill: parent
                enabled: row.device.paired
                hoverEnabled: true
                onClicked: row.device.forget()
            }
        }
    }

    panelWidth: 320

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
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

            PopupButton {
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

            PopupButton {
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

                    PopupButton {
                        label: "Cancel"
                        onClicked: {
                            if (pairBox.req.event === "display") {
                                if (popup.pairingDevice) popup.pairingDevice.cancelPair();
                                popup.finishPairing("");
                            } else popup.answer(false);
                        }
                    }

                    PopupButton {
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

                SectionTitle { visible: popup.pairedDevices.length > 0; text: "Known devices" }
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

            PopupButton {
                label: popup.adapter.discovering ? "Stop" : "Scan"
                onClicked: popup.toggleScan()
            }
        }
    }
}
