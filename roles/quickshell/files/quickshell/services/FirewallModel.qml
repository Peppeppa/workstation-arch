// Firewall sharing rules model (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// The QML side of the ONE implementation, the root helper
// /usr/local/libexec/workstation/firewall-rules (roles/firewall), run as
// `pkexec <helper> <verb> <args...>` - argv, never a shell string; polkit
// lets the active local session run exactly that helper without a
// password. The helper validates everything itself; the checks here only
// give feedback before a click.
//
// `list` reports each rule's desired state AND whether it is live in the
// kernel; the rows show the live state. Every change ends in a fresh
// `list` - that is the refresh event. Created only while the Firewall
// window is open: no watcher, no timer.

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Scope {
    id: model

    readonly property string helper: "/usr/local/libexec/workstation/firewall-rules"

    // [{label, port, protocol, enabled, active}]
    property var rules: []
    property bool loaded: true          // false: the table is not loaded
    property bool listed: false         // a first `list` came back
    property string errorText: ""
    readonly property bool busy: actionProc.running

    // ---- pure input checks (mirrors of the helper's; it decides) ----------
    function labelError(text) {
        const t = text.trim();
        if (t === "") return "Bezeichnung fehlt.";
        if (t.length > 48) return "Bezeichnung zu lang (höchstens 48 Zeichen).";
        if (/[\u0000-\u001f\u007f-\u009f]/.test(t)) return "Bezeichnung enthält Steuerzeichen.";
        return "";
    }

    function portError(text) {
        if (!/^[1-9][0-9]{0,4}$/.test(text) || parseInt(text, 10) > 65535)
            return "Port: eine Zahl von 1 bis 65535.";
        return "";
    }

    function normalizeProtocol(text) {
        const p = text.trim().toUpperCase();
        return p === "TCP" || p === "UDP" ? p : "";
    }

    // ---- helper calls -----------------------------------------------------
    property bool refreshPending: false

    function refresh() {
        if (listProc.running) refreshPending = true;
        else listProc.running = true;
    }

    function run(args) {
        if (actionProc.running) return false;
        errorText = "";
        actionProc.command = ["pkexec", helper].concat(args);
        actionProc.running = true;
        return true;
    }

    function add(label, port, protocol) {
        return run(["add", label.trim(), port, protocol]);
    }

    function setEnabled(rule, on) {
        run([on ? "enable" : "disable", String(rule.port), rule.protocol]);
    }

    function remove(rule) {
        run(["remove", String(rule.port), rule.protocol]);
    }

    // pkexec's own exit codes: 126 = not authorized/dismissed, 127 = failed
    // authentication; anything else is the helper's "firewall-rules: ...".
    function message(code, stderr) {
        if (code === 126 || code === 127)
            return "Keine Berechtigung, die Firewall zu ändern (polkit).";
        return stderr.trim().split("\n")[0].replace(/^firewall-rules: /, "")
            || "fehlgeschlagen (Exit " + code + ")";
    }

    signal actionDone(bool ok)

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: ["pkexec", model.helper, "list"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    const d = JSON.parse(listOut.text);
                    model.rules = d.rules;
                    model.loaded = d.loaded;
                } catch (e) {
                    model.errorText = "Der Firewall-Helper lieferte keine Regelliste.";
                    Log.warn("firewall", "`firewall-rules list` returned no JSON");
                }
            } else {
                model.errorText = model.message(exitCode, listErr.text);
                Log.warn("firewall", "`firewall-rules list` failed (exit " + exitCode + "): " + Log.firstLine(listErr.text));
            }
            model.listed = true;
            if (model.refreshPending) {
                model.refreshPending = false;
                running = true;
            }
        }
    }

    Process {
        id: actionProc
        stderr: StdioCollector { id: actionErr }
        onExited: exitCode => {
            if (exitCode !== 0) {
                model.errorText = model.message(exitCode, actionErr.text);
                Log.warn("firewall", "`firewall-rules " + command[2] + "` failed (exit " + exitCode + "): " + Log.firstLine(actionErr.text));
            }
            model.actionDone(exitCode === 0);
            model.refresh();
        }
    }
}
