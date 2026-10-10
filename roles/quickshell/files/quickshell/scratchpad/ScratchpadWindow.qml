// Scratchpad / quick notes (phase 1). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. See
// docs/feature-architecture.md "Scratchpad".
//
// Four fixed plain-text notes, one editable at a time, stored together in
// ONE Markdown file: Scratchpad.file (~/Documents/.system/scratchpad.md -
// ~/Documents is the Nextcloud folder synced to /2_Dokumente; the Nextcloud
// client alone syncs it, this works the same without it). Each note starts
// with an invisible marker line `<!-- scratchpad note N -->` (parseNotes /
// composeNotes; text above the first marker or a file without markers counts
// as note 1). Migrated once from the former 1.txt ... 4.txt by the bootstrap
// (roles/quickshell scratchpad-migrate.py - the old files stay). The window is
// a normal top-level window (title "workstation-scratchpad"): Hyprland's
// window rule (roles/hyprland appearance.lua) floats it top right and pins
// it; Super+Q closes it like any window (the shell keeps running). It EXISTS
// only while open (LazyLoader): a window the compositor has closed cannot be
// shown again, and closed it costs nothing. Notes, the current note and the
// font size live in the Scope, outside it. Toggle: mainMod+S or the bar icon
// (IPC "scratchpad").
//
// Editing: no wrapping (long lines scroll sideways), Enter = new line.
// Alt+1..4 or the dots pick a note; -/+ (or Ctrl+-/Ctrl++) set the notes'
// font size (0 = follow the desktop text size). Escape, a click elsewhere
// (focus lost to another window, or a click on free desktop - a
// transparent catcher on the Bottom layer, under every window, only while
// open), the toggle, Super+Q and another shell popup close it.
//
// Saving: a 400 ms single-shot timer after a change (nothing runs while
// nothing changes), and always before a note switch and on every close
// path; FileView writes atomically (temp file + rename). Last note + font
// size: Scratchpad.stateFile (local, not synced).
//
// External changes (Nextcloud, another editor): the file is watched
// (FileView watchChanges = inotify, no polling) and re-read on every open.
// A changed file whose content differs from what this shell last read or
// wrote is taken over - unless the open note has unsaved typing: then that
// local version is first written to a conflict copy next to the file
// ("scratchpad (Konflikt <date time>).md"), the file's content is taken over
// and the window says where the local version is. Nothing is overwritten
// silently; conflict copies (ours or Nextcloud's) are never touched again.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar

