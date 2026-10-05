// FEATURE: connectivity - bar widget "connectivity", its popup: network
// QUICK CONTROL (v2). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. See docs/feature-architecture.md
// "Network". Administration (VPN add/import/edit/delete, Ethernet/static
// IP/DNS, WPA-Enterprise) is nm-connection-editor (OS menu -> Network).
//
// A BarPopup (click outside / Escape closes, exists only while open).
//   Status   NetworkManager's connectivity (portal -> "Login required":
//            opens NM's own check URL in Chromium so the portal redirects),
//            global addresses per interface (`ip -j -d addr`, on open and on
//            NM events), the default gateway (Model.qml, kernel routes),
//            "via VPN" also for a policy-routed full tunnel (`ip route get`,
//            same moments - see tunnelDefault),
//            traffic of the default-route interface: the ONLY sampling - a
//            1 s Timer reading /sys/class/net/<if>/statistics (and the kernel
//            routes), alive only while this popup exists, following the
//            interface if the default route moves.
//   VPN      NetworkManager VPN/WireGuard profiles (`nmcli`, on open, on
//            NM events, after each action): activate/deactivate only.
//   Wi-Fi    Quickshell.Networking: radio on/off; Known networks (saved NM
//            profiles; hover X forgets) and Other networks (visible, not
//            saved; password inline for WPA/WPA3-Personal). Scanning only
//            while open. Secrets go straight to NetworkManager - never
//            logged or stored here. QR share of the current network.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs
import qs.bar

