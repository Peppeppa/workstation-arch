// OS menu -> System -> Create Snapshot: one manual snapper snapshot of / with a
// description. Managed by Ansible: do not edit by hand, see roles/quickshell
// in workstation-arch. Deployed only with the host capability
// recovery_enabled. See docs/feature-architecture.md "System updates".
//
// The description is optional - empty becomes "Manueller Snapshot <date
// time>". It is checked here for feedback (1-100 bytes UTF-8, no control
// characters, not starting with "-") and again by the root helper, which gets
// it as ONE argv element through `pkexec <helper> <label>` - no shell, no
// string built into a command. The helper (roles/recovery snapshot-create)
// only creates: system-snapshot "<label>" (snapper config root, important,
// kept by count). It never deletes, modifies or rolls back. A failure is
// shown as such - no success message, no retry with other privileges.
//
// Keys: Enter = Erstellen, Escape = Abbrechen/close. A snapshot is not a
// backup: it lives on the same disk (README "System updates").

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar

PanelWindow {
    id: dlg

    required property int fontSize
    required property string helper            // recovery_snapshot_helper

    property string stage: "input"             // input | working | done | failed
    property string error: ""
    property var created: null                 // {number, date, description}

    function open() {
        stage = "input";
        error = "";
        created = null;
        field.text = "";
        visible = true;
    }

    function close() {
        if (stage === "working") return;       // the helper runs: wait for its answer
        visible = false;
    }

    // One transient surface at a time (bar/BarPopups.qml).
    function closePopup() {
        close();
    }
    onVisibleChanged: {
        if (visible) {
            BarPopups.request(dlg);
            field.forceActiveFocus();
        } else {
            BarPopups.release(dlg);
        }
    }

    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }

    // The description the helper gets, or why not. Pure (tests).
    function labelFor(text, now) {
        const t = text.trim();
        const label = t !== "" ? t
            : "Manueller Snapshot " + now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
              + " " + pad(now.getHours()) + ":" + pad(now.getMinutes());
        if (/[\u0000-\u001f\u007f]/.test(label)) return { label: "", error: "Keine Steuerzeichen (Tab, Zeilenumbruch) im Namen." };
        if (label.startsWith("-")) return { label: "", error: "Der Name darf nicht mit \"-\" beginnen." };
        if (unescape(encodeURIComponent(label)).length > 100) return { label: "", error: "Der Name ist zu lang (höchstens 100 Bytes)." };
        return { label: label, error: "" };
    }

    function create() {
        if (stage !== "input") return;
        const r = labelFor(field.text, new Date());
        if (r.error !== "") {
            error = r.error;
            return;
        }
        error = "";
        stage = "working";
        proc.command = ["pkexec", dlg.helper, r.label];
        proc.running = true;
    }

    // pkexec: 126 = not authorized/dismissed, 127 = authentication failed.
    function failure(code, stderr) {
        if (code === 126 || code === 127) return "Keine Berechtigung (polkit) - es wurde kein Snapshot erstellt.";
        return (Log.firstLine(stderr).replace(/^snapshot-create: /, "") || "fehlgeschlagen (Exit " + code + ")");
    }

    Process {
        id: proc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            let d = null;
            if (code === 0) {
                try {
                    d = JSON.parse(out.text);
                } catch (e) {
                    d = null;
                }
            }
            if (d && typeof d.number === "number") {
                dlg.created = d;
                dlg.stage = "done";
            } else {
                dlg.error = code === 0 ? "Der Helper meldete keine Snapshot-Nummer." : dlg.failure(code, err.text);
                dlg.stage = "failed";
                Log.warn("snapshot", "snapshot-create failed (exit " + code + "): " + Log.firstLine(err.text));
            }
        }
    }

    IpcHandler {
        target: "snapshot"

        function open(): void {
            dlg.open();
        }

        function close(): void {
            dlg.close();
        }

        // {visible, stage, error, created}
        function state(): string {
            return JSON.stringify({ visible: dlg.visible, stage: dlg.stage, error: dlg.error, created: dlg.created });
        }
    }

    // ---- surface ------------------------------------------------------------
    visible: false
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
    WlrLayershell.namespace: "quickshell-snapshot"

    MouseArea {
        anchors.fill: parent
        onClicked: dlg.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Fonts.px(460)
        height: box.implicitHeight + 32
        radius: 8
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: box
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 8

            Text {
                text: "Snapshot erstellen"
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize + 1
                font.bold: true
            }

            Text {
                visible: dlg.stage === "input" || dlg.stage === "working"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Name (optional) - leer: Datum und Uhrzeit."
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 1
            }

            Rectangle {
                visible: dlg.stage === "input" || dlg.stage === "working"
                Layout.fillWidth: true
                implicitHeight: Fonts.px(30)
                radius: 4
                color: Colors.surface
                border.color: field.activeFocus ? Colors.borderActive : Colors.border
                border.width: 1

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    readOnly: dlg.stage !== "input"
                    color: Colors.foreground
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.accentForeground
                    font.family: Fonts.family
                    font.pixelSize: dlg.fontSize - 1
                    Keys.onReturnPressed: dlg.create()
                    Keys.onEnterPressed: dlg.create()
                    Keys.onEscapePressed: dlg.close()

                    Text {
                        visible: field.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "z. B. Vor Installation von Software"
                        color: Colors.foregroundMuted
                        font: field.font
                    }
                }
            }

            // Result: number, description, time.
            GridLayout {
                visible: dlg.stage === "done"
                columns: 2
                columnSpacing: 12
                rowSpacing: 4

                component Key: Text {
                    color: Colors.foregroundMuted
                    font.family: Fonts.family
                    font.pixelSize: dlg.fontSize - 1
                }
                component Val: Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: dlg.fontSize - 1
                }

                Key { text: "Snapshot" }
                Val { text: dlg.created ? String(dlg.created.number) : "" }
                Key { text: "Beschreibung" }
                Val { text: dlg.created ? dlg.created.description : "" }
                Key { text: "Zeitpunkt" }
                Val { text: dlg.created ? dlg.created.date : "" }
            }

            Text {
                visible: dlg.stage === "done"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Erstellt. Ein Snapshot liegt auf derselben Festplatte - er ersetzt kein externes Backup."
                color: Colors.success
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 2
            }

            Text {
                visible: dlg.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: (dlg.stage === "failed" ? "Snapshot fehlgeschlagen: " : "") + dlg.error
                color: Colors.error
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 1
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Item { Layout.fillWidth: true }

                PopupButton {
                    visible: dlg.stage === "input" || dlg.stage === "working"
                    label: "Abbrechen"
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.close()
                }
                PopupButton {
                    visible: dlg.stage === "input" || dlg.stage === "working"
                    primary: dlg.stage === "input"
                    label: dlg.stage === "working" ? "…" : "Erstellen"
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.create()
                }
                PopupButton {
                    visible: dlg.stage === "done" || dlg.stage === "failed"
                    primary: true
                    label: "Schließen"
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.close()
                }
            }
        }
    }

    // done/failed: Enter or Escape closes (the field is hidden then).
    onStageChanged: if (stage === "done" || stage === "failed") resultKeys.forceActiveFocus()

    Item {
        id: resultKeys
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                dlg.close();
                event.accepted = true;
            }
        }
    }
}
