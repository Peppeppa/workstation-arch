// Regression test for the pure logic inside the shipped Quickshell files
// (no Quickshell, no session, no D-Bus): each function is cut out of the
// real QML text and run against mock objects, so the test can never drift
// from the code it checks. Run by tests/run.sh:
//   QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen qml6 tests/qml-logic.qml
// Exit 0 = all checks passed, 1 = a check failed, 2 = a function was not found.

import QtQuick

QtObject {
    readonly property string files: Qt.resolvedUrl("../roles/quickshell/files/")
    property int failures: 0

    function read(path) {
        const x = new XMLHttpRequest();
        x.open("GET", files + path, false);
        x.send();
        return x.responseText;
    }

    // "function name(args) { ... }" by brace matching, evaluated with a mock
    // QML scope (the properties/functions the body refers to).
    function make(text, name, scope) {
        const i = text.indexOf("function " + name + "(");
        if (i < 0) {
            console.warn("FAIL function " + name + " not found");
            Qt.exit(2);
            throw new Error(name);
        }
        const open = text.indexOf("{", i);
        let depth = 0, k = open;
        for (; k < text.length; k++) {
            if (text[k] === "{") depth++;
            else if (text[k] === "}" && --depth === 0) break;
        }
        const args = text.slice(text.indexOf("(", i) + 1, text.indexOf(")", i));
        return new Function("scope", "with (scope) { return function(" + args + ") {" + text.slice(open + 1, k) + "} }")(scope);
    }

    function eq(what, got, want) {
        if (JSON.stringify(got) !== JSON.stringify(want)) {
            failures++;
            console.warn("FAIL " + what + ": " + JSON.stringify(got) + " != " + JSON.stringify(want));
        }
    }

    function hex(s) {
        return s.codePointAt(0).toString(16);
    }

    function bluetooth() {
        const bt = read("bluetooth/Popup.qml");
        // BlueZ Icon property -> glyph; anything unknown = the Bluetooth glyph.
        const glyph = make(bt, "deviceGlyph", {});
        const want = { "audio-headphones": "f02cb", "audio-headset": "f02ce", "audio-card": "f04c3",
                       "multimedia-player": "f04c3", "input-keyboard": "f030c", "input-mouse": "f037d",
                       "input-tablet": "f037d", "input-gaming": "f0297", "phone": "f011c", "modem": "f011c",
                       "computer": "f0322", "video-display": "f0379", "printer": "f042a", "scanner": "f042a",
                       "camera-photo": "f0100", "": "f00af", "something-new": "f00af" };
        for (const icon in want)
            eq("bluetooth glyph '" + icon + "'", hex(glyph({ icon: icon })), want[icon]);
        eq("bluetooth glyph without icon", hex(glyph({})), "f00af");

        const battery = make(bt, "batteryText", {});
        eq("bluetooth battery 0.55", battery({ batteryAvailable: true, battery: 0.55 }), "55%");
        eq("bluetooth battery 1", battery({ batteryAvailable: true, battery: 1 }), "100%");
        eq("bluetooth battery absent", battery({ batteryAvailable: false, battery: 0.5 }), "");

        // Row click: disconnect / connect / pair / cancel - never forget.
        const calls = [];
        const dev = o => Object.assign({ connect: () => calls.push("connect"), disconnect: () => calls.push("disconnect"),
                                         cancelPair: () => calls.push("cancelPair"), forget: () => calls.push("forget") }, o);
        const scope = { pairingDevice: null, startPair: () => calls.push("pair"), finishPairing: () => calls.push("finish") };
        const row = make(bt, "rowAction", scope);
        row(dev({ connected: true, paired: true }));
        row(dev({ connected: false, paired: true }));
        row(dev({ connected: false, paired: false }));
        const pairing = dev({ connected: false, paired: false });
        scope.pairingDevice = pairing;
        row(pairing);
        eq("bluetooth row actions", calls, ["disconnect", "connect", "pair", "cancelPair", "finish"]);

        // After pairing: trust, then exactly one connect - Quickshell's
        // connect() without a link, else one BlueZ Device1.Connect (busctl):
        // Quickshell refuses connect() while the pairing link is up.
        for (const [connected, want] of [[true, ["busctl Connect /org/bluez/hci0/dev_X"]], [false, ["connect"]]]) {
            const done = [];
            const d = { paired: true, connected: connected, trusted: false, dbusPath: "/org/bluez/hci0/dev_X",
                        connect: () => done.push("connect") };
            const proc = { set running(v) { if (v) done.push("busctl " + this.command[6] + " " + this.command[4]); }, command: [] };
            const scope = { postPairDevice: null, postPairConnect: proc };
            make(bt, "onPairedChanged", { popup: { pairingDevice: d, finishPairing: () => {},
                                                   connectAfterPairing: make(bt, "connectAfterPairing", scope) } })();
            eq("bluetooth after pairing (connected=" + connected + ")", [d.trusted, done], [true, want]);
        }
    }

    function battery() {
        // Low-battery notification: once at <= 15 % while discharging,
        // re-armed only by external power or >= 20 %.
        const notes = [];
        const st = { discharging: true, percent: 50, rearmPercent: 20, thresholdPercent: 15, warned: false,
                     Log: { warn: () => {} }, Quickshell: { execDetached: a => notes.push(a) } };
        const check = make(read("quickshell/BatteryWatcher.qml"), "check", st);
        for (const p of [30, 20, 16, 15, 14, 15, 16, 14, 19, 12, 10]) { st.percent = p; check(); }
        eq("low battery: one notification while draining with wobble", notes.length, 1);
        st.percent = 21; check(); st.percent = 15; check();
        eq("low battery: re-armed at >= 20 %", notes.length, 2);
        st.discharging = false; check(); st.discharging = true; st.percent = 14; check();
        eq("low battery: re-armed by external power", notes.length, 3);
        st.warned = false; st.discharging = true; st.percent = 9; check();
        eq("low battery: start already low (Component.onCompleted check)", notes.length, 4);

        // AC/battery policy: AC = Performance without touching the battery
        // choice; unplug restores it; equal profile = no set at all.
        const pp = read("quickshell/PowerPolicy.qml");
        const PP = { PowerSaver: 0, Balanced: 1, Performance: 2 };
        const sets = [];
        const ppd = { _p: 0, get profile() { return this._p; }, set profile(v) { sets.push(v); this._p = v; } };
        const pol = { ready: true, laptop: true, onAc: false, acProfile: PP.Performance, batteryProfile: PP.PowerSaver,
                      PowerProfiles: ppd, PowerProfile: PP, store: { setText: () => {} } };
        pol.wanted = make(pp, "wanted", pol);
        pol.nameOf = make(pp, "nameOf", pol);
        const apply = make(pp, "apply", pol), remember = make(pp, "remember", pol);
        apply();
        eq("power policy: battery profile already active -> no set", sets, []);
        pol.onAc = true; apply(); remember();
        eq("power policy: AC -> Performance", [ppd.profile, pol.batteryProfile], [PP.Performance, PP.PowerSaver]);
        apply();
        eq("power policy: duplicate AC event sets nothing", sets.length, 1);
        pol.onAc = false; apply(); remember();
        eq("power policy: unplug restores the battery choice", ppd.profile, PP.PowerSaver);
        ppd._p = PP.Balanced; remember();
        eq("power policy: a choice on battery is remembered", pol.batteryProfile, PP.Balanced);
        pol.laptop = false; pol.onAc = true; sets.length = 0; apply();
        eq("power policy: no laptop battery -> left alone", sets, []);

        const model = read("quickshell/bar/widgets/Power/Model.qml");
        const est = o => make(model, "estimateText", o)();
        eq("estimate without battery", est({ hasBattery: false }), "");
        eq("estimate discharging", est({ hasBattery: true, charging: false, discharging: true, device: { timeToEmpty: 13320 } }), "3h 42m remaining");
        eq("estimate charging", est({ hasBattery: true, charging: true, discharging: false, device: { timeToFull: 4080 } }), "1h 08m until full");
        eq("estimate minutes only", est({ hasBattery: true, charging: false, discharging: true, device: { timeToEmpty: 600 } }), "10m remaining");
        eq("estimate 0 = none", est({ hasBattery: true, charging: false, discharging: true, device: { timeToEmpty: 0 } }), "");
        eq("estimate NaN = none", est({ hasBattery: true, charging: true, discharging: false, device: { timeToFull: NaN } }), "");
        eq("estimate fully charged = none", est({ hasBattery: true, charging: false, discharging: false, device: {} }), "");
    }

    function network() {
        // Network popup, Other networks: a ListModel keyed by SSID, synced by
        // moves/inserts/removes (rows keep their identity), frozen while the
        // password box is open - the box's TextInput is never recreated.
        const pop = read("connectivity/Popup.qml");
        const rows = [];
        const created = [];
        const lm = {
            get count() { return rows.length; },
            get: i => rows[i],
            insert: (i, o) => { const r = { ssid: o.ssid, uid: created.length }; created.push(r); rows.splice(i, 0, r); },
            move: (from, to, n) => rows.splice(to, 0, ...rows.splice(from, n)),
            remove: (i, n) => rows.splice(i, n)
        };
        const st = { authActive: false, otherWanted: ["A", "B", "C"], otherModel: lm, otherSel: -1 };
        const sync = make(pop, "syncOther", st);
        sync();
        eq("network: Other in signal order", rows.map(r => r.ssid), ["A", "B", "C"]);
        const uidB = rows[1].uid;
        st.otherWanted = ["C", "B", "A", "D"]; sync();
        eq("network: re-sorted + new one", rows.map(r => r.ssid), ["C", "B", "A", "D"]);
        eq("network: a re-sorted row is the same row (not recreated)", rows[1].uid, uidB);
        st.authActive = true;
        st.otherWanted = ["D", "A"]; sync();
        eq("network: frozen while the password box is open", rows.map(r => r.ssid), ["C", "B", "A", "D"]);
        eq("network: the box's row survives scans", rows[1].uid, uidB);
        st.authActive = false; sync();
        eq("network: applied once the box closed", rows.map(r => r.ssid), ["D", "A"]);
        eq("network: rows created only for new SSIDs", created.length, 4);

        // Submit: a network gone from the scan keeps the box and the text.
        const sub = { authSsid: "X", byName: {}, pwError: "", passwordFor: null, pendingPsk: null, pendingWasKnown: false };
        const submit = make(pop, "submitPassword", sub);
        eq("network: short password not sent", submit("1234567"), false);
        eq("network: out of range keeps the text", [submit("12345678"), sub.pwError], [false, "Network out of range"]);
        let sent = 0;
        sub.byName = { X: { known: false, connectWithPsk: () => sent++ } };
        eq("network: sent once", [submit("12345678"), sent, sub.pendingPsk === sub.byName.X], [true, 1, true]);
        const cancel = { passwordFor: 1, pendingPsk: 1, pwError: "x", authSsid: "X" };
        make(pop, "cancelPassword", cancel)();
        eq("network: cancel clears the interaction", [cancel.passwordFor, cancel.pendingPsk, cancel.pwError, cancel.authSsid], [null, null, "", ""]);

        // Closing the Share view drops the password (and the QR) from memory.
        const qr = { qrRequested: true, qrSvg: "<svg/>", qrPassword: "secret", qrCopied: true };
        make(pop, "hideQr", qr)();
        eq("network: hideQr clears the shared password", [qr.qrRequested, qr.qrSvg, qr.qrPassword, qr.qrCopied], [false, "", "", false]);

        // Saved profiles Quickshell 0.3.1 does not attach (no explicit
        // 802-11-wireless.mode - eduroam CAT): rows from nmcli, by UUID.
        const parseProfiles = make(pop, "parseProfiles", {});
        const listing = "connection.id:eduroam\nconnection.uuid:u-edu\n802-11-wireless.ssid:eduroam\n802-11-wireless.mode:\n"
            + "802-11-wireless-security.key-mgmt:wpa-eap\nGENERAL.STATE:activated\nGENERAL.DEVICES:wlp3s0\n\n"
            + "connection.id:THWS\nconnection.uuid:u-thws\n802-11-wireless.ssid:THWS\n802-11-wireless.mode:\n"
            + "802-11-wireless-security.key-mgmt:wpa-eap\n\n"
            + "connection.id:Home\nconnection.uuid:u-home\n802-11-wireless.ssid:a:b\n802-11-wireless.mode:infrastructure\n"
            + "802-11-wireless-security.key-mgmt:wpa-psk\n\n"
            + "connection.id:Hotspot\nconnection.uuid:u-ap\n802-11-wireless.ssid:hs\n802-11-wireless.mode:ap\n"
            + "802-11-wireless-security.key-mgmt:wpa-psk\n";
        const profiles = parseProfiles(listing);
        eq("network: profiles parsed (hotspot skipped, ':' in an SSID kept)", profiles.map(p => [p.name, p.uuid, p.ssid, p.keyMgmt, p.state, p.device]),
           [["eduroam", "u-edu", "eduroam", "wpa-eap", "activated", "wlp3s0"], ["THWS", "u-thws", "THWS", "wpa-eap", "", ""],
            ["Home", "u-home", "a:b", "wpa-psk", "", ""]]);
        const ps = {};
        ps.profileOnly = make(pop, "profileOnly", ps);
        const known = make(pop, "knownEntries", ps);
        const nets = [{ name: "eduroam", known: false, connected: false, signalStrength: 0.6 },
                      { name: "a:b", known: true, connected: false, signalStrength: 0.9 },
                      { name: "Cafe", known: false, connected: false, signalStrength: 0.8 }];
        const k = known(nets, profiles, "");
        eq("network: Known = Quickshell-known + profile-only, active profile first, THWS out of range",
           k.map(e => [e.profile ? e.profile.name : e.network.name, e.network !== null]),
           [["eduroam", true], ["a:b", true], ["THWS", false]]);
        eq("network: the eduroam row is connected via its profile", k[0].profile.state, "activated");

        // A click on an SSID that has a saved profile activates that
        // profile - never "enterprise", never a new profile.
        const act = { message: "x", wifiProfiles: profiles, toggled: [], profileOnly: ps.profileOnly,
                      secured: () => true, personal: () => false };
        act.toggleProfile = p => act.toggled.push(p.uuid);
        const activate = make(pop, "activateNetwork", act);
        let added = 0;
        const eduNet = { name: "eduroam", known: false, connected: false, connect: () => added++ };
        activate(eduNet);
        eq("network: profile SSID -> its profile, no enterprise note", [act.toggled, act.message, added], [["u-edu"], "", 0]);
        activate({ name: "OtherCorp", known: false, connected: false, connect: () => added++ });
        eq("network: an unconfigured enterprise network -> note", [act.message, added], ["enterprise", 0]);

        const tg = { wifiBusy: "", message: "x", wifiDevice: { name: "wlp3s0" }, wifiAction: { command: [], running: false } };
        const toggle = make(pop, "toggleProfile", tg);
        toggle(profiles[1]);
        eq("network: up by UUID on the Wi-Fi device", [tg.wifiAction.command, tg.wifiAction.running, tg.wifiBusy],
           [["nmcli", "connection", "up", "uuid", "u-thws", "ifname", "wlp3s0"], true, "u-thws"]);
        tg.wifiAction.command = [];
        toggle(profiles[0]);
        eq("network: busy -> no second action", tg.wifiAction.command, []);
        tg.wifiBusy = "";
        toggle(profiles[0]);
        eq("network: active profile -> down by UUID", tg.wifiAction.command, ["nmcli", "connection", "down", "uuid", "u-edu"]);

        const m = read("quickshell/bar/widgets/Connectivity/Model.qml");
        const v4 = make(m, "v4", {}), v6 = make(m, "v6", {});
        eq("route v4", v4("0202000A"), "10.0.2.2");
        eq("route v6 compressed", v6("fe800000000000000000000000000002"), "fe80::2");
        eq("route v6 full", v6("20010db8000100020003000400050006"), "2001:db8:1:2:3:4:5:6");
        eq("route v6 zero run in the middle", v6("20010db8000000000000000000000001"), "2001:db8::1");
    }

    function hover() {
        // Keyboard-first menus open under a resting pointer: its first hover
        // report is only an anchor; only real movement changes the selection
        // (Enter on the power menu otherwise hit the row under the pointer).
        const area = { mapToItem: (_, x, y) => ({ x: x, y: y }) };
        for (const [file, prop] of [["PowerMenu.qml", "selectedIndex"], ["quickshell/osmenu/RootPage.qml", "index"],
                                    ["clipboard/ClipboardHistory.qml", "selectedIndex"]]) {
            const st = { pointerAtOpen: { x: -1, y: -1 } };
            st[prop] = 0;
            const hoverRow = make(read(file), "hoverRow", st);
            hoverRow(area, { x: 10, y: 50 }, 2);
            eq(file + ": resting pointer keeps the preselection", st[prop], 0);
            hoverRow(area, { x: 10, y: 50 }, 2);
            eq(file + ": same position again keeps it", st[prop], 0);
            hoverRow(area, { x: 10, y: 53 }, 2);
            eq(file + ": movement selects the row", st[prop], 2);
        }
    }

    function launcher() {
        // Empty search = every shown app, alphabetical, not cut to the page
        // height; a search keeps the at-most-maxResults behaviour.
        const names = ["Thunderbird", "Chromium", "Ghostty", "Files", "Bitwarden", "Obsidian", "Steam",
                       "Lutris", "IntelliJ IDEA Ultimate", "Zathura", "mpv", "Neovim", "Yazi", "imv"];
        const apps = names.map(n => ({ name: n, genericName: "", keywords: [] }));
        const scope = { DesktopEntries: { applications: { values: apps } }, maxResults: 8,
                        model: { shown: () => true } };
        const am = read("quickshell/osmenu/AppModel.qml");
        scope.matchScore = make(am, "matchScore", {});
        scope.scored = make(am, "scored", scope);
        const search = make(am, "search", scope);
        const all = search("");
        eq("launcher: empty search lists all apps", all.length, names.length);
        eq("launcher: empty search is alphabetical", all.map(e => e.name),
           names.slice().sort((a, b) => a.localeCompare(b)));
        eq("launcher: Thunderbird without typing", all.some(e => e.name === "Thunderbird"), true);
        eq("launcher: a search still returns at most maxResults", search("i").length <= 8, true);
        eq("launcher: a search finds by name", search("thun").map(e => e.name), ["Thunderbird"]);

        // Type-to-search ranking (the OS menu's own entries use the same):
        // prefix 0 < contains 1 < generic 2 < keywords 3, none -1.
        const ms = scope.matchScore;
        eq("search: name prefix", ms("chrom", "Chromium", "", ""), 0);
        eq("search: name contains", ms("pear", "Appearance", "", ""), 1);
        eq("search: generic name", ms("browser", "Chromium", "Web Browser", ""), 2);
        eq("search: keywords", ms("wifi", "Network", "", "wifi vpn"), 3);
        eq("search: no match", ms("xyz", "Network", "", "wifi"), -1);

        // A key on a menu list: printable = search text (j/k included),
        // Ctrl+J/Ctrl+K, Backspace, a leading blank are not.
        const isText = make(read("quickshell/osmenu/RootPage.qml"), "isSearchText",
                            { Qt: { ControlModifier: 0x04000000, AltModifier: 0x08000000, MetaModifier: 0x10000000 } });
        eq("search: j is text", isText({ text: "j", modifiers: 0 }), true);
        eq("search: k is text", isText({ text: "k", modifiers: 0 }), true);
        eq("search: Ctrl+J is not text", isText({ text: "\n", modifiers: 0x04000000 }), false);
        eq("search: Backspace is not text", isText({ text: "\b", modifiers: 0 }), false);
        eq("search: a leading blank is not text", isText({ text: " ", modifiers: 0 }), false);
        eq("search: umlaut is text", isText({ text: "ä", modifiers: 0 }), true);
    }

    function barLayout() {
        // coffee + theme became one "visuals" widget: a stored layout gets it
        // at the place of the first of them, nothing duplicated, the rest kept.
        const bl = read("quickshell/bar/BarLayout.qml");
        const ids = ["workspaces", "clock", "tray", "connectivity", "bluetooth", "audio", "power", "visuals"];
        const scope = { widgets: ids.map(i => ({ id: i })), renamed: { coffee: "visuals", theme: "visuals" },
                        zoneNames: ["left", "center", "right"], backgrounds: ["solid", "transparent"] };
        scope.known = make(bl, "known", scope);
        scope.cleanEntry = make(bl, "cleanEntry", scope);
        scope.emptyLayout = make(bl, "emptyLayout", scope);
        const sanitize = make(bl, "sanitize", scope);
        const laptop = { version: 1, layout: { left: [{ id: "workspaces" }], center: [{ id: "theme" }, { id: "coffee" }, { id: "clock" }],
                                               right: [{ id: "audio" }, { id: "bluetooth" }, { id: "tray" }, { id: "connectivity" }, { id: "power" }] },
                         settings: { background: "transparent" } };
        const out = sanitize(laptop);
        eq("bar layout: coffee+theme -> one visuals at the first place", out.layout.center.map(e => e.id), ["visuals", "clock"]);
        eq("bar layout: other zones untouched", out.layout.right.map(e => e.id), ["audio", "bluetooth", "tray", "connectivity", "power"]);
        eq("bar layout: settings kept", out.settings.background, "transparent");
        const split = sanitize({ layout: { left: [{ id: "coffee" }], center: [], right: [{ id: "theme" }] } });
        eq("bar layout: split coffee/theme -> visuals where the first was", [split.layout.left.map(e => e.id), split.layout.right.map(e => e.id)], [["visuals"], []]);
    }

    function countdown() {
        // MM:SS input, minutes may exceed 59; remaining always from the deadline.
        const cd = read("quickshell/Countdown.qml");
        const parse = make(cd, "parse", {}), format = make(cd, "format", {});
        eq("timer parse digits", ["5", "33", "230", "0230", "1200", "9000", "75", "13000", "123456"].map(parse),
           [5, 33, 150, 150, 720, 5400, 75, 5400, 45296]);
        eq("timer parse colons", ["05:00", "25:00", "90:00", "00:30", "5:07", " 01:00 ", "2:30", "12:00", "3:30:00", "0:00:30"].map(parse),
           [300, 1500, 5400, 30, 307, 60, 150, 720, 12600, 30]);
        eq("timer parse rejects", ["", "0", "0000", "00:00", "05:60", "abc", "1:2", "-1:00", "1000:00", "1:60:00", "1234567", "999999", "2 30"].map(parse),
           [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]);
        eq("timer format", [300, 3599, 3600, 5400, 12600, 30, 59, 0].map(format), ["05:00", "59:59", "1:00:00", "1:30:00", "3:30:00", "00:30", "00:59", "00:00"]);
    }

    function nightLight() {
        // Day/Night fade: a click during the fade does nothing; overlapping
        // IPC steps are replaced by the newest temperature, never queued.
        const nl = read("quickshell/NightLight.qml");
        const st = { busy: false, active: false, step: 0, from: 0, to: 0, neutral: 6500, temperature: 4500, pending: -1,
                     proc: { running: false }, fade: { started: 0, start() { this.started++; } },
                     ipc: { running: false, command: [] } };
        const toggle = make(nl, "toggle", st), set = make(nl, "setTemperature", st);
        toggle();
        eq("night: first click starts Night + fade", [st.active, st.busy, st.proc.running, st.from, st.to], [true, true, true, 6500, 4500]);
        toggle(); toggle();
        eq("night: clicks during the fade change nothing", [st.active, st.busy, st.fade.started], [true, true, 0]);
        set(6000);
        eq("night: a step runs the IPC call", st.ipc.command, ["hyprctl", "hyprsunset", "temperature", "6000"]);
        set(5800); set(5600);
        eq("night: overlapping steps keep only the newest", st.pending, 5600);
        st.busy = false;
        toggle();
        eq("night: after the fade a click fades back to Day", [st.active, st.busy, st.from, st.to, st.fade.started], [false, true, 4500, 6500, 1]);
    }

    // Firewall dialog checks (services/FirewallModel.qml) - feedback only,
    // the root helper decides (tests/firewall.sh), but both must agree.
    function firewall() {
        const fw = read("quickshell/services/FirewallModel.qml");
        const label = make(fw, "labelError", {}), port = make(fw, "portError", {}),
              proto = make(fw, "normalizeProtocol", {});
        for (const p of ["tcp", "TCP", "Tcp"]) eq("firewall protocol " + p, proto(p), "TCP");
        for (const p of ["udp", "UDP", "uDp"]) eq("firewall protocol " + p, proto(p), "UDP");
        for (const p of ["", "sctp", "tcp;", "t cp", "icmp"]) eq("firewall protocol '" + p + "' refused", proto(p), "");
        for (const p of ["1", "1234", "65535"]) eq("firewall port " + p, port(p), "");
        for (const p of ["0", "65536", "99999", "12ab", "", " 80", "080", "-1", "1.5", "1e3"])
            eq("firewall port '" + p + "' refused", port(p) !== "", true);
        eq("firewall label ok", label("Test Database"), "");
        eq("firewall label empty", label("") !== "", true);
        eq("firewall label blank", label("   ") !== "", true);
        eq("firewall label 48", label("x".repeat(48)), "");
        eq("firewall label 49", label("x".repeat(49)) !== "", true);
        eq("firewall label control char", label("a\tb") !== "", true);
        eq("firewall label shell text is just text", label("$(rm -rf /); `id`"), "");
    }

    // Network popup: ping summary -> latency + loss; bits formatting.
    function networkMetrics() {
        const pop = read("connectivity/Popup.qml");
        const sc = { pingMs: 0, lossPct: 0 };
        const parse = make(pop, "parsePing", sc);
        parse("--- 1.1.1.1 ping statistics ---\n5 packets transmitted, 5 received, 0% packet loss, time 815ms\nrtt min/avg/max/mdev = 11.204/13.587/17.911/2.390 ms\n");
        eq("ping: avg rtt", sc.pingMs, 13.587); eq("ping: no loss", sc.lossPct, 0);
        parse("5 packets transmitted, 3 received, 40% packet loss, time 4005ms\nrtt min/avg/max/mdev = 20.1/25.5/30.2/4.0 ms\n");
        eq("ping: 2 of 5 lost -> 40 %", sc.lossPct, 40);
        parse("5 packets transmitted, 0 received, 100% packet loss, time 4004ms\n");
        eq("ping: all lost -> 100 %, no latency", [sc.lossPct, sc.pingMs], [100, -1]);
        parse("ping: connect: Network is unreachable\n");
        eq("ping: unreachable -> unknown", [sc.lossPct, sc.pingMs], [-1, -1]);
        const bits = make(pop, "bits", {});
        eq("bits: 42300000", bits(42300000), "42 Mbit/s");
        eq("bits: 8100000", bits(8100000), "8.1 Mbit/s");
        eq("bits: 900", bits(900), "900 bit/s");
        const sp = { speedResult: null, speedState: "running", Qt: Qt };
        const parseSpeed = make(pop, "parseSpeed", sp);
        parseSpeed('{"download": 358000000, "upload": 18000000, "ping": 22.4}');
        eq("speedtest: result parsed", [sp.speedState, sp.speedResult.down, sp.speedResult.ping], ["done", 358000000, 22.4]);
        sp.speedState = "running"; parseSpeed("Cannot retrieve speedtest configuration");
        eq("speedtest: garbage -> failed (retry possible)", sp.speedState, "failed");
        sp.speedState = "running"; parseSpeed('{"download": 0, "upload": 0, "ping": 0}');
        eq("speedtest: no measurement -> failed", sp.speedState, "failed");
        const mbit = make(pop, "mbit", {});
        eq("mbit: 406e6", mbit(406123456), "406"); eq("mbit: 8.1e6", mbit(8100000), "8.1");
    }

    Component.onCompleted: {
        firewall();
        networkMetrics();
        nightLight();
        barLayout();
        countdown();
        launcher();
        hover();
        bluetooth();
        battery();
        network();
        console.info(failures === 0 ? "qml-logic: all checks passed" : "qml-logic: " + failures + " check(s) FAILED");
        Qt.exit(failures === 0 ? 0 : 1);
    }
}