BarPopup {
    id: popup

    required property var net               // Model.qml of the bar widget

    readonly property string qrCommand: Quickshell.env("HOME") + "/.local/libexec/workstation/wifi-qr"

    // The client radio (a radio running a hotspot is not where networks are joined).
    readonly property var wifiDevice: {
        const wifi = Networking.devices.values.filter(d => d.type === DeviceType.Wifi);
        return wifi.find(d => d.mode === WifiDeviceMode.Station) || wifi.find(d => d.mode !== WifiDeviceMode.AccessPoint) || null;
    }
    readonly property bool wifiOn: Networking.wifiEnabled && Networking.wifiHardwareEnabled
    readonly property var networks: wifiDevice === null ? []
        : wifiDevice.networks.values.filter(n => n.name !== "")
    readonly property var knownNetworks: networks.filter(n => n.known)
        .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
    readonly property var otherNetworks: networks.filter(n => !n.known)
        .sort((a, b) => b.signalStrength - a.signalStrength)
    readonly property var currentNetwork: networks.find(n => n.connected) || null

    property var passwordFor: null      // network waiting for a password
    property var pendingPsk: null       // network we just sent a password for
    property bool pendingWasKnown: false
    property string pwError: ""
    property string message: ""
    property string qrSvg: ""           // QR code (contains the password) - memory only
    property bool qrRequested: false
    property var vpns: []               // [{name, uuid, type, active}]
    property string vpnBusy: ""         // uuid of a running up/down
    property var addresses: []          // [{iface, kind, v4: [], v6: ""}]
    // NetworkManager's WireGuard full tunnel (AllowedIPs 0.0.0.0/0, how NM
    // imports wg-quick files) routes by policy: its default route sits in a
    // table of its own behind an ip rule, the main table - all Model.qml
    // reads - keeps the physical default, and NM does not mark the profile
    // as default either. So the popup asks the kernel which interface an
    // internet packet would leave by (a FIB lookup, nothing is sent;
    // TEST-NET-3 address, never routed specifically).
    property string internetDev: ""
    readonly property bool tunnelDefault: internetDev !== "" && net.physical[internetDev] === undefined

    // Traffic (default-route interface) - see header.
    readonly property string trafficIface: net.primaryIface
    property real rxRate: -1
    property real txRate: -1
    property real lastRx: -1
    property real lastTx: -1
    property real lastT: 0

    function signalIcon(s) {
        return net.signalIcon(s);
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

    function activateNetwork(n) {
        message = "";
        if (n.connected) n.disconnect();
        else if (n.known || !secured(n)) n.connect();
        else if (personal(n)) { pwError = ""; passwordFor = n; }
        else message = "enterprise";
    }

    function submitPassword(pw) {
        if (passwordFor === null || pw.length < 8) return;
        pendingPsk = passwordFor;
        pendingWasKnown = passwordFor.known;
        pwError = "";
        passwordFor.connectWithPsk(pw);
    }

    function openSettings() {
        Quickshell.execDetached(["systemd-cat", "-t", "app-launch", "-p", "err", "--",
                                 "systemd-run", "--user", "--quiet", "--collect", "--", "nm-connection-editor"]);
        popup.closeRequested();
    }

    function rate(bps) {
        if (bps < 0) return "–";
        const u = ["B/s", "KiB/s", "MiB/s", "GiB/s"];
        let i = 0;
        while (bps >= 1024 && i < u.length - 1) { bps /= 1024; i++; }
        return (i === 0 ? Math.round(bps) : bps.toFixed(1)) + " " + u[i];
    }

    // Also re-reads the kernel routes (Model.update): while the popup is
    // open, even a route change NetworkManager announces no event for (a
    // metric reapply) shows within a second. Closed: events only.
    // The counters are read when both reloads have delivered (onLoaded) -
    // text() right after reload() is the previous content in Quickshell
    // 0.3.1 (see Model.qml).
    property int countersPending: 0
    function sample() {
        popup.net.update();
        if (trafficIface === "") return;
        countersPending = 2;
        rxFile.reload();
        txFile.reload();
    }

    function counterLoaded() {
        if (countersPending <= 0 || --countersPending > 0) return;
        const rx = parseFloat(rxFile.text()), tx = parseFloat(txFile.text()), t = Date.now();
        if (isNaN(rx) || isNaN(tx)) return;
        if (lastRx >= 0 && t > lastT) {
            rxRate = Math.max(0, (rx - lastRx) * 1000 / (t - lastT));
            txRate = Math.max(0, (tx - lastTx) * 1000 / (t - lastT));
        }
        lastRx = rx; lastTx = tx; lastT = t;
    }

    // Deferred: this runs while the model is still propagating its new
    // default route, and sample() re-reads the routes into that model -
    // synchronously that wrote into primary's own update (QML: binding
    // loop on primary, every route change with the popup open).
    onTrafficIfaceChanged: { lastRx = -1; lastTx = -1; rxRate = -1; txRate = -1; Qt.callLater(sample); }

    function refreshLists() {
        if (!vpnList.running) vpnList.running = true;
        if (!addrProc.running) addrProc.running = true;
        if (!routeGet.running) routeGet.running = true;
    }

    function toggleVpn(v) {
        vpnBusy = v.uuid;
        message = "";
        vpnAction.command = ["nmcli", "connection", v.active ? "down" : "up", "uuid", v.uuid];
        vpnAction.running = true;
    }

    function openPortal() {
        portalUri.running = true;
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

    panelWidth: 340
    keyFilter: event => {
        if (event.key !== Qt.Key_Escape) return false;
        if (passwordFor !== null) { passwordFor = null; pwError = ""; }
        else if (qrRequested) hideQr();
        else return false;
        return true;
    }

    Component.onCompleted: {
        if (wifiDevice !== null && wifiOn) wifiDevice.scannerEnabled = true;
        refreshLists();
        sample();
    }
    Component.onDestruction: {
        if (wifiDevice !== null) wifiDevice.scannerEnabled = false;
        qrSvg = "";
    }

    onWifiOnChanged: if (wifiDevice !== null) wifiDevice.scannerEnabled = wifiOn
    onCurrentNetworkChanged: hideQr()

    // NetworkManager changed something: addresses and VPN states follow.
    Connections {
        target: popup.net
        function onNmStateChanged() { popup.refreshLists(); }
    }

    // The only sampling of this feature: exists with the popup, 1 s.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: popup.sample()
    }

    FileView {
        id: rxFile
        path: popup.trafficIface !== "" ? "/sys/class/net/" + popup.trafficIface + "/statistics/rx_bytes" : ""
        blockLoading: true
        printErrors: false
        onLoaded: popup.counterLoaded()
    }

    FileView {
        id: txFile
        path: popup.trafficIface !== "" ? "/sys/class/net/" + popup.trafficIface + "/statistics/tx_bytes" : ""
        blockLoading: true
        printErrors: false
        onLoaded: popup.counterLoaded()
    }

    // A pending password connect: success clears it, failure keeps the box.
    Connections {
        target: popup.pendingPsk
        function onConnectedChanged() {
            if (popup.pendingPsk && popup.pendingPsk.connected) {
                popup.pendingPsk = null;
                popup.passwordFor = null;
                popup.pwError = "";
            }
        }
        // NM saved a profile for the attempt; a network that was not known
        // before must not become "known" with a wrong password: forget it.
        function onConnectionFailed(reason) {
            const n = popup.pendingPsk;
            Log.warn("network", "Wi-Fi \"" + n.name + "\": connecting with a new password failed ("
                     + ConnectionFailReason.toString(reason) + ")");
            popup.pwError = reason === ConnectionFailReason.NoSecrets ? "Wrong password - try again"
                                                                      : "Could not connect - try again";
            if (!popup.pendingWasKnown && n.known) n.forget();
            popup.passwordFor = n;
            popup.pendingPsk = null;
        }
    }

    Process {
        id: addrProc
        command: ["ip", "-j", "-d", "addr", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    Log.warn("network", "`ip -j -d addr` returned no JSON - addresses not shown");
                }
                popup.addresses = list.filter(l => l.ifname !== "lo" && (l.addr_info || []).some(a => a.scope === "global"))
                    .map(l => {
                        const kindOf = popup.net.physical[l.ifname]
                            || (l.linkinfo && ["wireguard", "tun"].indexOf(l.linkinfo.info_kind) !== -1 ? "vpn" : "other");
                        const g = (l.addr_info || []).filter(a => a.scope === "global");
                        const v6 = g.filter(a => a.family === "inet6");
                        const stable = v6.find(a => !a.temporary) || v6[0];
                        return { iface: l.ifname, kind: kindOf,
                                 v4: g.filter(a => a.family === "inet").map(a => a.local),
                                 v6: stable ? stable.local : "" };
                    });
            }
        }
    }

    Process {
        id: routeGet
        command: ["ip", "-j", "route", "get", "203.0.113.1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    popup.internetDev = r.length > 0 && r[0].dev ? r[0].dev : "";
                } catch (e) {
                    popup.internetDev = "";   // no IPv4 route at all: nothing to say
                }
            }
        }
    }

    Process {
        id: portalUri
        command: ["busctl", "get-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
                  "org.freedesktop.NetworkManager", "ConnectivityCheckUri"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^s "(.*)"\s*$/);
                if (m && m[1] !== "") {
                    Quickshell.execDetached(["chromium", m[1]]);
                    popup.closeRequested();
                } else {
                    popup.message = "NetworkManager has no connectivity check URL";
                    Log.warn("network", "captive portal: NetworkManager reports no ConnectivityCheckUri - check /usr/lib/NetworkManager/conf.d/*connectivity*");
                }
            }
        }
    }

    Process {
        id: qrProc
        stdout: StdioCollector {
            onStreamFinished: if (popup.qrRequested) popup.qrSvg = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                Log.warn("network", "wifi-qr exited " + exitCode + (exitCode === 2 ? " (no readable PSK for this network)" : ""));
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
            if (exitCode !== 0) {
                popup.message = "VPN: " + (vpnErr.text.split("\n").filter(l => l.startsWith("Error"))[0] || "failed");
                Log.warn("network", "`" + command.slice(0, 3).join(" ") + "` (VPN) failed (exit " + exitCode + "): " + Log.firstLine(vpnErr.text));
            }
            popup.vpnBusy = "";
            popup.refreshLists();
        }
    }

    component SectionHeader: RowLayout {
        id: header
        property string title
        default property alias controls: extra.data

        Layout.fillWidth: true
        Layout.topMargin: 10

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

    component SubTitle: Text {
        Layout.topMargin: 4
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: popup.fontSize - 2
    }

    component InfoRow: RowLayout {
        id: info
        property string icon
        property string text
        property bool muted: false
        Layout.fillWidth: true
        Layout.leftMargin: 6
        spacing: 8

        Text {
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            text: info.icon
            color: info.muted ? Colors.foregroundMuted : Colors.foreground
            font.family: Fonts.icons
            font.pixelSize: popup.fontSize
        }

        Text {
            Layout.fillWidth: true
            text: info.text
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: info.muted ? Colors.foregroundMuted : Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
        }
    }

    // A Wi-Fi network row. Right side: lock (secured) - for a known network
    // an X replaces it while hovered: forget, without triggering the row.
    component NetworkRow: Rectangle {
        id: row
        required property var network
        readonly property bool hovered: rowMouse.containsMouse || forgetMouse.containsMouse

        Layout.fillWidth: true
        implicitHeight: row.network.connected || row.network.stateChanging ? 40 : 30
        radius: 4
        color: row.network.connected ? Colors.surface : hovered ? Colors.surface : "transparent"
        border.color: row.network.connected ? Colors.accent : "transparent"
        border.width: row.network.connected ? 1 : 0

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: popup.activateNetwork(row.network)
        }

        Connections {
            target: row.network
            // A password attempt logs once, in the popup's own handler; its
            // handler may run first (then pendingPsk is already cleared and
            // passwordFor is set again) - either order must not log twice.
            function onConnectionFailed(reason) {
                if (popup.pendingPsk !== row.network && popup.passwordFor !== row.network)
                    Log.warn("network", "Wi-Fi \"" + row.network.name + "\": connection failed (" + ConnectionFailReason.toString(reason) + ")");
            }
        }

        Text {
            id: sig
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: popup.signalIcon(row.network.signalStrength)
            color: row.network.connected ? Colors.accent : Colors.foreground
            font.family: Fonts.icons
            font.pixelSize: popup.fontSize + 1
        }

        Column {
            anchors.left: sig.right
            anchors.leftMargin: 8
            anchors.right: right.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: row.network.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 1
            }

            Text {
                visible: row.network.connected || row.network.stateChanging
                text: row.network.stateChanging ? "Connecting…" : "Connected"
                color: row.network.connected ? Colors.accent : Colors.foregroundMuted
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
                visible: !(row.network.known && row.hovered) && popup.secured(row.network)
                text: "\u{F033E}"           // lock
                color: Colors.foregroundMuted
                font.family: Fonts.icons
                font.pixelSize: popup.fontSize - 1
            }

            Rectangle {
                anchors.fill: parent
                visible: row.network.known && row.hovered
                radius: 4
                color: forgetMouse.containsMouse ? Colors.error : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u{F0156}"       // close (X)
                    color: forgetMouse.containsMouse ? Colors.background : Colors.error
                    font.family: Fonts.icons
                    font.pixelSize: popup.fontSize
                }
            }

            // Above the row's own MouseArea: this click forgets, nothing else.
            MouseArea {
                id: forgetMouse
                anchors.fill: parent
                enabled: row.network.known
                hoverEnabled: true
                onClicked: row.network.forget()
            }
        }
    }

    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(content.implicitHeight, popup.maxPanelHeight - 2 * BarStyle.popupPadding)
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: parent.width
            spacing: 3

            // ---- Status ----------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: popup.net.icon
                    color: popup.net.kind === "none" ? Colors.foregroundMuted : Colors.accent
                    font.family: Fonts.icons
                    font.pixelSize: popup.fontSize + 3
                }

                Text {
                    Layout.fillWidth: true
                    readonly property int c: Networking.connectivity
                    text: popup.net.kind === "none" ? "Disconnected"
                        : c === NetworkConnectivity.Portal ? "Login required"
                        : c === NetworkConnectivity.Limited ? "Limited connectivity"
                        : c === NetworkConnectivity.None ? "No internet"
                        : (popup.net.kind === "wifi" ? "Wi-Fi" : "Ethernet") + (popup.net.vpnDefault || popup.tunnelDefault ? "  ·  via VPN" : "")
                    color: c === NetworkConnectivity.Portal || c === NetworkConnectivity.Limited
                           || (c === NetworkConnectivity.None && popup.net.kind !== "none") ? Colors.error : Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize
                    font.bold: true
                }

                PopupButton {
                    visible: Networking.connectivity === NetworkConnectivity.Portal
                    primary: true
                    label: "Log in"
                    onClicked: popup.openPortal()
                }
            }

            Repeater {
                model: popup.addresses

                ColumnLayout {
                    id: addrRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    Repeater {
                        model: addrRow.modelData.v4
                        InfoRow {
                            required property string modelData
                            icon: popup.net.typeIcon(addrRow.modelData.kind)
                            text: modelData
                        }
                    }

                    // At most one IPv6 per interface (a stable one), dimmed.
                    InfoRow {
                        visible: addrRow.modelData.v6 !== ""
                        icon: addrRow.modelData.v4.length === 0 ? popup.net.typeIcon(addrRow.modelData.kind) : ""
                        text: addrRow.modelData.v6
                        muted: true
                    }
                }
            }

            SubTitle {
                visible: popup.net.gateway !== ""
                text: "Gateway"
            }

            InfoRow {
                visible: popup.net.gateway !== ""
                icon: popup.net.typeIcon(popup.net.kind)
                text: popup.net.gateway
            }

            InfoRow {
                visible: popup.trafficIface !== ""
                Layout.topMargin: 4
                icon: popup.net.typeIcon(popup.net.kind)
                text: "↓ " + popup.rate(popup.rxRate) + "    ↑ " + popup.rate(popup.txRate)
            }

            // ---- VPN ---------------------------------------------------
            SectionHeader {
                title: "VPN"
            }

            SubTitle {
                visible: popup.vpns.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "No VPN connections - add them in Network settings (OS menu)"
            }

            Repeater {
                model: popup.vpns

                Rectangle {
                    id: vrow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.active ? 40 : 30
                    radius: 4
                    color: modelData.active || vMouse.containsMouse ? Colors.surface : "transparent"
                    border.color: modelData.active ? Colors.accent : "transparent"
                    border.width: modelData.active ? 1 : 0

                    Text {
                        id: vIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F0582}"
                        color: vrow.modelData.active ? Colors.accent : Colors.foreground
                        font.family: Fonts.icons
                        font.pixelSize: popup.fontSize + 1
                    }

                    Column {
                        anchors.left: vIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: vrow.modelData.name + (vrow.modelData.type === "wireguard" ? "  (WireGuard)" : "")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize - 1
                        }

                        Text {
                            visible: vrow.modelData.active || popup.vpnBusy === vrow.modelData.uuid
                            text: popup.vpnBusy === vrow.modelData.uuid ? "…" : "Connected"
                            color: Colors.accent
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize - 3
                        }
                    }

                    MouseArea {
                        id: vMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (popup.vpnBusy === "") popup.toggleVpn(vrow.modelData)
                    }
                }
            }

            // ---- Wi-Fi ------------------------------------------------
            SectionHeader {
                title: "Wi-Fi"

                PopupButton {
                    visible: popup.wifiDevice !== null && Networking.wifiHardwareEnabled
                    label: Networking.wifiEnabled ? "On" : "Off"
                    primary: Networking.wifiEnabled
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }

            SubTitle {
                visible: popup.wifiDevice === null || !Networking.wifiHardwareEnabled
                text: popup.wifiDevice === null ? "No Wi-Fi device" : "Wi-Fi blocked by a hardware switch"
            }

            SubTitle {
                visible: popup.wifiOn && popup.knownNetworks.length > 0
                text: "Known networks"
            }

            Repeater {
                model: popup.wifiOn ? popup.knownNetworks : []
                delegate: NetworkRow {
                    required property var modelData
                    network: modelData
                }
            }

            PopupButton {
                visible: popup.wifiOn && !popup.qrRequested && popup.currentNetwork !== null
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

            SubTitle {
                visible: popup.wifiOn && popup.otherNetworks.length > 0
                text: "Other networks"
            }

            Repeater {
                model: popup.wifiOn ? popup.otherNetworks : []
                delegate: NetworkRow {
                    required property var modelData
                    network: modelData
                }
            }

            SubTitle {
                visible: popup.wifiOn && popup.wifiDevice !== null && popup.networks.length === 0
                text: "Searching…"
            }

            // Password for a protected network (WPA/WPA2/WPA3-Personal).
            Rectangle {
                visible: popup.passwordFor !== null || popup.pendingPsk !== null
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: pwBox.implicitHeight + 16
                radius: 6
                color: Colors.surface
                border.color: popup.pwError !== "" ? Colors.error : Colors.borderActive
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
                        readonly property var n: popup.passwordFor || popup.pendingPsk
                        text: popup.pendingPsk !== null ? "Connecting to " + (n ? n.name : "") + "…"
                                                        : "Password for " + (n ? n.name : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: popup.fontSize - 1
                    }

                    Rectangle {
                        visible: popup.pendingPsk === null
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 4
                        color: Colors.background
                        border.color: Colors.border
                        border.width: 1

                        TextInput {
                            id: pwInput
                            anchors.fill: parent
                            anchors.margins: 6
                            echoMode: TextInput.Password
                            color: Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: popup.fontSize
                            maximumLength: 63
                            onVisibleChanged: {
                                text = "";
                                if (visible) forceActiveFocus();
                                else popup.restoreKeyFocus();
                            }
                            Keys.onReturnPressed: { popup.submitPassword(text); text = ""; }
                            Keys.onEscapePressed: { text = ""; popup.passwordFor = null; popup.pwError = ""; }
                        }
                    }

                    Text {
                        visible: popup.pwError !== ""
                        text: popup.pwError
                        color: Colors.error
                        font.family: Fonts.family
                        font.pixelSize: popup.fontSize - 2
                    }

                    RowLayout {
                        visible: popup.pendingPsk === null
                        Layout.alignment: Qt.AlignRight
                        spacing: 6

                        PopupButton {
                            label: "Cancel"
                            onClicked: { pwInput.text = ""; popup.passwordFor = null; popup.pwError = ""; }
                        }

                        PopupButton {
                            primary: true
                            label: "Connect"
                            onClicked: { popup.submitPassword(pwInput.text); pwInput.text = ""; }
                        }
                    }
                }
            }

            // Enterprise (802.1X/eduroam) or WEP: configured in the editor.
            RowLayout {
                visible: popup.message === "enterprise"
                Layout.fillWidth: true
                Layout.topMargin: 4

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Enterprise (802.1X, eduroam) networks are set up in Network settings."
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize - 2
                }

                PopupButton {
                    label: "Open"
                    onClicked: popup.openSettings()
                }
            }

            Text {
                visible: popup.message !== "" && popup.message !== "enterprise"
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