Scope {
    id: root

    readonly property int noteCount: 4
    readonly property int minFontSize: 8
    readonly property int maxFontSize: 32

    property int note: 0                    // 0..3
    property int fontSize: 0                // 0 = the desktop's (Fonts.px(13))
    readonly property int effectiveFontSize: fontSize > 0 ? fontSize : Fonts.px(13)
    property var notes: ["", "", "", ""]    // the four notes (memory copy of the file)
    property string baseline: ""             // the file content last read or written by us
    property string notice: ""               // conflict / save problem, shown in the window
    readonly property bool visible: loader.active
    property bool closing: false

    // ---- open / close ------------------------------------------------------
    function toggle() {
        if (loader.active) close();
        else open();
    }

    function open() {
        if (loader.active) return;
        notice = "";
        store.reload();                     // the current file (onLoaded adopts it)
        BarPopups.request(root);
        loader.active = true;
    }

    // Every way the window goes away ends here: save, then destroy it.
    function close() {
        if (!loader.active || closing) return;
        closing = true;
        if (loader.item) loader.item.flush();
        loader.active = false;
        BarPopups.release(root);
        closing = false;
    }

    // The shell's one-transient-surface coordinator (bar/BarPopups.qml).
    function closePopup() {
        close();
    }

    // ---- notes + state -----------------------------------------------------
    readonly property var markerRe: /^<!-- scratchpad note ([1-9]) -->$/

    // File text -> [note 1, ..., note count]. Pure (tests). A note's text is
    // everything between its marker line and the next marker line, without
    // the one newline that separates them; text before the first marker (or
    // a file without markers) belongs to note 1.
    function parseNotes(text, count) {
        const out = [];
        for (let i = 0; i < count; i++) out.push("");
        const lines = text.split("\n");
        if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();   // the final newline
        let cur = 0, buf = [], started = false;
        const commit = () => {
            const t = buf.join("\n");
            out[cur] = out[cur] === "" ? t : t === "" ? out[cur] : out[cur] + "\n" + t;
        };
        for (const line of lines) {
            const m = markerRe.exec(line);
            if (m && Number(m[1]) >= 1 && Number(m[1]) <= count) {
                if (started || buf.length > 0) commit();
                cur = Number(m[1]) - 1;
                buf = [];
                started = true;
            } else {
                buf.push(line);
            }
        }
        if (started || buf.length > 0) commit();
        return out;
    }

    // [notes] -> file text: "<marker 1>\n" + note 1 + "\n" + "<marker 2>\n" ...
    function composeNotes(list) {
        return list.map((t, i) => "<!-- scratchpad note " + (i + 1) + " -->\n" + t + "\n").join("");
    }

    function saveNote(i, text) {
        notes[i] = text;
        writeFile();
    }

    function writeFile() {
        const text = composeNotes(notes);
        if (text === baseline) return;
        baseline = text;                    // our own write must not look external
        store.setText(text);
    }

    // The file changed on disk to `text`: take it over, or - with unsaved
    // typing in the open note - keep that typing in a conflict copy first.
    function adoptFile(text) {
        if (text === baseline) return;
        const w = loader.item;
        if (w && w.dirty) {
            const local = notes.slice();
            local[note] = w.currentText();
            const d = new Date();
            const stamp = Qt.formatDateTime(d, "yyyy-MM-dd HHmmss");
            conflictView.path = Scratchpad.dir + "/scratchpad (Konflikt " + stamp + ").md";
            conflictView.setText(composeNotes(local));
            notice = "Die Datei wurde außerhalb geändert (z. B. Nextcloud). Deine ungespeicherte Version liegt in "
                     + "\"scratchpad (Konflikt " + stamp + ").md\" daneben.";
            Log.warn("scratchpad", "external change while editing - local version kept in a conflict copy");
        }
        baseline = text;
        notes = parseNotes(text, noteCount);
        if (w) {
            w.dirty = false;                // the pending save must not write the old typing back
            w.showNote();
        }
    }

    function setFontSize(px) {
        fontSize = Math.max(minFontSize, Math.min(maxFontSize, px));
        saveState();
    }

    function saveState() {
        stateView.setText(JSON.stringify({ note: note + 1, fontSize: fontSize }) + "\n");
    }

    // The one file: read once blocking at startup, then watched (inotify).
    FileView {
        id: store
        path: Scratchpad.file
        blockLoading: true
        printErrors: false                  // no file yet = four empty notes
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.adoptFile(text())
        onSaveFailed: error => {
            root.notice = "Speichern fehlgeschlagen (" + error + ") - Ordner " + Scratchpad.dir + " vorhanden?";
            root.baseline = "";             // retry on the next change
            Log.warn("scratchpad", "cannot save " + path + ": " + error);
        }
    }

    // Conflict copies only (path set when one is needed).
    FileView {
        id: conflictView
        printErrors: false
        atomicWrites: true
        onSaveFailed: error => Log.warn("scratchpad", "cannot write the conflict copy: " + error)
    }

    FileView {
        id: stateView
        path: Scratchpad.stateFile
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    Component.onCompleted: {
        baseline = store.text();
        notes = parseNotes(baseline, noteCount);
        try {
            const s = JSON.parse(stateView.text() || "{}");
            if (s.note >= 1 && s.note <= noteCount) note = s.note - 1;
            if (s.fontSize >= minFontSize && s.fontSize <= maxFontSize) fontSize = s.fontSize;
        } catch (e) {
            Log.warn("scratchpad", "state file unreadable - using defaults");
        }
        Scratchpad.window = root;
    }
    Component.onDestruction: if (loader.item) loader.item.flush()

    // ---- the window (only while open) ----------------------------------------
    LazyLoader {
        id: loader
        active: false

        FloatingWindow {
            id: win

            property bool dirty: false
            property bool seenActive: false     // focus-loss closing only after it had focus
            readonly property int textLength: editor.text.length

            title: "workstation-scratchpad"
            visible: true
            color: Colors.background
            implicitWidth: Fonts.px(560)
            implicitHeight: Fonts.px(380)

            // The compositor closed it (Super+Q): save and drop it.
            onVisibleChanged: if (!visible) root.close()

            function showNote() {
                editor.loading = true;
                editor.text = root.notes[root.note];
                editor.loading = false;
                editor.cursorPosition = editor.text.length;
                flick.contentX = 0;
                editor.forceActiveFocus();
            }

            function switchNote(n) {
                if (n === root.note || n < 0 || n >= root.noteCount) return;
                flush();
                root.note = n;
                root.saveState();
                showNote();
            }

            function currentText() {
                return editor.text;
            }

            function flush() {
                saveTimer.stop();
                if (!dirty) return;
                root.saveNote(root.note, editor.text);
                dirty = false;
            }

            Component.onCompleted: showNote()

            Timer {
                id: saveTimer
                interval: 400
                onTriggered: win.flush()
            }

            // Focus lost to another window closes, like the shell's popups.
            Item {
                readonly property bool windowActive: Window.active
                onWindowActiveChanged: {
                    if (windowActive) win.seenActive = true;
                    else if (win.seenActive) root.close();
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // Conflict / save problem (until the next open).
                Text {
                    visible: root.notice !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.notice
                    color: Colors.error
                    font.family: Fonts.family
                    font.pixelSize: Fonts.px(11)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: Colors.surface
                    border.color: editor.activeFocus ? Colors.borderActive : Colors.border
                    border.width: 1
                    clip: true

                    Flickable {
                        id: flick
                        anchors.fill: parent
                        anchors.margins: 6
                        contentWidth: Math.max(editor.contentWidth + 8, width)
                        contentHeight: Math.max(editor.contentHeight, height)
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        function ensureVisible(r) {
                            if (contentX >= r.x) contentX = r.x;
                            else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width + 2;
                            if (contentY >= r.y) contentY = r.y;
                            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
                        }

                        TextEdit {
                            id: editor
                            property bool loading: false
                            width: Math.max(contentWidth, flick.width)
                            height: Math.max(contentHeight, flick.height)
                            wrapMode: TextEdit.NoWrap
                            textFormat: TextEdit.PlainText
                            selectByMouse: true
                                                        color: Colors.foreground
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.accentForeground
                            font.family: Fonts.family
                            font.pixelSize: root.effectiveFontSize
                            onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                            onTextChanged: {
                                if (loading) return;
                                win.dirty = true;
                                saveTimer.restart();
                            }

                            Keys.onPressed: event => {
                                const alt = event.modifiers & Qt.AltModifier;
                                const ctrl = event.modifiers & Qt.ControlModifier;
                                if (event.key === Qt.Key_Escape) root.close();
                                else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) win.switchNote(event.key - Qt.Key_1);
                                else if (ctrl && event.key === Qt.Key_Minus) root.setFontSize(root.effectiveFontSize - 1);
                                else if (ctrl && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) root.setFontSize(root.effectiveFontSize + 1);
                                else return;
                                event.accepted = true;
                            }
                        }
                    }

                    // Thin scroll indicators (only when the note is bigger than the view).
                    Rectangle {
                        visible: flick.contentHeight > flick.height
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        y: 2 + (parent.height - 4 - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
                        width: 3
                        height: Math.max(16, (parent.height - 4) * flick.height / flick.contentHeight)
                        radius: 1.5
                        color: Colors.border
                    }
                    Rectangle {
                        visible: flick.contentWidth > flick.width
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        x: 2 + (parent.width - 4 - width) * (flick.contentX / Math.max(1, flick.contentWidth - flick.width))
                        height: 3
                        width: Math.max(16, (parent.width - 4) * flick.width / flick.contentWidth)
                        radius: 1.5
                        color: Colors.border
                    }
                }

                // Bottom: the four notes (dots), font size (- +).
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Fonts.px(22)

                    Row {
                        anchors.centerIn: parent
                        spacing: Fonts.px(10)

                        Repeater {
                            model: root.noteCount

                            Rectangle {
                                id: dot
                                required property int index
                                readonly property bool current: index === root.note
                                width: Fonts.px(10)
                                height: width
                                radius: width / 2
                                color: current ? Colors.accent : dotMouse.containsMouse ? Colors.surface : "transparent"
                                border.color: current ? Colors.accent : Colors.foregroundMuted
                                border.width: 1

                                MouseArea {
                                    id: dotMouse
                                    anchors.fill: parent
                                    anchors.margins: -Fonts.px(5)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.switchNote(dot.index)
                                }
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        PopupButton {
                            label: "−"
                            fontSize: Fonts.px(12)
                            opacity: root.effectiveFontSize > root.minFontSize ? 1 : 0.5
                            onClicked: { root.setFontSize(root.effectiveFontSize - 1); editor.forceActiveFocus(); }
                        }
                        PopupButton {
                            label: "+"
                            fontSize: Fonts.px(12)
                            opacity: root.effectiveFontSize < root.maxFontSize ? 1 : 0.5
                            onClicked: { root.setFontSize(root.effectiveFontSize + 1); editor.forceActiveFocus(); }
                        }
                    }
                }
            }
        }
    }

    // A click on free desktop (no other window takes the focus there) also
    // closes, like the shell's popups: a transparent full-screen surface on
    // the Bottom layer - above the wallpaper, below every window and the
    // bar - that exists only while the scratchpad is open.
    PanelWindow {
        visible: loader.active
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell-scratchpad-catcher"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // IPC "scratchpad": the toggle (mainMod+S) and a read-only state for tests.
    IpcHandler {
        target: "scratchpad"

        function toggle(): void {
            root.toggle();
        }

        function close(): void {
            root.close();
        }

        // {open, note (1-4), fontSize, effectiveFontSize, dirty, length, file, lengths, notice}
        function state(): string {
            const w = loader.item;
            return JSON.stringify({ open: loader.active, note: root.note + 1, fontSize: root.fontSize,
                                    effectiveFontSize: root.effectiveFontSize,
                                    dirty: w ? w.dirty : false,
                                    length: w ? w.textLength : root.notes[root.note].length,
                                    file: Scratchpad.file, lengths: root.notes.map(n => n.length),
                                    notice: root.notice });
        }
    }
}
