// OS menu -> System -> Create Snapshot: the three MANUAL snapshot slots.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Deployed only with the host capability recovery_enabled.
// See docs/feature-architecture.md "System updates" and
// docs/recovery-design.md 23.
//
// Each slot is empty ("Empty") or holds exactly one snapshot: name, time,
// snapper number and whether the boot menu offers it (bootable / not
// bootable + why). The list is read without root (`<lister> slot-list
// --json`: snapper's info.xml + the snapshot-boot state) when the dialog
// opens and after every action - no polling.
//   empty slot   -> name (optional; empty = "Manual snapshot <date time>")
//                   -> Create
//   occupied     -> Overwrite: name -> a question naming the old snapshot
//                   (Cancel preselected) -> only then the helper, with the
//                   number the user saw (the helper refuses if the slot holds
//                   another one by then)
//   ✕            -> a question naming the snapshot (Cancel preselected)
//                   -> delete exactly that number
// Actions (roles/recovery snapshot-create, one helper under two names) -
// fixed argv, the label is ONE element:
//   create into an empty slot  `pkexec <helper> set <slot> <label>`
//                              (org.workstation.snapshot.create, no password)
//   overwrite                  `pkexec <deleteHelper> replace <slot> <old number> <label>`
//   delete                     `pkexec <deleteHelper> delete <slot> <number>`
//                              (org.workstation.snapshot.delete, administrator
//                              password - Security Hardening v1.1, S3-B)
// While a password may be asked the dialog is HIDDEN (an overlay would sit
// over the polkit agent's window and keep the keyboard) and comes back with
// the result; open() is ignored meanwhile. The helper creates the new
// snapshot first, checks it can boot, moves the slot and only then deletes
// the old one: a failure (also a cancelled password) leaves the slot as it
// was. Results and errors stay visible in the dialog.
//
// Keys: Up/Down pick a slot, Enter = Create/Overwrite, Delete = ✕,
// Escape = back/close (in a question: Cancel); Left/Right/Tab move between
// the buttons of a question. A snapshot is not a backup: same disk.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar
import qs.ui

