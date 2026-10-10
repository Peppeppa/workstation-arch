// The updater dialog (OS menu -> System -> Update, the bar's update icon - both call
// Updates.openDialog(), one dialog). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Deployed only with the host
// capability recovery_enabled. See docs/feature-architecture.md "System
// updates".
//
// It asks; system-update (roles/recovery) does the transaction:
//   1 check (Updates.check) -> count + package names
//   2 "Update the system?"  No (preselected) / Yes
//   3 Yes: system-update --ui in the terminal, as a transient user unit
//     (`systemd-run --user --unit=workstation-system-update`) - sudo, the
//     pre-update snapshot (recovery slot), the interactive `pacman -Syu`, the
//     checks and the result all happen there. The dialog closes (the terminal
//     needs the keyboard); closing it never stops the update - the unit is not
//     Quickshell's child. A second start is refused (unit already active +
//     system-update's own lock).
//   4 snapshot failed (system-update exit 3, IPC snapshotFailed): pacman did
//     NOT run. Second question "Snapshot failed. Continue with the update
//     anyway?" No (preselected; also Escape / click outside) /
//     Yes = system-update --ui --no-snapshot. Only this failure has a "go on
//     anyway": preflight (pacman lock, space, boot state), sudo, health and
//     pacman errors end the run in the terminal, no second chance here.
//   5 finished (IPC finished <code> <snapshot>): the result stays in the
//     terminal; here the bar is refreshed and the next opening shows it.
// The dialog offers buttons only - no free text reaches a command.
//
// Keys: Left/Right/Tab move between the buttons, Enter presses the selected
// one, Escape = No/close. Pointer hover never changes the selection.

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
    required property var terminal             // argv of the terminal (hyprland_terminal)

    // checking | confirm | none | checkFailed | snapshotFailed | busy | startFailed
    property string stage: "checking"
    property string detail: ""                 // error text of the current stage
    property var lastResult: null              // {code, snapshot, at} of the last finished update
    property int selected: 0                   // index into buttons
    property bool starting: false

    readonly property var buttons: {
        switch (stage) {
        case "confirm":        return [{ id: "no", label: "No" }, { id: "yes", label: "Yes" }];
        case "snapshotFailed": return [{ id: "no", label: "No (recommended)" }, { id: "yesNoSnapshot", label: "Yes", danger: true }];
        case "checkFailed":    return [{ id: "close", label: "Close" }, { id: "recheck", label: "Check again" }];
        case "checking":       return [{ id: "close", label: "Cancel" }];
        default:               return [{ id: "close", label: "Close" }];
        }
    }

    // The safe choice of each stage (preselected, Escape, click outside).
    function cancelIndex() {
        return 0;
    }

    function open() {
        Updates.syncUnit();
        selected = 0;
        detail = "";
        if (Updates.updating) stage = "busy";
        else {
            stage = "checking";
            Updates.check();
            if (!Updates.checking) settle();       // nothing started (already up to date in memory)
        }
        visible = true;
    }

    function close() {
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

    // The check is done: which question follows.
    function settle() {
        if (stage !== "checking") return;
        if (Updates.updating) stage = "busy";
        else if (Updates.status === "ok") stage = Updates.count > 0 ? "confirm" : "none";
        else {
            stage = "checkFailed";
            detail = Updates.status === "offline" ? "No internet connection: " + Updates.message : Updates.message;
        }
        selected = 0;
    }

    Connections {
        target: Updates
        function onCheckingChanged() {
            if (!Updates.checking) dlg.settle();
        }
        function onUpdatingChanged() {
            if (Updates.updating && dlg.stage !== "snapshotFailed") dlg.stage = "busy";
            else if (!Updates.updating && dlg.stage === "busy") {
                dlg.stage = "checking";                // the terminal is gone: check again
                Updates.check();
            }
        }
    }

    function press(id) {
        switch (id) {
        case "yes":           launch(false); break;
        case "yesNoSnapshot": launch(true); break;
        case "recheck":       stage = "checking"; Updates.check(); if (!Updates.checking) settle(); break;
        default:              close(); break;            // no / close / cancel
        }
    }

    // system-update in the terminal, detached from Quickshell (its own unit).
    function launch(noSnapshot) {
        if (starting || Updates.updating) return;
        starting = true;
        const args = ["/usr/local/bin/system-update", "--ui"].concat(noSnapshot ? ["--no-snapshot"] : []);
        launcher.command = ["systemd-run", "--user", "--quiet", "--collect",
                            "--unit=" + Updates.unit.replace(/\.service$/, ""), "--"]
                           .concat(dlg.terminal, ["-e"], args);
        launcher.running = true;
    }

    Process {
        id: launcher
        stderr: StdioCollector { id: launchErr }
        onExited: code => {
            dlg.starting = false;
            if (code === 0) {
                Updates.updating = true;
                dlg.close();
            } else {
                dlg.stage = "startFailed";
                dlg.detail = /already (loaded|exists)/.test(launchErr.text)
                    ? "A system update is already running."
                    : "Could not start the terminal: " + Log.firstLine(launchErr.text);
                dlg.selected = 0;
                Log.warn("updates", "starting system-update failed (exit " + code + "): " + Log.firstLine(launchErr.text));
            }
        }
    }

    function handleKey(key, modifiers) {
        const n = buttons.length;
        switch (key) {
        case Qt.Key_Left: case Qt.Key_Backtab: selected = (selected - 1 + n) % n; return true;
        case Qt.Key_Right: case Qt.Key_Tab:    selected = (selected + 1) % n; return true;
        case Qt.Key_Return: case Qt.Key_Enter: press(buttons[Math.min(selected, n - 1)].id); return true;
        case Qt.Key_Escape:                    press(buttons[cancelIndex()].id); return true;
        }
        return false;
    }

    function resultText(r) {
        if (!r) return "";
        const when = Qt.formatTime(r.at, "HH:mm");
        const snap = r.snapshot === "none" ? "WITHOUT a new pre-update snapshot" : "pre-update snapshot " + r.snapshot;
        return "Last update (" + when + "): " + (r.code === 0 ? "succeeded" : "FAILED (exit " + r.code + ")") + ", " + snap + ".";
    }

    // ---- IPC "updates" ------------------------------------------------------
    // open/close/state for the user and tests; snapshotFailed/finished are
    // system-update --ui's reports. None of them runs anything by itself.
    IpcHandler {
        target: "updates"

        function open(): void {
            dlg.open();
        }

        function close(): void {
            dlg.close();
        }

        // {visible, stage, selected, buttons, detail, status, count, packages, updating, lastResult}
        function state(): string {
            return JSON.stringify({ visible: dlg.visible, stage: dlg.stage, selected: dlg.buttons[dlg.selected] ? dlg.buttons[dlg.selected].id : null,
                                    buttons: dlg.buttons.map(b => b.id), detail: dlg.detail,
                                    status: Updates.status, count: Updates.count, packages: Updates.packages.map(p => p.name),
                                    iconVisible: Updates.iconVisible, updating: Updates.updating, lastResult: dlg.lastResult });
        }

        // Re-run the check now (the bar icon follows).
        function check(): void {
            Updates.check();
        }

        // system-update --ui: the pre-update snapshot failed, pacman did not run.
        function snapshotFailed(message: string): void {
            Updates.updating = false;
            dlg.stage = "snapshotFailed";
            dlg.detail = message;
            dlg.selected = 0;                      // No
            dlg.visible = true;
        }

        // system-update --ui ended: exit code, snapshot number or "none".
        function finished(code: int, snapshot: string): void {
            dlg.lastResult = { code: code, snapshot: snapshot, at: new Date() };
            Updates.updating = false;
            Updates.check();
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
    WlrLayershell.namespace: "quickshell-updater"

    MouseArea {
        anchors.fill: parent
        onClicked: dlg.press(dlg.buttons[dlg.cancelIndex()].id)
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => event.accepted = dlg.handleKey(event.key, event.modifiers)
    }

    DialogFrame {
        title: dlg.stage === "snapshotFailed" ? "Snapshot failed" : "System update"
        titleColor: dlg.stage === "snapshotFailed" ? Colors.error : Colors.foreground

        DialogText {
            text: {
                switch (dlg.stage) {
                case "checking":       return "Checking for updates …";
                case "confirm":        return (Updates.count === 1 ? "1 update available" : Updates.count + " updates available")
                                              + " (official Arch repositories). Update the system?";
                case "none":           return "The system is up to date - no updates from the official repositories.";
                case "checkFailed":    return "The update check failed.";
                case "busy":           return "A system update is running in the terminal window.";
                case "startFailed":    return "The update was not started.";
                case "snapshotFailed": return "The pre-update snapshot could not be created. Nothing was updated.\n\nContinue with the update anyway?";
                }
                return "";
            }
        }

        // Package list (confirm only), scrolls past ~12 rows.
        Rectangle {
            visible: dlg.stage === "confirm"
            Layout.fillWidth: true
            implicitHeight: Math.min(list.contentHeight, Math.ceil(Style.caption * 1.6) * 12) + 2 * Style.spacingSm
            radius: Style.controlRadius
            color: Colors.surface

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Style.spacingSm
                clip: true
                model: dlg.stage === "confirm" ? Updates.packages : []
                delegate: Text {
                    required property var modelData
                    width: list.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: modelData.name + "  " + modelData.from + " → " + modelData.to
                    color: Colors.foreground
                    font.family: Fonts.family
                    font.pixelSize: Style.caption
                }
            }
        }

        DialogText {
            visible: dlg.detail !== ""
            kind: "error"
            text: dlg.detail
        }

        DialogText {
            visible: dlg.stage === "snapshotFailed"
            kind: "hint"
            text: "Yes updates WITHOUT a new snapshot (recorded in the journal: journalctl -t system-update). \"Recovery: before the last update\" then stays the state before an earlier update."
        }

        DialogText {
            visible: dlg.stage === "confirm"
            kind: "hint"
            text: "Yes opens the terminal: sudo password, snapshot before the update, then pacman -Syu (interactive). No automatic reboot."
        }

        DialogText {
            visible: dlg.lastResult !== null && dlg.stage !== "snapshotFailed"
            kind: dlg.lastResult && dlg.lastResult.code !== 0 ? "error" : "hint"
            text: dlg.resultText(dlg.lastResult)
        }

        DialogButtons {
            buttons: dlg.buttons.map(b => ({ id: b.id, danger: b.danger,
                                             label: dlg.starting && b.id.startsWith("yes") ? "…" : b.label }))
            selected: dlg.selected
            onPressed: id => dlg.press(id)
        }
    }

    Component.onCompleted: Updates.dialog = dlg
}
