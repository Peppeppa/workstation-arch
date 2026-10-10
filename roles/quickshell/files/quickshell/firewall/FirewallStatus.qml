// Firewall -> "Wirksamer Zustand": what the kernel really does with inbound
// traffic, read-only. Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. See docs/feature-architecture.md
// "Firewall".
//
// Everything shown comes from `firewall-rules status` (FirewallModel.status:
// the LIVE table inet workstation + the configured file loaded in a private
// network namespace for comparison, `ss` for listeners and connections) -
// texts are built only from those fields, unknown conditions are shown
// verbatim, a name appears only where the configuration gave the rule one.
// Distinguished on purpose:
//   allowed     an accept rule (with its source / interface / IP version -
//               "alle" only when the rule really has no such condition)
//   listening   a socket on the port (not the same as allowed)
//   connected   established connections right now (proof of one path, not
//               of reachability in general - that cannot be tested from here)
// Nothing here changes the firewall; no timer - refreshed when the window
// opens and after every change.

import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    id: root

    required property var model            // FirewallModel
    required property int fontSize
    readonly property var st: model.status

    spacing: 4

    // ---- pure text helpers (tests: tests/qml-logic.qml) ----------------------
    function familyText(x) {
        return x.family ? "nur " + x.family : "IPv4 + IPv6";
    }

    function listText(list, all) {
        return list && list.length > 0 ? list.join(", ") : all;
    }

    // One accept/drop rule with a port: "TCP 22" + where it applies.
    function ruleTitle(x) {
        return (x.service ? x.service + " - " : "") + x.proto + " " + x.ports;
    }

    function ruleScope(x) {
        const parts = ["Quelle: " + listText(x.source, "alle Adressen"),
                       "Schnittstelle: " + listText(x.iface, "alle"),
                       familyText(x)];
        if (x.dest && x.dest.length > 0) parts.push("Ziel: " + x.dest.join(", "));
        if (x.other && x.other.length > 0) parts.push("weitere Bedingung: " + x.other.join("; "));
        return parts.join(" · ");
    }

    function originText(x) {
        return x.origin + " · " + x.persistence;
    }

    function listenText(x) {
        if (!x.listening) return "Lauschen: unbekannt";
        if (x.listening.length === 0) return "Kein Programm lauscht gerade auf diesem Port (ss)";
        return "Lauscht: " + x.listening.map(s => (s.process || "?") + " (" + s.scope + ")").join(", ");
    }

    function connText(x) {
        if (!x.connections || x.connections.length === 0) return "";
        return "Aktive Verbindungen: " + x.connections.map(c => c.peer + " über " + c.iface).join(", ");
    }

    // A rule without a port (loopback, replies, ICMP, Docker bridges ...):
    // its conditions as they are, then the action.
    function infraText(x) {
        const c = [];
        if (x.iface && x.iface.length > 0) c.push("Schnittstelle " + x.iface.join(", "));
        if (x.ct) c.push("Verbindungsstatus " + x.ct);
        if (x.icmp) c.push((x.family === "IPv6" ? "ICMPv6 " : "ICMP ") + x.icmp);
        if (x.proto && !x.icmp) c.push(x.proto);
        if (x.source && x.source.length > 0) c.push("Quelle " + x.source.join(", "));
        if (x.dest && x.dest.length > 0) c.push("Ziel " + x.dest.join(", "));
        if (x.other && x.other.length > 0) c.push(x.other.join("; "));
        return (c.length > 0 ? c.join(" · ") : "alles") + " → " + actionText(x.action);
    }

    function actionText(a) {
        return a === "accept" ? "erlauben" : a === "drop" ? "verwerfen" : a === "reject" ? "abweisen" : String(a);
    }

    function sockText(s) {
        return s.proto + " " + s.port + " " + (s.process || "?") + " (" + s.scope + ")";
    }

    readonly property var portRules: st ? st.inbound.filter(x => x.kind === "port") : []
    readonly property var infraRules: st ? st.inbound.filter(x => x.kind !== "port") : []

    component Heading: Text {
        Layout.fillWidth: true
        Layout.topMargin: 8
        color: Colors.foreground
        font.family: Fonts.family
        font.pixelSize: root.fontSize
        font.bold: true
    }
    component Line: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: root.fontSize - 3
    }

    Heading {
        text: "Wirksamer Zustand (live, eingehend)"
    }

    Line {
        visible: root.st === null && root.model.statusError === ""
        text: "…"
    }

    Text {
        visible: root.model.statusError !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.model.statusError
        color: Colors.error
        font.family: Fonts.family
        font.pixelSize: root.fontSize - 2
    }

    Text {
        visible: root.st !== null
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: !root.st ? "" : root.st.loaded
            ? "Firewall aktiv. Eingehend wird alles verworfen (policy " + root.st.policy + "), außer was unten erlaubt ist."
            : "Firewall-Tabelle nicht geladen - eingehender Verkehr wird von dieser Firewall NICHT gefiltert."
        color: root.st && root.st.loaded ? Colors.foreground : Colors.error
        font.family: Fonts.family
        font.pixelSize: root.fontSize - 2
    }

    // ---- allowed ports -----------------------------------------------------
    Heading {
        visible: root.portRules.length > 0
        text: "Erlaubte Zugriffe"
        font.pixelSize: root.fontSize - 1
    }

    Repeater {
        model: root.portRules

        Rectangle {
            id: card
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: cardCol.implicitHeight + 10
            radius: 4
            color: "transparent"
            border.color: Colors.border
            border.width: 1

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 5
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.ruleTitle(card.modelData) + "  →  " + root.actionText(card.modelData.action)
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: root.fontSize - 2
                }
                Line { text: root.ruleScope(card.modelData) }
                Line { text: root.originText(card.modelData) }
                Line { text: root.listenText(card.modelData) }
                Line {
                    visible: text !== ""
                    text: root.connText(card.modelData)
                }
            }
        }
    }

    Line {
        visible: root.st !== null && root.st.loaded && root.portRules.length === 0
        text: "Keine Port-Freigaben - von außen ist kein Dienst erreichbar."
    }

    // ---- configured but not live -------------------------------------------
    Heading {
        visible: root.st !== null && root.st.missing.length > 0
        text: "Konfiguriert, aber nicht aktiv"
        font.pixelSize: root.fontSize - 1
    }
    Repeater {
        model: root.st ? root.st.missing : []
        Line {
            required property var modelData
            color: Colors.error
            text: (modelData.service ? modelData.service + " - " : "") + (modelData.ports ? modelData.proto + " " + modelData.ports : root.infraText(modelData))
        }
    }

    // ---- listening, but blocked / local only -------------------------------
    Heading {
        visible: root.st !== null && root.st.blocked.length > 0
        text: "Lauscht, aber eingehend nicht erlaubt"
        font.pixelSize: root.fontSize - 1
    }
    Repeater {
        model: root.st ? root.st.blocked : []
        Line {
            required property var modelData
            text: root.sockText(modelData) + (root.st.loaded ? " - von außen blockiert" : " - Firewall nicht geladen: nicht gefiltert")
        }
    }

    Heading {
        visible: root.st !== null && root.st.localOnly.length > 0
        text: "Nur lokal (Loopback)"
        font.pixelSize: root.fontSize - 1
    }
    Repeater {
        model: root.st ? root.st.localOnly : []
        Line {
            required property var modelData
            text: root.sockText(modelData) + " - nur von diesem Rechner erreichbar"
        }
    }

    // ---- base rules without a port ----------------------------------------
    Heading {
        visible: root.infraRules.length > 0
        text: "Grundregeln"
        font.pixelSize: root.fontSize - 1
    }
    Repeater {
        model: root.infraRules
        Line {
            required property var modelData
            text: root.infraText(modelData) + (modelData.persistence !== "persistent" ? " (" + modelData.persistence + ")" : "")
        }
    }

    // ---- other tables -------------------------------------------------------
    Heading {
        visible: root.st !== null && root.st.foreign.length > 0
        text: "Weitere nftables-Tabellen (nicht von hier verwaltet)"
        font.pixelSize: root.fontSize - 1
    }
    Repeater {
        model: root.st ? root.st.foreign : []
        Line {
            required property var modelData
            text: modelData.table + (modelData.chains.length > 0
                  ? ": " + modelData.chains.map(c => c.name + " (" + c.hook + ", policy " + c.policy + ", " + c.rules + " Regeln)").join(", ")
                  : ": ohne eigene Hook-Ketten") + " - nicht ausgewertet"
        }
    }

    Line {
        visible: root.st !== null
        Layout.topMargin: 6
        text: "Ob ein erlaubter Port von einem bestimmten Netz aus wirklich erreichbar ist (Router, VPN, Netzwerk-Firewalls), lässt sich von hier aus nicht feststellen - aktive Verbindungen zeigen nur, dass ein Zugriff gerade besteht."
    }
}
