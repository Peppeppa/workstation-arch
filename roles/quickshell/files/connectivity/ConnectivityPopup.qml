// FEATURE: connectivity - the Connectivity Center opened from the bar's
// network label (ConnectivityControl.qml). Managed by Ansible: do not edit
// by hand, see roles/quickshell in workstation-arch.
//
// Same overlay pattern as the other popups (click outside / Escape
// closes, created by a Loader only while open). Sections:
//   Wi-Fi     Quickshell.Networking (NetworkManager over D-Bus, the only
//             Wi-Fi owner): radio on/off, current network, available
//             networks (signal, secured, known), connect/disconnect/forget,
//             password entry for new WPA/WPA3-Personal networks. Scanning
//             only while the popup is open. The password goes straight to
//             NetworkManager (connectWithPsk) - not logged, not stored here.
//   QR        on request only: wifi-qr (one-shot helper) reads the active
//             network's password from NetworkManager and returns an SVG
//             QR code, held in memory while shown. Not for enterprise/WEP.
//   Bluetooth (bluetooth feature) adapter on/off + connected devices; the
//             full Bluetooth popup (BluetoothPopup.qml) opens via "More".
//   VPN       NetworkManager VPN/WireGuard connections: `nmcli` once on
//             open and after each action (no monitor process), up/down by
//             UUID with a fixed argv.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland

