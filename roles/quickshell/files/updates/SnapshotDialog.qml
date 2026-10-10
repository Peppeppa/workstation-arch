// OS menu -> System -> Create Snapshot: the three MANUAL snapshot slots.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Deployed only with the host capability recovery_enabled.
// See docs/feature-architecture.md "System updates" and
// docs/recovery-design.md 23.
//
// Each slot is empty ("Leer") or holds exactly one snapshot: name, time,
// snapper number and whether the boot menu offers it (bootfähig / nicht
// bootfähig + why). The list is read without root (`<lister> slot-list
// --json`: snapper's info.xml + the snapshot-boot state) when the dialog
// opens and after every action - no polling.
//   empty slot   -> name (optional; empty = "Manueller Snapshot <date time>")
//                   -> Erstellen
//   occupied     -> Überschreiben: name -> a question naming the old snapshot
//                   (Abbrechen preselected) -> only then the helper, with the
//                   number the user saw (the helper refuses if the slot holds
//                   another one by then)
//   ✕            -> a question naming the snapshot (Abbrechen preselected)
//                   -> delete exactly that number
// Actions: `pkexec <helper> set <slot> <label> [<old number>]` /
// `pkexec <helper> delete <slot> <number>` (roles/recovery snapshot-create,
// polkit org.workstation.snapshot.create) - fixed argv, the label is ONE
// element. The helper creates the new snapshot first, checks it can boot,
// moves the slot and only then deletes the old one: a failure leaves the
// slot as it was. Results and errors stay visible in the dialog.
//
// Keys: Up/Down pick a slot, Enter = Erstellen/Überschreiben, Delete = ✕,
// Escape = back/close (in a question: Abbrechen); Left/Right/Tab move between
// the buttons of a question. A snapshot is not a backup: same disk.

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
    required property string helper            // recovery_snapshot_helper (pkexec)
    required property string lister            // snapshot-boot (slot-list, no root)

    property string stage: "slots"             // slots | name | confirmReplace | confirmDelete | working
    property var slots: []                     // [{slot, empty, number, description, date, status, reason}]
    property int current: 0                    // index into slots
    property int selected: 0                   // button in a question (0 = Abbrechen)
    property string error: ""                  // input error in the name stage
    property string message: ""                // result of the last action
    property bool messageIsError: false
    property bool loading: false

    readonly property var target: slots.length > current ? slots[current] : null

    function open() {
        stage = "slots";
        error = "";
        message = "";
        current = 0;
        visible = true;
        reload();
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
            keys.forceActiveFocus();
        } else {
            BarPopups.release(dlg);
        }
    }

    function reload() {
        loading = true;
        listProc.running = true;
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

    // A slot's status line. Pure (tests).
    function statusText(s) {
        if (!s || s.empty) return "";
        if (s.status === "bootable") return "bootfähig - im Bootmenü";
        if (s.status === "not-bootable") return "nicht bootfähig: " + s.reason;
        return "Bootstatus noch unbekannt";
    }

    // The helper's argv for an action. Pure (tests).
    function argvFor(action, s, label) {
        if (action === "delete") return ["pkexec", helper, "delete", String(s.slot), String(s.number)];
        const a = ["pkexec", helper, "set", String(s.slot), label];
        return s.empty ? a : a.concat([String(s.number)]);
    }

    // pkexec: 126 = not authorized/dismissed, 127 = authentication failed.
    function failure(code, stderr) {
        if (code === 126 || code === 127) return "Keine Berechtigung (polkit) - es wurde nichts verändert.";
        const lines = (stderr || "").split("\n").filter(l => l.trim() !== "");
        const last = lines.length ? lines[lines.length - 1] : "";
        return last.replace(/^(snapshot-boot|snapshot-create): /, "") || "fehlgeschlagen (Exit " + code + ")";
    }

    // ---- actions ------------------------------------------------------------
    function startCreate() {
        if (!target || loading) return;
        error = "";
        message = "";
        field.text = "";
        stage = "name";
        field.forceActiveFocus();
    }

    function submitName() {
        const r = labelFor(field.text, new Date());
        if (r.error !== "") {
            error = r.error;
            return;
        }
        pendingLabel = r.label;
        if (target.empty) run("set");
        else {
            stage = "confirmReplace";
            selected = 0;                      // Abbrechen preselected
            keys.forceActiveFocus();
        }
    }
    property string pendingLabel: ""
    property string pendingAction: ""

    function startDelete() {
        if (!target || target.empty || loading) return;
        message = "";
        stage = "confirmDelete";
        selected = 0;
        keys.forceActiveFocus();
    }

    function run(action) {
        pendingAction = action;
        stage = "working";
        proc.command = argvFor(action, target, pendingLabel);
        proc.running = true;
    }

    function back() {
        stage = "slots";
        error = "";
        keys.forceActiveFocus();
    }

    function answer(yes) {
        if (!yes) { back(); return; }
        run(stage === "confirmDelete" ? "delete" : "set");
    }

    function handleKey(key) {
        switch (stage) {
        case "slots":
            switch (key) {
            case Qt.Key_Up:     current = (current - 1 + slots.length) % Math.max(1, slots.length); return true;
            case Qt.Key_Down:   current = (current + 1) % Math.max(1, slots.length); return true;
            case Qt.Key_Return: case Qt.Key_Enter: startCreate(); return true;
            case Qt.Key_Delete: startDelete(); return true;
            case Qt.Key_Escape: close(); return true;
            }
            return false;
        case "confirmReplace": case "confirmDelete":
            switch (key) {
            case Qt.Key_Left: case Qt.Key_Right: case Qt.Key_Tab: case Qt.Key_Backtab: selected = 1 - selected; return true;
            case Qt.Key_Return: case Qt.Key_Enter: answer(selected === 1); return true;
            case Qt.Key_Escape: answer(false); return true;
            }
            return false;
        }
        return false;
    }

    Process {
        id: listProc
        command: [dlg.lister, "slot-list", "--json"]
        stdout: StdioCollector { id: listOut }
        onExited: code => {
            dlg.loading = false;
            let d = null;
            try { d = JSON.parse(listOut.text); } catch (e) { d = null; }
            if (code === 0 && d && Array.isArray(d.slots)) {
                dlg.slots = d.slots;
                dlg.current = Math.min(dlg.current, Math.max(0, d.slots.length - 1));
            } else {
                dlg.message = "Die Slots konnten nicht gelesen werden (Exit " + code + ").";
                dlg.messageIsError = true;
                Log.warn("snapshot", "slot-list failed (exit " + code + ")");
            }
        }
    }

    Process {
        id: proc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            let d = null;
            if (code === 0) {
                try { d = JSON.parse(out.text.trim().split("\n").pop()); } catch (e) { d = null; }
            }
            if (d && d.ok === true) {
                dlg.messageIsError = false;
                dlg.message = dlg.pendingAction === "delete"
                    ? "Slot " + d.slot + " geleert (Snapshot #" + d.deleted + " gelöscht)."
                    : "Slot " + d.slot + ": „" + d.description + "“ erstellt (#" + d.number + ")"
                      + (d.replaced ? ", vorheriger Snapshot #" + d.replaced + " gelöscht." : ".");
                if (d.warnings && d.warnings.length) {
                    dlg.message += " Hinweis: " + d.warnings.join("; ");
                    dlg.messageIsError = true;
                }
            } else {
                dlg.messageIsError = true;
                dlg.message = (dlg.pendingAction === "delete" ? "Löschen fehlgeschlagen: " : "Snapshot fehlgeschlagen: ")
                    + (code === 0 ? "keine Antwort des Helpers." : dlg.failure(code, err.text))
                    + " Der Slot ist unverändert.";
                Log.warn("snapshot", "snapshot-create " + dlg.pendingAction + " failed (exit " + code + "): " + Log.firstLine(err.text));
            }
            dlg.stage = "slots";
            keys.forceActiveFocus();
            dlg.reload();
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

        // {visible, stage, current, slots, message, error}
        function state(): string {
            return JSON.stringify({ visible: dlg.visible, stage: dlg.stage, current: dlg.current, slots: dlg.slots,
                                    message: dlg.message, error: dlg.error });
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
        onClicked: {
            if (dlg.stage === "slots") dlg.close();
            else if (dlg.stage !== "working") dlg.back();     // a question/name: the safe way out first
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => event.accepted = dlg.handleKey(event.key)
    }

    Rectangle {
        anchors.centerIn: parent
        width: Fonts.px(540)
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
                text: dlg.stage === "confirmReplace" ? "Slot " + (dlg.target ? dlg.target.slot : "") + " überschreiben?"
                    : dlg.stage === "confirmDelete" ? "Snapshot löschen?"
                    : dlg.stage === "name" ? "Snapshot in Slot " + (dlg.target ? dlg.target.slot : "")
                    : "Manuelle Snapshots"
                color: Colors.foregroundStrong
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize + 1
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 2
                visible: dlg.stage === "slots" || dlg.stage === "working"
                text: "Drei feste Plätze für eigene Sicherungspunkte - jeder ist im Bootmenü wählbar. "
                    + "Update-Snapshots entstehen automatisch (die letzten zwei)."
            }

            // ---- the slots
            Repeater {
                model: (dlg.stage === "slots" || dlg.stage === "working") ? dlg.slots : []

                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === dlg.current

                    Layout.fillWidth: true
                    implicitHeight: rowBox.implicitHeight + 14
                    radius: 6
                    color: sel ? Colors.surface : "transparent"
                    border.color: sel ? Colors.borderActive : Colors.border
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        onClicked: dlg.current = row.index
                    }

                    RowLayout {
                        id: rowBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 10

                        Text {
                            text: "Slot " + row.modelData.slot
                            color: Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: dlg.fontSize - 1
                            font.bold: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: row.modelData.empty ? "Leer" : row.modelData.description
                                color: row.modelData.empty ? Colors.foregroundMuted : Colors.foreground
                                font.family: Fonts.family
                                font.pixelSize: dlg.fontSize - 1
                                font.italic: row.modelData.empty
                            }
                            Text {
                                visible: !row.modelData.empty
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: (row.modelData.date || "") + "  ·  #" + row.modelData.number + "  ·  " + dlg.statusText(row.modelData)
                                color: row.modelData.status === "not-bootable" ? Colors.error : Colors.foregroundMuted
                                font.family: Fonts.family
                                font.pixelSize: dlg.fontSize - 3
                            }
                        }

                        PopupButton {
                            label: row.modelData.empty ? "Erstellen" : "Überschreiben"
                            primary: row.sel
                            fontSize: dlg.fontSize - 2
                            onClicked: if (dlg.stage === "slots") { dlg.current = row.index; dlg.startCreate(); }
                        }
                        PopupButton {
                            visible: !row.modelData.empty
                            label: "✕"
                            danger: true
                            fontSize: dlg.fontSize - 2
                            onClicked: if (dlg.stage === "slots") { dlg.current = row.index; dlg.startDelete(); }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 2
                visible: dlg.stage === "working"
                text: "…"
            }

            // ---- name
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Colors.foregroundMuted
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 2
                visible: dlg.stage === "name"
                text: dlg.target && !dlg.target.empty
                    ? "Name des neuen Snapshots (optional - leer: Datum und Uhrzeit). Danach wird gefragt, ob „"
                      + dlg.target.description + "“ ersetzt werden soll."
                    : "Name (optional - leer: Datum und Uhrzeit)."
            }
            Rectangle {
                visible: dlg.stage === "name"
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
                    color: Colors.foreground
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.accentForeground
                    font.family: Fonts.family
                    font.pixelSize: dlg.fontSize - 1
                    Keys.onReturnPressed: dlg.submitName()
                    Keys.onEnterPressed: dlg.submitName()
                    Keys.onEscapePressed: dlg.back()

                    Text {
                        visible: field.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "z. B. Vor Installation von Software"
                        color: Colors.foregroundMuted
                        font: field.font
                    }
                }
            }
            Text {
                visible: dlg.stage === "name" && dlg.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: dlg.error
                color: Colors.error
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 1
            }

            // ---- questions
            Text {
                visible: dlg.stage === "confirmReplace" || dlg.stage === "confirmDelete"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 1
                text: !dlg.target || dlg.target.empty ? ""
                    : dlg.stage === "confirmReplace"
                    ? "Slot " + dlg.target.slot + " enthält „" + dlg.target.description + "“ vom " + dlg.target.date
                      + " (#" + dlg.target.number + ").\n\nDer neue Snapshot „" + dlg.pendingLabel + "“ wird zuerst erstellt und "
                      + "geprüft; erst danach wird der bisherige gelöscht. Schlägt etwas fehl, bleibt der Slot wie er ist."
                    : "„" + dlg.target.description + "“ vom " + dlg.target.date + " (#" + dlg.target.number + ") aus Slot "
                      + dlg.target.slot + " löschen?\n\nDer Snapshot und sein Bootmenü-Eintrag werden entfernt - das lässt sich "
                      + "nicht rückgängig machen. Danach ist der Slot wieder frei."
            }

            Text {
                visible: dlg.message !== "" && dlg.stage === "slots"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: dlg.message
                color: dlg.messageIsError ? Colors.error : Colors.success
                font.family: Fonts.family
                font.pixelSize: dlg.fontSize - 2
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Item { Layout.fillWidth: true }

                PopupButton {
                    visible: dlg.stage === "name"
                    label: "Abbrechen"
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.back()
                }
                PopupButton {
                    visible: dlg.stage === "name"
                    primary: true
                    label: dlg.target && !dlg.target.empty ? "Weiter" : "Erstellen"
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.submitName()
                }
                PopupButton {
                    visible: dlg.stage === "confirmReplace" || dlg.stage === "confirmDelete"
                    label: "Abbrechen"
                    primary: dlg.selected === 0
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.answer(false)
                }
                PopupButton {
                    visible: dlg.stage === "confirmReplace" || dlg.stage === "confirmDelete"
                    label: dlg.stage === "confirmDelete" ? "Löschen" : "Überschreiben"
                    primary: dlg.selected === 1
                    danger: true
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.answer(true)
                }
                PopupButton {
                    visible: dlg.stage === "slots" || dlg.stage === "working"
                    label: "Schließen"
                    fontSize: dlg.fontSize - 1
                    onClicked: dlg.close()
                }
            }
        }
    }
}
