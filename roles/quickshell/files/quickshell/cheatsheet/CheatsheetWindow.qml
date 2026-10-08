// Cheatsheet - two Markdown documents (Hyprland keybindings, Neovim/
// LazyVim/VimTeX) in one viewer window. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. See
// docs/feature-architecture.md "Cheatsheet".
//
// The documents are plain Markdown files deployed by Ansible (roles/hyprland
// renders hyprland.md from the same settings as the binds, roles/apps ships
// neovim.md) into ~/.local/share/workstation/cheatsheets/ and read fresh on
// every open. Rendering is Qt's own Markdown import (TextEdit MarkdownText,
// read-only): headings, GitHub tables as real tables, inline code, bold,
// lists - no parser of ours, no WebEngine. The rendered document's plain
// text (getText) maps 1:1 to document positions, so search runs on what is
// shown (no Markdown syntax) and a hit inside a table cell is selected and
// scrolled to exactly.
//
// Like the scratchpad: a normal top-level window (title
// "workstation-cheatsheet"; Hyprland's window rule in roles/hyprland
// appearance.lua floats and centers it) that EXISTS only while open
// (LazyLoader). Close: mainMod+T again (IPC "cheatsheet"), Escape with no
// search, the x button, Super+Q (the compositor closes it), focus lost to
// another window, a click on free desktop (Bottom-layer catcher, only while
// open), or another shell popup (BarPopups). No global grab, no timer, no
// polling.
//
// Keys (vim-like, three states):
//   normal   Tab other document, j/k scroll, / search, n/N next/previous
//            hit (while hits are shown), Escape: hits shown -> clear them,
//            else close
//   input    the search field has the keyboard: every key is text (j, k, n
//            too), Tab does nothing, Enter = search (first hit selected
//            and scrolled into view; no hit -> a hint, the field stays),
//            Escape = cancel (query and hits cleared, window stays)
//   results  = normal with the hits marked (all outlined, the current one
//            selected); n wraps from the last to the first

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.bar

