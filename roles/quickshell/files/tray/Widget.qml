// FEATURE: tray - bar widget "tray" (see group_vars/all.yml tray_enabled
// and docs/feature-architecture.md). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. Only deployed while the
// feature is enabled; with the feature off the bar never loads it and
// Quickshell never becomes a StatusNotifierWatcher/host.
//
// Quickshell 0.3.1's native StatusNotifier support (SystemTray) is the
// tray host: discovery is event-driven over D-Bus, no polling. Each item
// shows its own icon (pixmap or theme name - resolved by Quickshell);
// nothing here knows about specific applications.
//   left click   -> activate()   (or the menu for menu-only items)
//   middle click -> secondaryActivate()
//   right click  -> context menu (DBusMenu, rendered by Menu.qml)
//   wheel        -> scroll(delta, horizontal)
// Passive items are hidden (StatusNotifierItem semantics). With no visible
// item the widget is invisible and takes no space. The context menu is
// this widget's popup (one at a time, via BarPopups).
//
// Collapsible: at rest only a small "<" handle shows. Hovering the widget
// slides the icons out to the LEFT of the handle (width + fade, an
// animation only while it changes); leaving collapses them again. The
// hover area is the whole widget (handle + revealed icons), so moving from
// the handle onto an icon never collapses it; an open context menu keeps
// it expanded. In the right zone (default) the right edge stays put, so
// the handle does not move under the pointer.

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs
import qs.bar

Item {
    id: tray

    required property var bar

    readonly property var shown: SystemTray.items.values.filter(i => i.status !== Status.Passive)
    property var menuItem: null          // the item whose context menu is open
    property Item menuEntry: null        // its icon slot (popup anchor)
    readonly property bool popupOpen: menuItem !== null

    function openMenu(item, entry) {
        BarPopups.request(tray);
        menuItem = null;              // re-create the menu for another item
        menuEntry = entry;
        menuItem = item;
    }

    // BarPopups protocol.
    function closePopup() {
        if (menuItem === null) return;
        menuItem = null;
        BarPopups.release(tray);
    }

    Component.onDestruction: BarPopups.release(tray)

    readonly property bool expanded: (trayHover.hovered && !bar.dragging) || popupOpen
    property real reveal: expanded ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: BarStyle.revealDuration; easing.type: Easing.OutCubic } }

    visible: shown.length > 0
    implicitWidth: Math.round(row.implicitWidth * reveal) + handle.width
    implicitHeight: bar.barHeight

    HoverHandler {
        id: trayHover
    }

    // The collapsed icons: clipped to the revealed width, right-aligned so
    // they slide in from the handle towards the left.
    Item {
        id: strip
        anchors.right: handle.left
        width: Math.round(row.implicitWidth * tray.reveal)
        height: parent.height
        clip: true
        opacity: tray.reveal
        visible: tray.reveal > 0

        Row {
            id: row
            anchors.right: parent.right
            height: parent.height

            Repeater {
                model: tray.shown

                Item {
                    id: entry

                    required property var modelData
                    readonly property bool hovered: hover.hovered && !tray.bar.dragging

                    width: 24
                    height: tray.bar.barHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: BarStyle.hoverInset
                        anchors.bottomMargin: BarStyle.hoverInset
                        radius: BarStyle.hoverRadius
                        color: Colors.surface
                        visible: entry.hovered || tray.menuItem === entry.modelData
                    }

                    Image {
                        anchors.centerIn: parent
                        width: BarStyle.trayIconSize
                        height: BarStyle.trayIconSize
                        sourceSize.width: BarStyle.trayIconSize
                        sourceSize.height: BarStyle.trayIconSize
                        source: entry.modelData.icon
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Rectangle {
                        visible: tray.menuItem === entry.modelData
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 12
                        height: BarStyle.underlineHeight
                        radius: height / 2
                        color: Colors.accent
                    }

                    HoverHandler {
                        id: hover
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: event => {
                            const item = entry.modelData;
                            if (event.button === Qt.MiddleButton)
                                item.secondaryActivate();
                            else if (event.button === Qt.RightButton || item.onlyMenu) {
                                if (item.hasMenu) tray.openMenu(item, entry);
                            } else
                                item.activate();
                        }
                        onWheel: event => {
                            const horizontal = event.angleDelta.x !== 0;
                            entry.modelData.scroll(horizontal ? event.angleDelta.x : event.angleDelta.y, horizontal);
                        }
                    }
                }
            }
        }
    }

    Text {
        id: handle
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(BarStyle.iconSlot * 0.6)
        horizontalAlignment: Text.AlignHCenter
        text: "\u{F0141}"                  // chevron-left: the icons open to the left
        color: tray.expanded ? Colors.foregroundStrong : Colors.foregroundMuted
        font.family: Fonts.icons
        font.pixelSize: BarStyle.iconSize
    }

    // Loaded by path (feature widget): its own files by relative path too.
    // The source is cleared when the menu closes: left set, re-activating
    // the Loader first re-created Menu.qml from it WITHOUT the properties
    // (owner/item null - TypeError in BarPopup) before setSource ran.
    Loader {
        id: menuLoader
        active: tray.menuItem !== null && tray.menuEntry !== null
        onActiveChanged: {
            if (active) setSource("Menu.qml", { owner: tray.menuEntry, ownerBar: tray.bar, item: tray.menuItem });
            else source = "";
        }
    }

    Connections {
        target: menuLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested() { tray.closePopup(); }
    }

    Connections {
        target: SystemTray.items
        function onValuesChanged() {
            if (tray.menuItem !== null && !SystemTray.items.values.includes(tray.menuItem))
                tray.closePopup();
        }
    }
}
