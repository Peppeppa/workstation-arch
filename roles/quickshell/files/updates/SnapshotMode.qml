// Snapshot mode (roles/recovery snapshot boot, docs/recovery-design.md 22).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Deployed only with the host capability recovery_enabled.
//
// When the machine was booted from a snapshot entry of the boot menu (kernel
// command line workstation.snapshot=<n>, read ONCE at start - no polling):
//   - a strip along the bottom of every screen, the whole session: "SNAPSHOT-
//     MODUS", the snapshot, a click opens the dialog again
//   - the dialog, opened once at start: date + description of the snapshot,
//     the normal system is unchanged; "Nur testen" (default: closes) /
//     "Dauerhaft wiederherstellen" -> a second question that says what
//     changes (Abbrechen preselected) -> `pkexec <helper> <n>` (polkit
//     org.workstation.snapshot.restore, administrator password) ->
//     system-rollback. While pkexec runs the dialog is HIDDEN: the polkit
//     agent's password window is a normal window, and a full-screen overlay
//     holding the keyboard left it unusable behind the dialog (laptop
//     2026-10-10); the strip says what is going on, the dialog comes back
//     with the result. Success: "Jetzt neu starten" through Hyprland's own
//     session end (workstation_end_session, like the power menu) or later;
//     failure: the helper's reason, nothing changed.
// Outside a snapshot boot nothing is shown and nothing runs after the one
// read of /proc/cmdline. Snapshot data comes from /.snapshots/<n>/info.xml
// (world-readable; snapper writes the date in UTC).
//
// Keys: Left/Right/Tab between the buttons, Enter presses the selected one,
// Escape = the safe answer (close / Abbrechen). The dialog cannot be closed
// while the restore runs.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar
import qs.ui

