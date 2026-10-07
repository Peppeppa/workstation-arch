// Scratchpad / quick notes (phase 1). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. See
// docs/feature-architecture.md "Scratchpad".
//
// Four fixed plain-text notes, one editable at a time - plain UTF-8 files
// <Scratchpad.dataDir>/1.txt ... 4.txt (~/.local/share/workstation/
// scratchpad). The window is a normal top-level window (title
// "workstation-scratchpad"): Hyprland's window rule (roles/hyprland
// appearance.lua) floats it top right and pins it; Super+Q closes it like
// any window (the shell keeps running). It EXISTS only while open
// (LazyLoader): a window the compositor has closed cannot be shown again,
// and closed it costs nothing. Notes, the current note and the font size
// live in the Scope, outside it. Toggle: mainMod+N or the bar icon (IPC
// "scratchpad").
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
// path; FileView writes atomically. The files are read once when the
// shell starts - changes made to them from outside while it runs are not
// picked up (phase 2). Last note + font size: Scratchpad.stateFile.

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
    property var notes: ["", "", "", ""]    // what is in the files (memory copy)
    readonly property bool visible: loader.active
    property bool closing: false

    // ---- open / close ------------------------------------------------------
    function toggle() {
        if (loader.active) close();
        else open();
    }

    function open() {
        if (loader.active) return;
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
    function saveNote(i, text) {
        notes[i] = text;
        files.objectAt(i).setText(text);
    }

    function setFontSize(px) {
        fontSize = Math.max(minFontSize, Math.min(maxFontSize, px));
        saveState();
    }

    function saveState() {
        stateView.setText(JSON.stringify({ note: note + 1, fontSize: fontSize }) + "\n");
    }

    // The four files, read once at startup (blocking - small text files).
    Instantiator {
        id: files
        model: root.noteCount
        delegate: FileView {
            required property int index
            path: Scratchpad.dataDir + "/" + (index + 1) + ".txt"
            blockLoading: true
            printErrors: false             // a note never written yet is just empty
            atomicWrites: true
        }
        onObjectAdded: (i, view) => { root.notes[i] = view.text(); }
    }

    FileView {
        id: stateView
        path: Scratchpad.stateFile
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    Component.onCompleted: {
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

    // IPC "scratchpad": the toggle (mainMod+N) and a read-only state for tests.
    IpcHandler {
        target: "scratchpad"

        function toggle(): void {
            root.toggle();
        }

        function close(): void {
            root.close();
        }

        // {open, note (1-4), fontSize, effectiveFontSize, dirty, length}
        function state(): string {
            const w = loader.item;
            return JSON.stringify({ open: loader.active, note: root.note + 1, fontSize: root.fontSize,
                                    effectiveFontSize: root.effectiveFontSize,
                                    dirty: w ? w.dirty : false,
                                    length: w ? w.textLength : root.notes[root.note].length });
        }
    }
}