PanelWindow {
    id: popup

    required property real anchorX
    required property int barHeight
    required property int fontSize
    required property bool bluetoothEnabled

    readonly property string qrCommand: Quickshell.env("HOME") + "/.local/libexec/workstation/wifi-qr"

    // The client radio (a radio running a hotspot is not where networks are joined).
    readonly property var wifiDevice: {
        const wifi = Networking.devices.values.filter(d => d.type === DeviceType.Wifi);
        return wifi.find(d => d.mode === WifiDeviceMode.Station) || wifi.find(d => d.mode !== WifiDeviceMode.AccessPoint) || null;
    }
    readonly property bool wifiOn: Networking.wifiEnabled && Networking.wifiHardwareEnabled
    readonly property var networks: wifiDevice === null ? []
        : wifiDevice.networks.values.filter(n => n.name !== "").sort((a, b) =>
              (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    readonly property var currentNetwork: networks.find(n => n.connected) || null
    readonly property var otherNetworks: networks.filter(n => !n.connected)

    readonly property var btAdapter: bluetoothEnabled ? Bluetooth.defaultAdapter : null

    property var passwordFor: null      // network waiting for a password
    property string message: ""
    property string qrSvg: ""           // QR code (contains the password) - memory only
    property bool qrRequested: false
    property var vpns: []               // [{name, uuid, type, active}]
    property string vpnBusy: ""         // uuid of a running up/down

    signal closeRequested
    signal bluetoothRequested

    function signalIcon(s) {
        const v = s > 1 ? s / 100 : s;
        return v > 0.75 ? "\u{F0928}" : v > 0.5 ? "\u{F0925}" : v > 0.25 ? "\u{F0922}" : "\u{F091F}";
    }

    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
            && n.security !== WifiSecurityType.Unknown;
    }

    // WPA/WPA2/WPA3-Personal: the only kinds a password field can join.
    function personal(n) {
        return n.security === WifiSecurityType.WpaPsk || n.security === WifiSecurityType.Wpa2Psk
            || n.security === WifiSecurityType.Sae;
    }

    function connectNetwork(n) {
        message = "";
        if (n.known || !secured(n)) n.connect();
        else if (personal(n)) passwordFor = n;
        else message = "Enterprise/WEP networks: set up with nmtui";
    }

    function showQr() {
        qrSvg = "";
        qrRequested = true;
        qrProc.command = [qrCommand, wifiDevice.name];
        qrProc.running = true;
    }

    function hideQr() {
        qrRequested = false;
        qrSvg = "";
    }

    function refreshVpns() {
        if (!vpnList.running) vpnList.running = true;
    }

    function toggleVpn(v) {
        vpnBusy = v.uuid;
        message = "";
        vpnAction.command = ["nmcli", "connection", v.active ? "down" : "up", "uuid", v.uuid];
        vpnAction.running = true;
    }

    // nmcli -t output: fields separated by ':', literal ':' and '\' escaped.
    function splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) cur += line[++i];
            else if (c === ":") { out.push(cur); cur = ""; }
            else cur += c;
        }
        out.push(cur);
        return out;
    }

    Component.onCompleted: {
        keyHandler.forceActiveFocus();
        if (wifiDevice !== null && wifiOn) wifiDevice.scannerEnabled = true;
        refreshVpns();
    }
    Component.onDestruction: {
        if (wifiDevice !== null) wifiDevice.scannerEnabled = false;
        qrSvg = "";
    }

    // Wi-Fi turned on while open: start scanning.
    onWifiOnChanged: if (wifiDevice !== null) wifiDevice.scannerEnabled = wifiOn

    // The QR code belongs to the network it was made for.
    onCurrentNetworkChanged: hideQr()

    Process {
        id: qrProc
        stdout: StdioCollector {
            onStreamFinished: if (popup.qrRequested) popup.qrSvg = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                popup.hideQr();
                popup.message = exitCode === 2 ? "No QR code for this network (password not readable or enterprise)"
                                               : "QR code unavailable";
            }
        }
    }

    Process {
        id: vpnList
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                popup.vpns = text.split("\n").filter(l => l !== "").map(l => popup.splitTerse(l))
                    .filter(f => f.length === 4 && (f[2] === "vpn" || f[2] === "wireguard"))
                    .map(f => ({ name: f[0], uuid: f[1], type: f[2], active: f[3] === "yes" }));
            }
        }
    }

    Process {
        id: vpnAction
        stderr: StdioCollector {
            id: vpnErr
        }
        onExited: exitCode => {
            if (exitCode !== 0) popup.message = "VPN: " + (vpnErr.text.split("\n").filter(l => l.startsWith("Error"))[0] || "failed");
            popup.vpnBusy = "";
            popup.refreshVpns();
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
    WlrLayershell.namespace: "quickshell-connectivity"

    MouseArea {
        anchors.fill: parent
        onClicked: popup.closeRequested()
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (popup.passwordFor !== null) popup.passwordFor = null;
            else if (popup.qrRequested) popup.hideQr();
            else popup.closeRequested();
        }
    }

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

    component SectionHeader: RowLayout {
        id: header
        property string title
        default property alias controls: extra.data

        Layout.fillWidth: true
        Layout.topMargin: 8

        Text {
            Layout.fillWidth: true
            text: header.title
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize
            font.bold: true
        }

        Row {
            id: extra
            spacing: 6
        }
    }

    component Note: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: popup.fontSize - 2
    }

    component NetworkRow: Rectangle {
        id: row
        required property var network
        property bool confirmForget: false

        Layout.fillWidth: true
        implicitHeight: 30
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

            Text {
                text: popup.signalIcon(row.network.signalStrength)
                color: row.network.connected ? Colors.accent : Colors.foreground
                font.family: Fonts.icons
                font.pixelSize: popup.fontSize + 1
            }

            Text {
                Layout.fillWidth: true
                text: row.network.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 1
            }

            Text {
                text: [row.network.stateChanging ? "…" : "",
                       row.network.known && !row.network.connected ? "known" : "",
                       popup.secured(row.network) ? "\u{F033E}" : ""].filter(s => s !== "").join(" ")
                color: Colors.foregroundMuted
                font.family: Fonts.icons
                font.pixelSize: popup.fontSize - 2
            }

            ActionButton {
                visible: row.network.known
                label: row.confirmForget ? "Forget?" : "\uf1f8"
                danger: true
                onClicked: {
                    if (row.confirmForget) row.network.forget();
                    else row.confirmForget = true;
                }
            }

            ActionButton {
                label: row.network.connected ? "Disconnect" : "Connect"
                onClicked: row.network.connected ? row.network.disconnect() : popup.connectNetwork(row.network)
            }
        }

        // A failed connect to a network that needs a password: ask for it.
        Connections {
            target: row.network
            function onConnectionFailed(reason) {
                if (reason === ConnectionFailReason.NoSecrets && popup.personal(row.network))
                    popup.passwordFor = row.network;
                else
                    popup.message = "Could not connect to " + row.network.name;
            }
        }
    }

    Rectangle {
        readonly property int panelWidth: 340

        x: Math.max(6, Math.min(popup.anchorX - panelWidth / 2, popup.width - panelWidth - 6))
        y: popup.barHeight + 4
        width: panelWidth
        implicitHeight: Math.min(content.implicitHeight + 20, popup.height - popup.barHeight - 12)
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 10
            contentHeight: content.implicitHeight
            clip: true

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 4

                // ---- Wi-Fi ------------------------------------------------
                SectionHeader {
                    Layout.topMargin: 0
                    title: "Wi-Fi"

                    ActionButton {
                        visible: popup.wifiDevice !== null && Networking.wifiHardwareEnabled
                        label: Networking.wifiEnabled ? "On" : "Off"
                        primary: Networking.wifiEnabled
                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                }

                Note {
                    visible: popup.wifiDevice === null || !Networking.wifiHardwareEnabled
                    text: popup.wifiDevice === null ? "No Wi-Fi device" : "Wi-Fi blocked by a hardware switch"
                }

                // Current network + QR.
                ColumnLayout {
                    visible: popup.wifiOn && popup.currentNetwork !== null
                    Layout.fillWidth: true
                    spacing: 4

                    Loader {
                        Layout.fillWidth: true
                        active: popup.currentNetwork !== null
                        sourceComponent: NetworkRow { network: popup.currentNetwork }
                    }

                    ActionButton {
                        visible: !popup.qrRequested && popup.currentNetwork !== null
                                 && (popup.personal(popup.currentNetwork) || !popup.secured(popup.currentNetwork))
                        Layout.alignment: Qt.AlignRight
                        label: "\u{F0432}  Share (QR)"
                        onClicked: popup.showQr()
                    }

                    Rectangle {
                        visible: popup.qrRequested
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 196
                        implicitHeight: 196
                        radius: 6
                        color: Colors.surface

                        Image {
                            anchors.centerIn: parent
                            width: 180
                            height: 180
                            sourceSize.width: 180
                            sourceSize.height: 180
                            smooth: false
                            cache: false        // the QR encodes the password: not in Qt's pixmap cache
                            source: popup.qrSvg !== "" ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(popup.qrSvg) : ""
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: popup.hideQr()
                        }
                    }
                }

                // Password for a new network (WPA/WPA3-Personal).
                Rectangle {
                    visible: popup.passwordFor !== null
                    Layout.fillWidth: true
                    implicitHeight: pwBox.implicitHeight + 16
                    radius: 6
                    color: Colors.surface
                    border.color: Colors.borderActive
                    border.width: 1

                    ColumnLayout {
                        id: pwBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: "Password for " + (popup.passwordFor ? popup.passwordFor.name : "")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize - 1
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 4
                            color: Colors.background
                            border.color: Colors.border
                            border.width: 1

                            TextInput {
                                id: pwInput
                                function submit() {
                                    if (text.length < 8 || popup.passwordFor === null) return;
                                    popup.passwordFor.connectWithPsk(text);
                                    text = "";
                                    popup.passwordFor = null;
                                }
                                anchors.fill: parent
                                anchors.margins: 6
                                echoMode: TextInput.Password
                                color: Colors.foreground
                                font.family: Fonts.family
                                font.pixelSize: popup.fontSize
                                maximumLength: 63
                                onVisibleChanged: { text = ""; if (visible) forceActiveFocus(); }
                                Keys.onReturnPressed: submit()
                                Keys.onEscapePressed: { text = ""; popup.passwordFor = null; }
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 6

                            ActionButton {
                                label: "Cancel"
                                onClicked: { pwInput.text = ""; popup.passwordFor = null; }
                            }

                            ActionButton {
                                primary: true
                                label: "Connect"
                                onClicked: pwInput.submit()
                            }
                        }
                    }
                }

                Repeater {
                    model: popup.wifiOn ? popup.otherNetworks : []
                    delegate: NetworkRow {
                        required property var modelData
                        network: modelData
                    }
                }

                Note {
                    visible: popup.wifiOn && popup.networks.length === 0
                    text: "Searching…"
                }

                // ---- Bluetooth (bluetooth feature) -------------------------
                SectionHeader {
                    visible: popup.btAdapter !== null
                    title: "Bluetooth"

                    ActionButton {
                        visible: popup.btAdapter !== null && popup.btAdapter.state !== BluetoothAdapterState.Blocked
                        label: popup.btAdapter && popup.btAdapter.enabled ? "On" : "Off"
                        primary: popup.btAdapter !== null && popup.btAdapter.enabled
                        onClicked: popup.btAdapter.enabled = !popup.btAdapter.enabled
                    }

                    ActionButton {
                        label: "More"
                        onClicked: popup.bluetoothRequested()
                    }
                }

                Note {
                    visible: popup.btAdapter !== null
                    text: {
                        if (popup.btAdapter === null) return "";
                        if (popup.btAdapter.state === BluetoothAdapterState.Blocked) return "Blocked";
                        if (!popup.btAdapter.enabled) return "Off";
                        const c = popup.btAdapter.devices.values.filter(d => d.connected).map(d => d.name || d.address);
                        return c.length > 0 ? "Connected: " + c.join(", ") : "No device connected";
                    }
                }

                // ---- VPN ---------------------------------------------------
                SectionHeader {
                    title: "VPN"
                }

                Note {
                    visible: popup.vpns.length === 0
                    text: "No VPN connections (add them with nmcli/nmtui)"
                }

                Repeater {
                    model: popup.vpns

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        spacing: 8

                        Text {
                            text: "\u{F0582}"
                            color: modelData.active ? Colors.accent : Colors.foregroundMuted
                            font.family: Fonts.icons
                            font.pixelSize: popup.fontSize + 1
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name + (modelData.type === "wireguard" ? "  (WireGuard)" : "")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize - 1
                        }

                        ActionButton {
                            label: popup.vpnBusy === modelData.uuid ? "…"
                                 : modelData.active ? "Disconnect" : "Connect"
                            onClicked: if (popup.vpnBusy === "") popup.toggleVpn(modelData)
                        }
                    }
                }

                Text {
                    visible: popup.message !== ""
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: popup.message
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize - 2
                }
            }
        }
    }
}
