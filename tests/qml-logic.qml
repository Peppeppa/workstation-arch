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

        // After pairing: trust, and connect only if the pairing did not
        // already connect (a second connect() logs an ERROR).
        for (const [connected, want] of [[true, []], [false, ["connect"]]]) {
            const done = [];
            const d = { paired: true, connected: connected, trusted: false, connect: () => done.push("connect") };
            make(bt, "onPairedChanged", { popup: { pairingDevice: d, finishPairing: () => {} } })();
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
        // Network popup: the network being authenticated stays under "Other"
        // (in place) until the connect succeeded; "Other" keeps its order
        // while the inline password box is open.
        const pop = read("connectivity/Popup.qml");
        const a = { name: "A", signalStrength: 0.9 }, b = { name: "B", signalStrength: 0.5 }, c = { name: "C", signalStrength: 0.2 };
        const scope = { authNetwork: b, pendingWasKnown: false };
        const hold = make(pop, "holdInOther", scope);
        eq("network: auth network held in Other", [hold(b), hold(a)], [true, false]);
        scope.pendingWasKnown = true;
        eq("network: an already known network is not held", hold(b), false);
        const order = make(pop, "orderOther", {});
        eq("network: Other by signal", order([c, a, b], []).map(n => n.name), ["A", "B", "C"]);
        b.signalStrength = 0.95; const d = { name: "D", signalStrength: 1 };
        eq("network: Other frozen while the box is open, new ones at the end",
           order([c, a, b, d], ["A", "B", "C"]).map(n => n.name), ["A", "B", "C", "D"]);

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

    Component.onCompleted: {
        launcher();
        hover();
        bluetooth();
        battery();
        network();
        console.info(failures === 0 ? "qml-logic: all checks passed" : "qml-logic: " + failures + " check(s) FAILED");
        Qt.exit(failures === 0 ? 0 : 1);
    }
}