Scope {
    id: root

    required property int fontSize
    required property string helper            // recovery_restore_helper

    property int number: -1                    // the booted snapshot, -1 = normal boot
    readonly property bool active: number >= 0
    property string date: ""                   // local "YYYY-MM-DD HH:MM"
    property string description: ""
    property string stage: "intro"             // intro | confirm | working | done | failed
    property string error: ""
    property string previous: ""               // @broken-<date> after a restore
    property int selected: 0

    // ---- pure helpers (tests/qml-logic.qml) ----------------------------------
    function parseCmdline(text) {
        const m = /(?:^|\s)workstation\.snapshot=(\d+)(?:\s|$)/.exec(text || "");
        return m ? parseInt(m[1]) : -1;
    }

    function unescapeXml(s) {
        return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
                .replace(/&apos;/g, "'").replace(/&amp;/g, "&");
    }

    // snapper's info.xml -> {date (local, "YYYY-MM-DD HH:MM"), description}
    function parseInfo(xml) {
        const d = /<date>(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})<\/date>/.exec(xml || "");
        const t = /<description>([^<]*)<\/description>/.exec(xml || "");
        let date = "";
        if (d) {
            const at = new Date(Date.UTC(+d[1], +d[2] - 1, +d[3], +d[4], +d[5], +d[6]));
            date = Qt.formatDateTime(at, "yyyy-MM-dd HH:mm");
        }
        return { date: date, description: t ? unescapeXml(t[1]) : "" };
    }

    // The buttons of a stage: [{id, label, danger}]; index 0 = the safe answer.
    function buttonsFor(stage) {
        switch (stage) {
        case "intro":   return [{ id: "test", label: "Just test" }, { id: "restore", label: "Restore permanently…", danger: true }];
        case "confirm": return [{ id: "cancel", label: "Cancel" }, { id: "yes", label: "Restore", danger: true }];
        case "working": return [{ id: "wait", label: "…" }];
        case "done":    return [{ id: "later", label: "Reboot later" }, { id: "reboot", label: "Reboot now" }];
        default:        return [{ id: "close", label: "Close" }];
        }
    }
    readonly property var buttons: buttonsFor(stage)

    // pkexec: 126 = dismissed/not authorized, 127 = authentication failed.
    function failure(code, stderr) {
        if (code === 126 || code === 127) return "Not authorized (polkit) - nothing was changed.";
        return Log.firstLine(stderr).replace(/^snapshot-restore: /, "") || "fehlgeschlagen (Exit " + code + ")";
    }

    // ---- actions ------------------------------------------------------------
    function openDialog() {
        if (!active) return;
        if (stage !== "working" && stage !== "done") stage = "intro";
        selected = 0;
        dialog.visible = true;
    }

    function closeDialog() {
        if (stage === "working") return;           // the helper runs: wait for its answer
        if (stage === "confirm" || stage === "failed") stage = "intro";
        dialog.visible = false;
    }

    function press(id) {
        switch (id) {
        case "test": case "close": case "later":
            closeDialog();
            break;
        case "restore":
            stage = "confirm";
            selected = 0;                          // Abbrechen preselected
            break;
        case "cancel":
            stage = "intro";
            selected = 0;
            break;
        case "yes":
            stage = "working";
            error = "";
            dialog.visible = false;                // the polkit agent's window needs the keyboard

            restoreProc.command = ["pkexec", root.helper, String(root.number)];
            restoreProc.running = true;
            break;
        case "reboot":
            dialog.visible = false;
            Hyprland.dispatch("workstation_end_session(\"reboot\")");
            break;
        }
    }

    function handleKey(key) {
        const n = buttons.length;
        switch (key) {
        case Qt.Key_Left: case Qt.Key_Backtab: selected = (selected - 1 + n) % n; return true;
        case Qt.Key_Right: case Qt.Key_Tab:    selected = (selected + 1) % n; return true;
        case Qt.Key_Return: case Qt.Key_Enter: press(buttons[Math.min(selected, n - 1)].id); return true;
        case Qt.Key_Escape:                    press(buttons[0].id); return true;
        }
        return false;
    }

    // ---- detection (once) ---------------------------------------------------
    Process {
        running: true
        command: ["cat", "/proc/cmdline"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = root.parseCmdline(text);
                if (n < 0) return;
                root.number = n;
                infoProc.command = ["cat", "/.snapshots/" + n + "/info.xml"];
                infoProc.running = true;
            }
        }
    }

    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                const i = root.parseInfo(text);
                root.date = i.date;
                root.description = i.description;
                root.openDialog();
            }
        }
        onExited: code => {
            if (code !== 0) {
                Log.warn("snapshot", "info.xml of snapshot " + root.number + " not readable (exit " + code + ")");
                root.openDialog();
            }
        }
    }

    Process {
        id: restoreProc
        stdout: StdioCollector { id: restoreOut }
        stderr: StdioCollector { id: restoreErr }
        onExited: code => {
            let d = null;
            if (code === 0) {
                try { d = JSON.parse(restoreOut.text); } catch (e) { d = null; }
            }
            if (d && d.ok === true) {
                root.previous = d.previous || "";
                root.stage = "done";
                root.selected = 1;                 // Jetzt neu starten
            } else {
                root.error = code === 0 ? "The helper reported no result." : root.failure(code, restoreErr.text);
                root.stage = "failed";
                root.selected = 0;
                Log.warn("snapshot", "snapshot-restore failed (exit " + code + "): " + Log.firstLine(restoreErr.text));
            }
            dialog.visible = true;
        }
    }

    // ---- IPC "snapshotmode" (tests / diagnostics) ----------------------------
    IpcHandler {
        target: "snapshotmode"

        function open(): void {
            root.openDialog();
        }

        function close(): void {
            root.closeDialog();
        }

        // {active, number, date, description, visible, stage, selected, error, previous}
        function state(): string {
            return JSON.stringify({ active: root.active, number: root.number, date: root.date,
                                    description: root.description, visible: dialog.visible, stage: root.stage,
                                    selected: root.buttons[root.selected] ? root.buttons[root.selected].id : null,
                                    error: root.error, previous: root.previous });
        }
    }

    // ---- the strip: the whole session, every screen --------------------------
    Variants {
        model: root.active ? Quickshell.screens : []

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: Style.grow(26)
            color: Colors.accent
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-snapshotmode-strip"

            Text {
                anchors.centerIn: parent
                width: parent.width - 2 * Style.spacingLg
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: (root.stage === "done" ? "SNAPSHOT MODE - restored, reboot pending"
                       : root.stage === "working" ? "SNAPSHOT MODE - restoring: enter the administrator password in the authentication window"
                       : "SNAPSHOT MODE")
                      + "  ·  #" + root.number + (root.date ? "  " + root.date : "")
                      + (root.description ? "  " + root.description : "")
                      + "  ·  Normal system unchanged  ·  Click for options"
                color: Colors.accentForeground
                font.family: Fonts.family
                font.pixelSize: Style.secondary
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openDialog()
            }
        }
    }

    // ---- the dialog -----------------------------------------------------------
    PanelWindow {
        id: dialog

        // One transient surface at a time (bar/BarPopups.qml); every close path ends here.
        function closePopup() {
            root.closeDialog();
        }
        onVisibleChanged: {
            if (visible) {
                BarPopups.request(dialog);
                keys.forceActiveFocus();
            } else {
                BarPopups.release(dialog);
            }
        }

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
        WlrLayershell.namespace: "quickshell-snapshotmode"

        MouseArea {
            anchors.fill: parent
            onClicked: root.press(root.buttons[0].id)
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => event.accepted = root.handleKey(event.key)
        }

        DialogFrame {
            panelWidth: Style.widePanelWidth
            title: root.stage === "confirm" ? "Restore the snapshot permanently?"
                 : root.stage === "done" ? "Snapshot restored"
                 : root.stage === "failed" ? "Restore failed"
                 : "Snapshot mode"
            titleColor: root.stage === "failed" ? Colors.error : Colors.foregroundStrong

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Style.spacingLg
                rowSpacing: Style.spacingSm

                DialogText { Layout.fillWidth: false; kind: "detail"; color: Colors.foregroundMuted; text: "Snapshot" }
                DialogText { kind: "detail"; text: "#" + root.number }
                DialogText { Layout.fillWidth: false; kind: "detail"; color: Colors.foregroundMuted; text: "Taken" }
                DialogText { kind: "detail"; text: root.date || "unknown" }
                DialogText { Layout.fillWidth: false; kind: "detail"; color: Colors.foregroundMuted; text: "Description" }
                DialogText { kind: "detail"; text: root.description || "-" }
            }

            DialogText {
                visible: root.stage === "intro"
                kind: "detail"
                text: "REPO is running in the state this snapshot captured. The normal system is unchanged. "
                    + "Whatever you change on the system in this session is gone after the next reboot; "
                    + "package installs and updates are blocked here. Your files in /home are the normal ones."
            }
            DialogText {
                visible: root.stage === "intro"
                kind: "detail"
                color: Colors.foregroundMuted
                text: "Just test: keep working and check. A normal reboot returns to the previous system."
            }

            DialogText {
                visible: root.stage === "confirm" || root.stage === "working"
                kind: "detail"
                text: "REPO then boots permanently into this snapshot's state:\n"
                    + "•  The system (/, subvolume @) is replaced by snapshot #" + root.number + " - installed "
                    + "programs, system settings and /etc as they were then.\n"
                    + "•  The current system is kept as @broken-<date> (the way back; uses space until it is deleted).\n"
                    + "•  Unchanged: /home with your files and ~/.config, the logs (/var/log), the package cache.\n"
                    + "•  Changes made in this test session are not kept.\n"
                    + "•  A reboot is needed afterwards. The administrator password is requested."
            }

            DialogText {
                visible: root.stage === "done"
                kind: "detail"
                color: Colors.success
                text: "Snapshot #" + root.number + " is now the regular system - effective after the reboot. "
                    + "The previous system is kept as " + (root.previous || "@broken-<date>") + "."
            }

            DialogText {
                visible: root.stage === "failed"
                kind: "error"
                text: root.error + "\nThe system was not changed; you are still in snapshot mode."
            }

            DialogButtons {
                buttons: root.buttons
                selected: root.selected
                onPressed: id => { if (root.stage !== "working") root.press(id); }
            }
        }
    }
}
