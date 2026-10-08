// Bar widget "connectivity" - the network state it shows (core). Managed
// by Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// The icon follows the interface that carries the ACTIVE DEFAULT ROUTE -
// not "Wi-Fi if connected": the kernel's routing table (/proc/net/route,
// /proc/net/ipv6_route): the IPv4 default route with the lowest metric
// (IPv6's only on IPv6-only networks), among the physical devices
// NetworkManager manages (Quickshell.Networking: interface name + type).
// A VPN tunnel holding the default route keeps the physical uplink as the
// icon and sets vpnDefault. Re-read on NetworkManager events only (device
// state/connection changes, connectivity) plus one delayed re-read for
// routes that settle a moment later - no poller, no process.
//
// VPNs: Quickshell's Networking module knows only Wi-Fi/Ethernet devices,
// so an active VPN (split tunnel: no default route of its own) comes from
// /run/workstation/vpn-state, kept by roles/network's NetworkManager
// dispatcher hook on every (vpn-)up/down and watched here (inotify).
//
// One exception to "no process": a Wi-Fi connection Quickshell cannot
// attach to its network (eduroam CAT profiles - see nmWifiNeeded) has its
// signal read once per NM event with `nmcli`.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Scope {
    id: model

    // Everything that changes when NetworkManager (de)activates something.
    readonly property string nmState: Networking.devices.values.map(d => d.name + ":" + d.state + ":" + d.connected + ":"
        + (d.type === DeviceType.Wifi && d.networks ? d.networks.values.filter(n => n.connected).map(n => n.name).join("|") : ""))
        .join(",") + "/" + Networking.connectivity

    // Physical NM devices by interface name -> "wifi" | "wired".
    readonly property var physical: {
        const m = {};
        for (const d of Networking.devices.values) {
            if (d.type === DeviceType.Wifi) m[d.name] = "wifi";
            else if (d.type === DeviceType.Wired) m[d.name] = "wired";
        }
        return m;
    }

    property var defaults: []            // [{iface, gateway, metric, family}]: IPv4 by metric, then IPv6 by metric
    // IPv4's default route decides (the path, gateway and traffic people
    // mean); IPv6's only on an IPv6-only network.
    readonly property var primary: defaults.find(r => r.family === 4 && physical[r.iface] !== undefined)
                                   || defaults.find(r => physical[r.iface] !== undefined) || null
    readonly property string primaryIface: primary ? primary.iface : ""
    readonly property string kind: primary ? physical[primary.iface] : "none"
    readonly property bool vpnDefault: defaults.length > 0 && physical[defaults[0].iface] === undefined
    // "TYPE:DEVICE:NAME" lines of the active VPN/WireGuard connections ("" = none)
    property string vpnState: ""
    readonly property bool vpnActive: vpnState !== "" || vpnDefault
    readonly property string gateway: primary ? primary.gateway : ""

    readonly property var wifiDevice: kind === "wifi" ? Networking.devices.values.find(d => d.name === primaryIface) || null : null
    readonly property var wifiNetwork: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values.find(n => n.connected) || null : null
    readonly property real signal: {
        const s = wifiNetwork ? wifiNetwork.signalStrength : nmSignal >= 0 ? nmSignal : undefined;  // object may be going away
        return typeof s === "number" ? (s > 1 ? s / 100 : s) : 0;
    }

    // Wi-Fi up but no connected network in Quickshell: a saved profile
    // without an explicit 802-11-wireless.mode (eduroam CAT profiles) is
    // never attached to its network in Quickshell 0.3.1 (see the network
    // popup's wifiProfiles). Then NM's own active access point gives the
    // signal: one `nmcli` read per NM event, only in that case - a value as
    // of the last event, not followed live like Quickshell's.
    readonly property bool nmWifiNeeded: kind === "wifi" && wifiNetwork === null
    property real nmSignal: -1
    onNmWifiNeededChanged: readNmWifi()

    function readNmWifi() {
        if (!nmWifiNeeded) { nmSignal = -1; return; }
        if (nmWifi.running) return;
        nmWifi.command = ["nmcli", "-t", "-f", "ACTIVE,SIGNAL", "device", "wifi", "list", "ifname", primaryIface, "--rescan", "no"];
        nmWifi.running = true;
    }

    Process {
        id: nmWifi
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.split("\n").find(l => l.startsWith("yes:"));
                model.nmSignal = a ? parseInt(a.slice(4)) : -1;
            }
        }
    }

    function signalIcon(s) {
        const v = s > 1 ? s / 100 : s;
        return v > 0.75 ? "\u{F0928}" : v > 0.5 ? "\u{F0925}" : v > 0.25 ? "\u{F0922}" : "\u{F091F}";
    }

    function typeIcon(t) {
        return t === "wifi" ? "\u{F0928}" : t === "wired" ? "\u{F0200}" : t === "vpn" ? "\u{F0582}" : "\u{F06F3}";
    }

    readonly property string icon: kind === "wired" ? "\u{F0200}"            // ethernet
        : kind === "wifi" ? signalIcon(signal)
        : "\u{F0318}"                                                         // lan-disconnect

    // /proc/net/route: IPv4 in little-endian hex.
    function v4(hex) {
        const b = [];
        for (let i = 6; i >= 0; i -= 2) b.push(parseInt(hex.substr(i, 2), 16));
        return b.join(".");
    }

    // /proc/net/ipv6_route: 32 hex digits -> compressed IPv6 (longest run
    // of two or more zero groups becomes "::").
    function v6(hex) {
        const g = [];
        for (let i = 0; i < 32; i += 4) g.push(parseInt(hex.substr(i, 4), 16).toString(16));
        let best = -1, bestLen = 1;
        for (let i = 0; i < 8; ) {
            if (g[i] !== "0") { i++; continue; }
            let j = i;
            while (j < 8 && g[j] === "0") j++;
            if (j - i > bestLen) { best = i; bestLen = j - i; }
            i = j;
        }
        if (best < 0) return g.join(":");
        return g.slice(0, best).join(":") + "::" + g.slice(best + bestLen).join(":");
    }

    // Quickshell 0.3.1: text() right after reload() still returns the
    // PREVIOUS content (measured), so the routes are parsed when the new
    // content has arrived (onLoaded). Read synchronously, the bar was always
    // one read behind: re-plugging Ethernet while Wi-Fi was up left the Wi-Fi
    // icon, because the settle re-read still saw NM's temporary metric
    // (20100, connectivity check pending, lifted ~0.1-0.2 s later).
    function update() {
        route4.reload();
        route6.reload();
    }

    function parse() {
        const out = [];
        for (const line of route4.text().split("\n").slice(1)) {
            const f = line.trim().split(/\s+/);
            if (f.length < 8 || f[1] !== "00000000" || f[7] !== "00000000" || !(parseInt(f[3], 16) & 1)) continue;
            out.push({ iface: f[0], gateway: f[2] !== "00000000" ? v4(f[2]) : "", metric: parseInt(f[6]), family: 4 });
        }
        for (const line of route6.text().split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f.length < 10 || f[9] === "lo" || !/^0{32}$/.test(f[0]) || f[1] !== "00" || !(parseInt(f[8], 16) & 1)) continue;
            out.push({ iface: f[9], gateway: /^0{32}$/.test(f[4]) ? "" : v6(f[4]), metric: parseInt(f[5], 16), family: 6 });
        }
        out.sort((a, b) => (a.family - b.family) || (a.metric - b.metric));
        defaults = out;
    }

    // Deferred: device objects can emit while a binding reads them.
    onNmStateChanged: {
        Qt.callLater(update);
        Qt.callLater(readNmWifi);
        settle.restart();
    }
    Component.onCompleted: update()

    // One-shot: routes can follow a device state change a moment later.
    Timer {
        id: settle
        interval: 1500
        onTriggered: model.update()
    }

    // Quickshell 0.3.1: parse in onLoaded (text() right after reload() is stale).
    FileView {
        id: vpnFile
        path: "/run/workstation/vpn-state"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            model.vpnState = text().trim();
            Qt.callLater(model.update);       // a tunnel's routes changed too
        }
    }

    FileView {
        id: route4
        path: "/proc/net/route"
        blockLoading: true
        onLoaded: model.parse()
    }

    FileView {
        id: route6
        path: "/proc/net/ipv6_route"
        blockLoading: true
        onLoaded: model.parse()
    }
}