PanelWindow {
    id: dlg

    required property int fontSize
    required property string helper            // recovery_snapshot_helper (pkexec, no password)
    required property string deleteHelper      // recovery_snapshot_delete_helper (pkexec, password)
    property bool hiddenForAuth: false         // hidden while pkexec may ask for the password
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
        if (hiddenForAuth) return;             // the polkit prompt is up - do not cover it
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
            : "Manual snapshot " + now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
              + " " + pad(now.getHours()) + ":" + pad(now.getMinutes());
        if (/[\u0000-\u001f\u007f]/.test(label)) return { label: "", error: "No control characters (tab, line break) in the name." };
        if (label.startsWith("-")) return { label: "", error: "The name must not start with \"-\"." };
        if (unescape(encodeURIComponent(label)).length > 100) return { label: "", error: "The name is too long (at most 100 bytes)." };
        return { label: label, error: "" };
    }

    // A slot's status line. Pure (tests).
    function statusText(s) {
        if (!s || s.empty) return "";
        if (s.status === "bootable") return "bootable";
        if (s.status === "not-bootable") return "not bootable: " + s.reason;
        return "boot status not known yet";
    }

    // The helper's argv for an action. Pure (tests). Removing a snapshot
    // (delete, overwrite) goes through deleteHelper - the password one.
    function argvFor(action, s, label) {
        if (action === "delete") return ["pkexec", deleteHelper, "delete", String(s.slot), String(s.number)];
        if (s.empty) return ["pkexec", helper, "set", String(s.slot), label];
        return ["pkexec", deleteHelper, "replace", String(s.slot), String(s.number), label];
    }

    // Does this action remove a snapshot (= polkit asks for the password)? Pure.
    function needsPassword(action, s) {
        return action === "delete" || !s.empty;
    }

    // pkexec: 126 = not authorized/dismissed, 127 = authentication failed.
    function failure(code, stderr) {
        if (code === 126 || code === 127) return "Not authorized (polkit) - nothing was changed.";
        const lines = (stderr || "").split("\n").filter(l => l.trim() !== "");
        const last = lines.length ? lines[lines.length - 1] : "";
        return last.replace(/^(snapshot-boot|snapshot-create|snapshot-delete): /, "") || "failed (exit " + code + ")";
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
        if (needsPassword(action, target)) {
            hiddenForAuth = true;
            visible = false;                   // the polkit agent's window needs the keyboard
        }
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
                dlg.message = "The slots could not be read (exit " + code + ").";
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
                    ? "Slot " + d.slot + " emptied (snapshot #" + d.deleted + " deleted)."
                    : "Slot " + d.slot + ": \u201c" + d.description + "\u201d created (#" + d.number + ")"
                      + (d.replaced ? ", previous snapshot #" + d.replaced + " deleted." : ".");
                if (d.warnings && d.warnings.length) {
                    dlg.message += " Note: " + d.warnings.join("; ");
                    dlg.messageIsError = true;
                }
            } else {
                dlg.messageIsError = true;
                dlg.message = (dlg.pendingAction === "delete" ? "Delete failed: " : "Snapshot failed: ")
                    + (code === 0 ? "no answer from the helper." : dlg.failure(code, err.text))
                    + " The slot is unchanged.";
                Log.warn("snapshot", "slot " + dlg.pendingAction + " failed (exit " + code + "): " + Log.firstLine(err.text));
            }
            dlg.stage = "slots";
            if (dlg.hiddenForAuth) {
                dlg.visible = true;
                dlg.hiddenForAuth = false;
            }
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

        // {visible, stage, current, slots, message, error, hiddenForAuth}
        function state(): string {
            return JSON.stringify({ visible: dlg.visible, stage: dlg.stage, current: dlg.current, slots: dlg.slots,
                                    message: dlg.message, error: dlg.error, hiddenForAuth: dlg.hiddenForAuth });
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

    DialogFrame {
        panelWidth: Style.widePanelWidth
        title: dlg.stage === "confirmReplace" ? "Overwrite slot " + (dlg.target ? dlg.target.slot : "") + "?"
             : dlg.stage === "confirmDelete" ? "Delete the snapshot?"
             : dlg.stage === "name" ? "Snapshot in slot " + (dlg.target ? dlg.target.slot : "")
             : "Manual snapshots"
        titleColor: Colors.foregroundStrong

        DialogText {
            visible: dlg.stage === "slots" || dlg.stage === "working"
            kind: "hint"
            text: "Three fixed places for your own restore points - each one can be chosen in the boot menu. "
                + "Update snapshots are made automatically (the last two)."
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
                implicitHeight: Math.max(Style.standardRowHeight, rowBox.implicitHeight + 2 * Style.spacingSm)
                radius: Style.controlRadius
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
                    anchors.leftMargin: Style.spacingMd
                    anchors.rightMargin: Style.spacingMd
                    spacing: Style.spacingMd

                    Text {
                        text: "Slot " + row.modelData.slot
                        color: Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: Style.secondary
                        font.bold: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: row.modelData.empty ? "Empty" : row.modelData.description
                            color: row.modelData.empty ? Colors.foregroundMuted : Colors.foreground
                            font.family: Fonts.family
                            font.pixelSize: Style.secondary
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
                            font.pixelSize: Style.caption
                        }
                    }

                    PopupButton {
                        label: row.modelData.empty ? "Create" : "Overwrite"
                        primary: row.sel
                        fontSize: Style.caption
                        onClicked: if (dlg.stage === "slots") { dlg.current = row.index; dlg.startCreate(); }
                    }
                    PopupButton {
                        visible: !row.modelData.empty
                        label: "✕"
                        danger: true
                        fontSize: Style.caption
                        onClicked: if (dlg.stage === "slots") { dlg.current = row.index; dlg.startDelete(); }
                    }
                }
            }
        }

        DialogText {
            visible: dlg.stage === "working"
            kind: "hint"
            text: "…"
        }

        // ---- name
        DialogText {
            visible: dlg.stage === "name"
            kind: "hint"
            text: dlg.target && !dlg.target.empty
                ? "Name of the new snapshot (optional - empty: date and time). You are asked afterwards whether \u201c"
                  + dlg.target.description + "\u201d is replaced."
                : "Name (optional - empty: date and time)."
        }
        Rectangle {
            visible: dlg.stage === "name"
            Layout.fillWidth: true
            implicitHeight: Style.standardRowHeight
            radius: Style.controlRadius
            color: Colors.surface
            border.color: field.activeFocus ? Colors.borderActive : Colors.border
            border.width: 1

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: Style.spacingMd
                anchors.rightMargin: Style.spacingMd
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Colors.foreground
                selectionColor: Colors.accent
                selectedTextColor: Colors.accentForeground
                font.family: Fonts.family
                font.pixelSize: Style.secondary
                Keys.onReturnPressed: dlg.submitName()
                Keys.onEnterPressed: dlg.submitName()
                Keys.onEscapePressed: dlg.back()

                Text {
                    visible: field.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "e.g. Before installing software"
                    color: Colors.foregroundMuted
                    font: field.font
                }
            }
        }
        DialogText {
            visible: dlg.stage === "name" && dlg.error !== ""
            kind: "error"
            text: dlg.error
        }

        // ---- questions
        DialogText {
            visible: dlg.stage === "confirmReplace" || dlg.stage === "confirmDelete"
            kind: "detail"
            text: !dlg.target || dlg.target.empty ? ""
                : dlg.stage === "confirmReplace"
                ? "Slot " + dlg.target.slot + " holds \u201c" + dlg.target.description + "\u201d from " + dlg.target.date
                  + " (#" + dlg.target.number + ").\n\nThe new snapshot \u201c" + dlg.pendingLabel + "\u201d is created and "
                  + "checked first; only then is the old one deleted. If anything fails, the slot stays as it is."
                : "Delete \u201c" + dlg.target.description + "\u201d from " + dlg.target.date + " (#" + dlg.target.number + ") in slot "
                  + dlg.target.slot + "?\n\nThe snapshot and its boot menu entry are removed - this cannot be "
                  + "undone. The slot is free again afterwards."
        }

        DialogText {
            visible: dlg.message !== "" && dlg.stage === "slots"
            kind: "hint"
            color: dlg.messageIsError ? Colors.error : Colors.success
            text: dlg.message
        }

        DialogButtons {
            buttons: dlg.stage === "name"
                ? [{ id: "back", label: "Cancel" }, { id: "submit", label: dlg.target && !dlg.target.empty ? "Next" : "Create" }]
                : dlg.stage === "confirmReplace" || dlg.stage === "confirmDelete"
                ? [{ id: "no", label: "Cancel" }, { id: "yes", label: dlg.stage === "confirmDelete" ? "Delete" : "Overwrite", danger: true }]
                : [{ id: "close", label: "Close" }]
            // the name step's Create/Next is the default (Enter in the field);
            // a question shows the keyboard selection; the slot list has one button
            selected: dlg.stage === "name" ? 1 : dlg.stage === "confirmReplace" || dlg.stage === "confirmDelete" ? dlg.selected : -1
            onPressed: id => {
                switch (id) {
                case "back":   dlg.back(); break;
                case "submit": dlg.submitName(); break;
                case "no":     dlg.answer(false); break;
                case "yes":    dlg.answer(true); break;
                default:       dlg.close(); break;
                }
            }
        }
    }
}
