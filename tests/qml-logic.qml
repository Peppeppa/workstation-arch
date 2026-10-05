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
        const search = make(read("quickshell/osmenu/AppModel.qml"), "search", scope);
        const all = search("");
        eq("launcher: empty search lists all apps", all.length, names.length);
        eq("launcher: empty search is alphabetical", all.map(e => e.name),
           names.slice().sort((a, b) => a.localeCompare(b)));
        eq("launcher: Thunderbird without typing", all.some(e => e.name === "Thunderbird"), true);
        eq("launcher: a search still returns at most maxResults", search("i").length <= 8, true);
        eq("launcher: a search finds by name", search("thun").map(e => e.name), ["Thunderbird"]);
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
        eq("timer parse", ["05:00", "25:00", "90:00", "00:30", "5:07", " 01:00 "].map(parse), [300, 1500, 5400, 30, 307, 60]);
        eq("timer parse rejects", ["00:00", "5", "05:60", "abc", "1:2", "-1:00", "1000:00"].map(parse), [-1, -1, -1, -1, -1, -1, -1]);
        eq("timer format", [300, 5400, 30, 59, 0].map(format), ["05:00", "90:00", "00:30", "00:59", "00:00"]);
    }

    Component.onCompleted: {
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
