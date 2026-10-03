// Core Desktop v1 app launcher. Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch.
//
// Replaces the previous temporary fuzzel launcher (see roles/hyprland):
// a small centered overlay, toggled by Hyprland's mainMod+Space bind
// via Quickshell's own IPC mechanism (`qs ipc call launcher toggle` -
// a one-shot CLI invocation per keypress, not a permanently running
// process or a second lifecycle owner for Quickshell itself).
//
// App data comes entirely from Quickshell's own native DesktopEntries
// singleton (XDG .desktop parsing built into Quickshell 0.3.1) - no
// hand-rolled .desktop parser, no external search process. Launching
// uses DesktopEntry.execute() directly, which is Quickshell's own
// supported way to run an entry's Exec= line (including any
// Terminal=true handling) - nothing here shells out itself.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

PanelWindow {
    id: launcher

    required property int fontSize

    readonly property int maxResults: 8

    property string query: ""
    property int selectedIndex: 0
    property var results: computeResults(query)
    onResultsChanged: selectedIndex = 0

    // No screen set on purpose: a layer-shell surface with no output
    // binding is placed by the compositor on whichever monitor is
    // currently focused - the right default for a single modal
    // overlay, and simpler than guessing which monitor to target.
    visible: false
    focusable: true
    color: "transparent"
    implicitWidth: 480
    implicitHeight: 360

    onVisibleChanged: {
        if (visible) {
            query = "";
            selectedIndex = 0;
            searchInput.forceActiveFocus();
        }
    }

    function computeResults(q) {
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        if (q.length === 0) {
            return apps.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, maxResults);
        }

        const needle = q.toLowerCase();
        const scored = [];
        for (const e of apps) {
            const name = (e.name || "").toLowerCase();
            const generic = (e.genericName || "").toLowerCase();
            const keywords = (e.keywords || []).join(" ").toLowerCase();
            let score = -1;
            if (name.startsWith(needle)) score = 0;
            else if (name.includes(needle)) score = 1;
            else if (generic.includes(needle)) score = 2;
            else if (keywords.includes(needle)) score = 3;
            if (score >= 0) scored.push({ entry: e, score: score });
        }
        scored.sort((a, b) => a.score - b.score || a.entry.name.localeCompare(b.entry.name));
        return scored.slice(0, maxResults).map(s => s.entry);
    }

    function launchSelected() {
        if (results.length === 0) return;
        const idx = Math.min(selectedIndex, results.length - 1);
        results[idx].execute();
        visible = false;
    }

    // IPC target "launcher" - called by Hyprland's mainMod+Space bind
    // (`qs ipc call launcher toggle`, see roles/hyprland). This is
    // Quickshell's own supported mechanism for a running instance to
    // react to an external keybind, not a second autostart/lifecycle
    // path: it does not spawn or own any process, it only flips this
    // already-running instance's own visibility.
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.visible = !launcher.visible;
        }

        function close(): void {
            launcher.visible = false;
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 460
        height: 340
        radius: 8
        color: Colors.background
        border.color: Colors.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: 4
                color: Colors.surface
                border.color: Colors.border
                border.width: 1

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Colors.text
                    font.family: Fonts.family
                    font.pixelSize: launcher.fontSize + 2
                    clip: true

                    text: launcher.query
                    onTextChanged: launcher.query = text

                    Keys.onDownPressed: launcher.selectedIndex = Math.min(launcher.selectedIndex + 1, launcher.results.length - 1)
                    Keys.onUpPressed: launcher.selectedIndex = Math.max(launcher.selectedIndex - 1, 0)
                    Keys.onReturnPressed: launcher.launchSelected()
                    Keys.onEnterPressed: launcher.launchSelected()
                    Keys.onEscapePressed: launcher.visible = false
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: launcher.results
                currentIndex: launcher.selectedIndex

                delegate: Rectangle {
                    id: resultDelegate
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 40
                    radius: 4
                    color: index === launcher.selectedIndex ? Colors.accent : "transparent"

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 0

                        Text {
                            text: resultDelegate.modelData.name
                            color: resultDelegate.index === launcher.selectedIndex ? Colors.accentText : Colors.text
                            font.family: Fonts.family
                            font.pixelSize: launcher.fontSize
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            visible: text.length > 0
                            text: resultDelegate.modelData.genericName
                            color: Colors.textMuted
                            font.family: Fonts.family
                            font.pixelSize: launcher.fontSize - 2
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            launcher.selectedIndex = resultDelegate.index;
                            launcher.launchSelected();
                        }
                    }
                }
            }
        }
    }
}