Scope {
    id: root

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                  + "/workstation/cheatsheets"
    readonly property var docs: [
        { title: "Hyprland", file: "hyprland.md" },
        { title: "Neovim", file: "neovim.md" }
    ]

    property int tab: 0                     // the document shown (0 = Hyprland on every open)
    property var scrollY: [0, 0]            // per document, kept while the shell runs
    property bool closing: false

    // ---- pure logic (tests/qml-logic.qml) ------------------------------------
    // Start positions of every case-insensitive occurrence of query in text,
    // non-overlapping. If lower-casing changed the length (rare Unicode),
    // positions would no longer map to the document: then case-sensitive.
    function findMatches(text, query) {
        if (query === "") return [];
        let t = text.toLowerCase(), q = query.toLowerCase();
        if (t.length !== text.length || q.length !== query.length) {
            t = text;
            q = query;
        }
        const out = [];
        for (let i = t.indexOf(q); i >= 0; i = t.indexOf(q, i + q.length)) out.push(i);
        return out;
    }

    // The hit after (step 1) / before (step -1) the current one, wrapping.
    function nextIndex(current, count, step) {
        if (count === 0) return -1;
        if (current < 0) return step > 0 ? 0 : count - 1;
        return (current + step + count) % count;
    }

    // ---- open / close ------------------------------------------------------
    function toggle() {
        if (loader.active) close();
        else open();
    }

    function open() {
        if (loader.active) return;
        tab = 0;
        BarPopups.request(root);
        loader.active = true;
    }

    function close() {
        if (!loader.active || closing) return;
        closing = true;
        if (loader.item) loader.item.rememberScroll();
        loader.active = false;
        BarPopups.release(root);
        closing = false;
    }

    // The shell's one-transient-surface coordinator (bar/BarPopups.qml).
    function closePopup() {
        close();
    }

    // ---- the window (only while open) ----------------------------------------
    LazyLoader {
        id: loader
        active: false

        FloatingWindow {
            id: win

            property bool seenActive: false     // focus-loss closing only after it had focus
            property string mode: "normal"      // normal | input | results
            property string query: ""
            property var matches: []            // document positions
            property int current: -1
            property var boxes: []              // outline rectangles of all hits
            property bool noHits: false
            readonly property int matchLength: query.length
            // read-only views for the IPC state (tests)
            readonly property string selected: view.selectedText
            readonly property real scrollPos: flick.contentY
            readonly property real maxScroll: Math.max(0, flick.contentHeight - flick.height)

            // The focused output's logical size (the window is placed there).
            readonly property var outputScreen: {
                const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
                const s = Quickshell.screens.find(x => x.name === name);
                return s || Quickshell.screens[0];
            }

            title: "workstation-cheatsheet"
            visible: true
            color: Colors.background
            // Compact, always inside the output (scale already applied).
            implicitWidth: Math.min(Fonts.px(820), outputScreen.width - 80)
            implicitHeight: Math.min(Fonts.px(700), outputScreen.height - 120)

            // The compositor closed it (Super+Q).
            onVisibleChanged: if (!visible) root.close()

            function load(i) {
                clearSearch();
                root.tab = i;
                view.text = files.objectAt(i).text();
                flick.contentY = 0;
                // the saved position once the new text is laid out
                Qt.callLater(() => { flick.contentY = Math.min(root.scrollY[i], win.maxScroll); });
                view.forceActiveFocus();
            }

            function rememberScroll() {
                const y = root.scrollY.slice();
                y[root.tab] = flick.contentY;
                root.scrollY = y;
            }

            function switchTab() {
                rememberScroll();
                load(1 - root.tab);
            }

            function scrollBy(dy) {
                flick.contentY = Math.max(0, Math.min(maxScroll, flick.contentY + dy));
            }

            // ---- search ----
            function startSearch() {
                mode = "input";
                noHits = false;
                field.text = query;
                field.selectAll();
                field.forceActiveFocus();
            }

            function runSearch() {
                const q = field.text;
                if (q === "") {
                    cancelSearch();
                    return;
                }
                query = q;
                matches = root.findMatches(view.getText(0, view.length), q);
                if (matches.length === 0) {
                    noHits = true;                  // hint; the field keeps the keyboard
                    boxes = [];
                    view.deselect();
                    return;
                }
                noHits = false;
                mode = "results";
                current = -1;
                updateBoxes();
                step(1);
                view.forceActiveFocus();
            }

            function step(dir) {
                current = root.nextIndex(current, matches.length, dir);
                if (current < 0) return;
                const p = matches[current];
                view.select(p, p + matchLength);
                const r = view.positionToRectangle(p);
                // Into view with some context above (only if not visible).
                if (r.y < flick.contentY || r.y + r.height > flick.contentY + flick.height)
                    flick.contentY = Math.max(0, Math.min(maxScroll, r.y - flick.height / 3));
            }

            function updateBoxes() {
                const b = [];
                for (const p of matches) {
                    const a = view.positionToRectangle(p);
                    const e = view.positionToRectangle(p + matchLength);
                    const w = e.y === a.y ? e.x - a.x : view.width - a.x;   // wrapped hit: to the line end
                    b.push({ x: a.x - 1, y: a.y, w: w + 2, h: a.height });
                }
                boxes = b;
            }

            function clearSearch() {
                mode = "normal";
                query = "";
                matches = [];
                boxes = [];
                current = -1;
                noHits = false;
                view.deselect();
            }

            function cancelSearch() {
                clearSearch();
                view.forceActiveFocus();
            }

            // The documents, read fresh each time the window opens.
            Instantiator {
                id: files
                model: root.docs
                delegate: FileView {
                    required property var modelData
                    path: root.dir + "/" + modelData.file
                    blockLoading: true
                }
            }

            Component.onCompleted: load(0)

            // Focus lost to another window closes, like the scratchpad.
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

                // ---- tabs + close ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: root.docs

                        Rectangle {
                            id: tabItem
                            required property var modelData
                            required property int index
                            readonly property bool current: index === root.tab
                            implicitWidth: tabLabel.implicitWidth + Fonts.px(24)
                            implicitHeight: Fonts.px(28)
                            radius: 4
                            color: current ? Colors.surface : tabMouse.containsMouse ? Colors.surface : "transparent"
                            border.color: current ? Colors.borderActive : "transparent"
                            border.width: 1

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: tabItem.modelData.title
                                color: tabItem.current ? Colors.accent : Colors.foreground
                                font.family: Fonts.family
                                font.pixelSize: Fonts.px(13)
                                font.bold: tabItem.current
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!tabItem.current) win.switchTab()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    PopupButton {
                        label: "\u{F0156}"              // close
                        fontSize: Fonts.px(13)
                        onClicked: root.close()
                    }
                }

                // ---- the document ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: Colors.surface
                    border.color: Colors.border
                    border.width: 1
                    clip: true

                    Flickable {
                        id: flick
                        anchors.fill: parent
                        anchors.margins: 12
                        contentWidth: width
                        contentHeight: view.height
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        TextEdit {
                            id: view
                            width: flick.width
                            height: Math.max(contentHeight, flick.height)
                            readOnly: true
                            persistentSelection: true
                            selectByMouse: false
                            selectByKeyboard: false
                            cursorVisible: false
                            activeFocusOnPress: false
                            textFormat: TextEdit.MarkdownText
                            wrapMode: TextEdit.Wrap
                            color: Colors.foreground
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.accentForeground
                            font.family: Fonts.family
                            font.pixelSize: Fonts.px(13)
                            onWidthChanged: if (win.matches.length > 0) win.updateBoxes()

                            // Every hit outlined; the current one is the selection.
                            Repeater {
                                model: win.boxes

                                Rectangle {
                                    required property var modelData
                                    x: modelData.x
                                    y: modelData.y
                                    width: modelData.w
                                    height: modelData.h
                                    color: "transparent"
                                    border.color: Colors.accent
                                    border.width: 1
                                    radius: 2
                                }
                            }

                            Keys.onPressed: event => {
                                const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
                                const step = Fonts.px(64);
                                if (event.key === Qt.Key_Escape) {
                                    if (win.mode !== "normal") win.cancelSearch();
                                    else root.close();
                                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) win.switchTab();
                                else if (!plain) return;
                                else if (event.text === "j") win.scrollBy(step);
                                else if (event.text === "k") win.scrollBy(-step);
                                else if (event.text === "/") win.startSearch();
                                else if (event.text === "n" && win.mode === "results") win.step(1);
                                else if (event.text === "N" && win.mode === "results") win.step(-1);
                                else return;
                                event.accepted = true;
                            }
                        }
                    }

                    // Thin scroll indicator (only when the document is longer than the view).
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
                }

                // ---- search line / key hint ----
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Fonts.px(26)

                    RowLayout {
                        anchors.fill: parent
                        visible: win.mode !== "normal"
                        spacing: 6

                        Text {
                            text: "/"
                            color: Colors.accent
                            font.family: Fonts.family
                            font.pixelSize: Fonts.px(13)
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 4
                            color: Colors.surface
                            border.color: win.noHits ? Colors.error : field.activeFocus ? Colors.borderActive : Colors.border
                            border.width: 1

                            TextInput {
                                id: field
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                verticalAlignment: TextInput.AlignVCenter
                                readOnly: win.mode !== "input"
                                color: Colors.foreground
                                selectionColor: Colors.accent
                                selectedTextColor: Colors.accentForeground
                                font.family: Fonts.family
                                font.pixelSize: Fonts.px(13)
                                clip: true
                                onTextEdited: win.noHits = false
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) win.cancelSearch();
                                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.runSearch();
                                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {}   // no document switch while typing
                                    else return;
                                    event.accepted = true;
                                }
                            }
                        }

                        Text {
                            text: win.noHits ? "no match"
                                : win.mode === "results" ? (win.current + 1) + " / " + win.matches.length
                                : "Enter search · Esc cancel"
                            color: win.noHits ? Colors.error : Colors.foregroundMuted
                            font.family: Fonts.family
                            font.pixelSize: Fonts.px(12)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.mode === "normal"
                        text: "Tab document · j/k scroll · / search · Esc close"
                        color: Colors.foregroundMuted
                        font.family: Fonts.family
                        font.pixelSize: Fonts.px(12)
                    }
                }
            }
        }
    }

    // A click on free desktop (no other window takes the focus there) also
    // closes: a transparent full-screen surface on the Bottom layer - above
    // the wallpaper, below every window and the bar - only while open.
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
        WlrLayershell.namespace: "quickshell-cheatsheet-catcher"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // IPC "cheatsheet": the toggle (mainMod+T) and a read-only state for tests.
    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.toggle();
        }

        function close(): void {
            root.close();
        }

        // {open, tab, mode, query, matches, current, selected, scrollY, maxScrollY}
        function state(): string {
            const w = loader.item;
            if (!w) return JSON.stringify({ open: false, tab: root.tab });
            return JSON.stringify({ open: true, tab: root.tab, document: root.docs[root.tab].title,
                                    mode: w.mode, query: w.query, noHits: w.noHits,
                                    matches: w.matches.length, current: w.current + 1,
                                    selected: w.selected, scrollY: Math.round(w.scrollPos),
                                    maxScrollY: Math.round(w.maxScroll),
                                    width: w.width, height: w.height });
        }
    }
}
