// FEATURE: connectivity - bar widget "connectivity", its popup: network
// QUICK CONTROL (v2). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. See docs/feature-architecture.md
// "Network". Administration (VPN add/import/edit/delete, Ethernet/static
// IP/DNS, WPA-Enterprise) is nm-connection-editor: the popup's own
// "Connections..." button at the bottom, or OS menu -> Network.
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
//            saved; password inline for WPA/WPA3-Personal, own scroll area
//            of ten rows, Up/Down/Enter). Scanning only while open. Secrets
//            go straight to NetworkManager - never logged, stored, put in
//            argv or the clipboard here. QR share of the current network.

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
    readonly property var knownNetworks: networks.filter(n => n.known && n.name !== authSsid)
        .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
    // SSID -> network object (the rows look their network up by name).
    readonly property var byName: {
        const m = {};
        for (const n of networks) if (!(n.name in m)) m[n.name] = n;
        return m;
    }

    // Other networks: a ListModel of SSIDs, NOT a JS array as the model.
    // A Repeater over an array recreates every row whenever the array is
    // re-evaluated - and the scan re-evaluated it on each result and signal
    // change, so the inline password box (its TextInput) was destroyed and
    // rebuilt: the typed password was lost (real use, long password). Rows
    // now keep their identity (key = SSID): syncOther() only moves, inserts
    // and removes what differs. While a password is being entered or sent
    // (authSsid) the list is frozen - no move, insert or removal; the wanted
    // order just keeps changing and is applied once, when the box closes
    // (cancel, success, popup closed). Everything else (Known, VPN, status)
    // keeps updating.
    readonly property var otherWanted: networks.filter(n => !n.known || n.name === authSsid)
        .sort((a, b) => b.signalStrength - a.signalStrength).map(n => n.name)
    onOtherWantedChanged: syncOther()
    property string authSsid: ""        // the network of the password box ("" = none)
    readonly property bool authActive: authSsid !== ""
    onAuthActiveChanged: if (!authActive) syncOther()

    // The open password box's height: the list's view grows by it, so ten
    // rows stay visible next to it.
    readonly property real authExtra: {
        if (!authActive) return 0;
        for (let i = 0; i < otherRepeater.count; i++) {
            const it = otherRepeater.itemAt(i);
            if (it && it.ssid === authSsid) return Math.max(0, it.height - rowHeight);
        }
        return 0;
    }
    // Opening the box scrolls its row (with the box) into view.
    onAuthSsidChanged: if (authActive) Qt.callLater(() => {
        for (let i = 0; i < otherModel.count; i++)
            if (otherModel.get(i).ssid === authSsid) { otherSel = i; showOther(i); }
    })

    function syncOther() {
        if (authActive) return;
        const want = otherWanted.filter((s, i, a) => a.indexOf(s) === i);
        for (let i = 0; i < want.length; i++) {
            let j = i;
            while (j < otherModel.count && otherModel.get(j).ssid !== want[i]) j++;
            if (j === otherModel.count) otherModel.insert(i, { ssid: want[i] });
            else if (j !== i) otherModel.move(j, i, 1);
        }
        if (otherModel.count > want.length) otherModel.remove(want.length, otherModel.count - want.length);
        if (otherSel >= otherModel.count) otherSel = otherModel.count - 1;
    }

    ListModel {
        id: otherModel
    }

    // Keyboard selection in Other networks (-1 = none): Up/Down/Enter.
    property int otherSel: -1
    readonly property int rowHeight: Fonts.px(30)           // an Other network row (not connecting)
    readonly property int otherVisibleRows: 10

    readonly property var currentNetwork: networks.find(n => n.connected) || null

    property var passwordFor: null      // network waiting for a password
    property var pendingPsk: null       // network we just sent a password for
    property bool pendingWasKnown: false
    property string pwError: ""
    property string message: ""
    property string qrSvg: ""           // QR code (contains the password) - memory only
    property string qrPassword: ""      // the same password, for Copy only (never rendered) - memory only, "" = none
    property bool qrCopied: false
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
        if (n === null) return;
        if (n.connected) n.disconnect();
        else if (n.known || !secured(n)) n.connect();
        else if (personal(n)) { pwError = ""; passwordFor = n; authSsid = n.name; }
        else message = "enterprise";
    }

    function cancelPassword() {
        passwordFor = null;
        pendingPsk = null;
        pwError = "";
        authSsid = "";
    }

    function submitPassword(pw) {
        if (pw.length < 8) return false;
        // The network left the scan while the password was typed (the row
        // stays, frozen): keep the text, say why nothing happens.
        const n = byName[authSsid];
        if (n === undefined || n === null) { pwError = "Network out of range"; return false; }
        passwordFor = n;
        pendingPsk = n;
        pendingWasKnown = n.known;
        pwError = "";
        n.connectWithPsk(pw);
        return true;
    }

    // Bring Other row i (and its password box) into the list's view.
    function showOther(i) {
        const item = otherRepeater.itemAt(i);
        if (!item) return;
        if (item.y < otherView.contentY) otherView.contentY = item.y;
        else if (item.y + item.height > otherView.contentY + otherView.height)
            otherView.contentY = Math.min(item.y + item.height - otherView.height,
                                          Math.max(0, otherView.contentHeight - otherView.height));
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
        qrPassword = "";
        qrCopied = false;
    }

    // Copy only the password: wl-copy (core wl-clipboard) gets it on stdin,
    // never in argv; --sensitive sets the password-manager hint, so the
    // clipboard history (cliphist) does not store it.
    function copyQrPassword() {
        if (qrPassword === "" || copyProc.running) return;
        copyProc.stdinEnabled = true;
        copyProc.running = true;
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

    panelWidth: Fonts.px(340)
    keyFilter: event => {
        if (event.key === Qt.Key_Escape) {
            if (authActive && pendingPsk === null) cancelPassword();
            else if (qrRequested) hideQr();
            else return false;
            return true;
        }
        // Other networks: Up/Down select (the list scrolls along), Enter
        // acts like a click. Inactive while the password box has the keys.
        if (!wifiOn || otherModel.count === 0 || authActive) return false;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            otherSel = event.key === Qt.Key_Down ? Math.min(otherModel.count - 1, otherSel + 1)
                                                 : Math.max(0, otherSel - 1);
            showOther(otherSel);
            return true;
        }
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && otherSel >= 0) {
            activateNetwork(byName[otherModel.get(otherSel).ssid] || null);
            return true;
        }
        return false;
    }

    Component.onCompleted: {
        if (wifiDevice !== null && wifiOn) wifiDevice.scannerEnabled = true;
        refreshLists();
        sample();
        syncOther();
    }
    Component.onDestruction: {
        if (wifiDevice !== null) wifiDevice.scannerEnabled = false;
        qrSvg = "";
        qrPassword = "";
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
            if (popup.pendingPsk && popup.pendingPsk.connected) popup.cancelPassword();
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
                // Only links that are up: a down link can keep its address
                // (docker0 after `systemctl stop docker` - shown as a third
                // "connection", real use). Tunnels report UNKNOWN - kept.
                popup.addresses = list.filter(l => l.ifname !== "lo" && l.operstate !== "DOWN"
                                                   && (l.flags || []).indexOf("NO-CARRIER") === -1
                                                   && (l.addr_info || []).some(a => a.scope === "global"))
                    .map(l => {
                        const kindOf = popup.net.physical[l.ifname]
                            || (l.linkinfo && ["wireguard", "tun"].indexOf(l.linkinfo.info_kind) !== -1 ? "vpn"
                                : l.link_type === "ppp" ? "vpn"     // openfortivpn (Fortinet SSL-VPN)
                                : "other");
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
            onStreamFinished: {
                if (!popup.qrRequested) return;
                try {
                    const r = JSON.parse(text);
                    popup.qrPassword = typeof r.password === "string" ? r.password : "";
                    popup.qrSvg = r.svg;
                } catch (e) {
                    popup.hideQr();     // nothing faked: no QR, no empty password row
                    popup.message = "QR code unavailable";
                    Log.warn("network", "wifi-qr returned no valid output");
                }
            }
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
        id: copyProc
        command: ["wl-copy", "--sensitive"]
        onStarted: {
            write(popup.qrPassword);
            stdinEnabled = false;       // EOF: wl-copy takes what it got
        }
        onExited: exitCode => {
            if (exitCode === 0) popup.qrCopied = true;
            else Log.warn("network", "copying the Wi-Fi password failed (wl-copy exit " + exitCode + ")");
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
            Layout.preferredWidth: Fonts.px(18)
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

    // Password for a protected network (WPA/WPA2/WPA3-Personal), inline
    // below its row in Other networks (one per row, visible only for
    // authSsid). The row - and so this box and its TextInput - lives as long
    // as the password interaction: the list is frozen meanwhile (syncOther),
    // so text, cursor and focus survive every scan. The eye only switches
    // the echo mode of the same field. Nothing of the text is kept anywhere
    // else: hiding the box (cancel, sent, popup closed) empties it.
    component PasswordBox: Rectangle {
        id: box
        property bool reveal: false
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: pwBox.implicitHeight + 16
        radius: 6
        color: Colors.surface
        border.color: popup.pwError !== "" ? Colors.error : Colors.borderActive
        border.width: 1
        onVisibleChanged: reveal = false

        ColumnLayout {
            id: pwBox
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: popup.pendingPsk !== null ? "Connecting to " + popup.authSsid + "…"
                                                : "Password for " + popup.authSsid
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 1
            }

            Rectangle {
                visible: popup.pendingPsk === null
                Layout.fillWidth: true
                implicitHeight: Fonts.px(28)
                radius: 4
                color: Colors.background
                border.color: Colors.border
                border.width: 1

                TextInput {
                    id: pwInput
                    anchors.left: parent.left
                    anchors.right: eye.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 6
                    anchors.rightMargin: 4
                    clip: true
                    echoMode: box.reveal ? TextInput.Normal : TextInput.Password
                    selectByMouse: false
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize
                    maximumLength: 63
                    onVisibleChanged: {
                        text = "";
                        if (visible) forceActiveFocus();
                        else popup.restoreKeyFocus();
                    }
                    // Never into the clipboard (cliphist) - also not when shown.
                    Keys.onPressed: event => {
                        if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)) event.accepted = true;
                    }
                    Keys.onReturnPressed: if (popup.submitPassword(text)) text = ""
                    Keys.onEscapePressed: popup.cancelPassword()
                }

                // Show / hide the typed password (same field, same text).
                Text {
                    id: eye
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: box.reveal ? "\u{F0209}" : "\u{F0208}"      // eye-off / eye
                    color: eyeMouse.containsMouse || box.reveal ? Colors.accent : Colors.foregroundMuted
                    font.family: Fonts.icons
                    font.pixelSize: popup.fontSize

                    MouseArea {
                        id: eyeMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            box.reveal = !box.reveal;
                            pwInput.forceActiveFocus();
                        }
                    }
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
                    onClicked: popup.cancelPassword()
                }

                PopupButton {
                    primary: true
                    label: "Connect"
                    onClicked: if (popup.submitPassword(pwInput.text)) pwInput.text = ""
                }
            }
        }
    }

    // An Other network row plus its inline password box. Keyed by SSID:
    // the network object is looked up (it can vanish from the scan while
    // the list is frozen - the row then stays, marked out of range).
    component OtherEntry: ColumnLayout {
        id: entry
        required property string ssid
        required property int index
        readonly property var network: popup.byName[ssid] || null
        width: parent ? parent.width : 0
        spacing: 2

        NetworkRow {
            network: entry.network
            name: entry.ssid
            selected: popup.otherSel === entry.index
        }

        PasswordBox {
            visible: popup.authSsid === entry.ssid
        }
    }

    // A Wi-Fi network row. Right side: lock (secured) - for a known network
    // an X replaces it while hovered: forget, without triggering the row.
    component NetworkRow: Rectangle {
        id: row
        required property var network       // null: no longer in the scan (frozen Other list)
        property string name: network ? network.name : ""
        property bool selected: false
        readonly property bool present: network !== null
        readonly property bool connected: present && network.connected
        readonly property bool changing: present && network.stateChanging
        readonly property bool known: present && network.known
        readonly property bool hovered: rowMouse.containsMouse || forgetMouse.containsMouse

        Layout.fillWidth: true
        implicitHeight: connected || changing || !present ? popup.rowHeight + 10 : popup.rowHeight
        radius: 4
        color: connected || hovered || selected ? Colors.surface : "transparent"
        border.color: connected ? Colors.accent : "transparent"
        border.width: connected ? 1 : 0

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: popup.activateNetwork(row.network)
        }

        Connections {
            target: row.network
            ignoreUnknownSignals: true
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
            text: popup.signalIcon(row.present ? row.network.signalStrength : 0)
            color: row.connected ? Colors.accent : row.present ? Colors.foreground : Colors.foregroundMuted
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
                text: row.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.present ? Colors.foreground : Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: popup.fontSize - 1
            }

            Text {
                visible: row.connected || row.changing || !row.present
                text: !row.present ? "Out of range" : row.changing ? "Connecting…" : "Connected"
                color: row.connected ? Colors.accent : Colors.foregroundMuted
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
                visible: row.present && !(row.known && row.hovered) && popup.secured(row.network)
                text: "\u{F033E}"           // lock
                color: Colors.foregroundMuted
                font.family: Fonts.icons
                font.pixelSize: popup.fontSize - 1
            }

            Rectangle {
                anchors.fill: parent
                visible: row.known && row.hovered
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
                enabled: row.known
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
                text: "No VPN connections - add them with Connections\u2026 below"
            }

            Repeater {
                model: popup.vpns

                Rectangle {
                    id: vrow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: Fonts.px(modelData.active ? 40 : 30)
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

            // The shared network's password row, below its QR (open networks:
            // none). Never rendered: a fixed mask (same length for every
            // password, so not even the length shows) - the real password
            // only goes to Copy (wl-copy stdin, --sensitive) and the QR.
            SubTitle {
                visible: popup.qrRequested && popup.qrSvg !== "" && popup.qrPassword !== ""
                text: "Password"
            }

            RowLayout {
                visible: popup.qrRequested && popup.qrSvg !== "" && popup.qrPassword !== ""
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "\u2022".repeat(12)
                    textFormat: Text.PlainText
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: popup.fontSize
                }

                PopupButton {
                    label: popup.qrCopied ? "Copied" : "Copy"
                    onClicked: popup.copyQrPassword()
                }
            }

            SubTitle {
                visible: popup.wifiOn && otherModel.count > 0
                text: "Other networks"
            }

            // Its own scroll area: up to ten rows tall (plus an open password
            // box), the rest scrolls here - the heading above and every other
            // section stay put. A Repeater, not a ListView: rows (and the
            // password field in one) are never destroyed by scrolling.
            Item {
                visible: popup.wifiOn && otherModel.count > 0
                Layout.fillWidth: true
                implicitHeight: otherView.height

                Flickable {
                    id: otherView
                    readonly property real viewport: popup.otherVisibleRows * popup.rowHeight
                        + (popup.otherVisibleRows - 1) * otherColumn.spacing
                        + popup.authExtra
                    readonly property bool scrolls: contentHeight > height + 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.min(otherColumn.implicitHeight, viewport)
                    contentHeight: otherColumn.implicitHeight
                    clip: true
                    interactive: scrolls
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: otherColumn
                        width: otherView.width - (otherView.scrolls ? 10 : 0)
                        spacing: 3

                        Repeater {
                            id: otherRepeater
                            model: otherModel
                            delegate: OtherEntry {}
                        }
                    }
                }

                // Scrollbar - only when the list is longer than its view.
                Rectangle {
                    visible: otherView.scrolls
                    anchors.right: parent.right
                    y: otherView.visibleArea.yPosition * otherView.height
                    width: 4
                    height: Math.max(16, otherView.visibleArea.heightRatio * otherView.height)
                    radius: 2
                    color: barDrag.active || barMouse.containsMouse ? Colors.accent : Colors.foregroundMuted

                    MouseArea {
                        id: barMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                    }

                    DragHandler {
                        id: barDrag
                        target: null
                        property real startY: 0
                        onActiveChanged: if (active) startY = otherView.contentY
                        onTranslationChanged: otherView.contentY = Math.max(0, Math.min(
                            otherView.contentHeight - otherView.height,
                            startY + translation.y * otherView.contentHeight / otherView.height))
                    }
                }
            }

            SubTitle {
                visible: popup.wifiOn && popup.wifiDevice !== null && popup.networks.length === 0
                text: "Searching…"
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

            // The escape hatch for everything this popup deliberately does
            // not do (VPN import/edit, static IP/DNS, 802.1X, Ethernet).
            PopupButton {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: 4
                label: "Connections\u2026"
                onClicked: popup.openSettings()
            }
        }
    }
}
