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
        const m = read("quickshell/bar/widgets/Connectivity/Model.qml");
        const v4 = make(m, "v4", {}), v6 = make(m, "v6", {});
        eq("route v4", v4("0202000A"), "10.0.2.2");
        eq("route v6 compressed", v6("fe800000000000000000000000000002"), "fe80::2");
        eq("route v6 full", v6("20010db8000100020003000400050006"), "2001:db8:1:2:3:4:5:6");
        eq("route v6 zero run in the middle", v6("20010db8000000000000000000000001"), "2001:db8::1");
    }

    Component.onCompleted: {
        bluetooth();
        battery();
        network();
        console.info(failures === 0 ? "qml-logic: all checks passed" : "qml-logic: " + failures + " check(s) FAILED");
        Qt.exit(failures === 0 ? 0 : 1);
    }
}
