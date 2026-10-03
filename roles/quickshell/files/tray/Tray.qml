// FEATURE: tray (see group_vars/all.yml tray_enabled and
// docs/feature-architecture.md). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Only deployed while the
// feature is enabled; Bar.qml loads it through a Loader, so with the
// feature off nothing here is instantiated and Quickshell never becomes
// a StatusNotifierWatcher/host.
//
// Quickshell 0.3.1's native StatusNotifier support (SystemTray) is the
// tray host: discovery is event-driven over D-Bus, no polling. Each item
// shows its own icon (pixmap or theme name - resolved by Quickshell);
// nothing here knows about specific applications.
//   left click   -> activate()   (or the menu for menu-only items)
//   middle click -> secondaryActivate()
//   right click  -> context menu (DBusMenu, rendered by TrayMenu.qml)
//   wheel        -> scroll(delta, horizontal)
// Passive items are hidden (StatusNotifierItem semantics). With no
// visible item the whole zone is invisible and takes no space.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

RowLayout {
    id: tray

    required property var bar

    readonly property var shown: SystemTray.items.values.filter(i => i.status !== Status.Passive)
    property var menuItem: null          // the item whose context menu is open
    property real menuAnchorX: 0

    visible: shown.length > 0
    spacing: 4

    function openMenu(item, delegate) {
        menuAnchorX = delegate.mapToItem(null, delegate.width / 2, 0).x;
        menuItem = item;
    }

    Repeater {
        model: tray.shown

        Item {
            id: entry

            required property var modelData

            implicitWidth: 22
            implicitHeight: tray.bar.barHeight

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                sourceSize.width: 16
                sourceSize.height: 16
                source: entry.modelData.icon
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
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

            // Tooltip: the item's own tooltip title (or its title).
            PopupWindow {
                id: tooltip
                readonly property string label: entry.modelData.tooltipTitle || entry.modelData.title || ""

                visible: mouse.containsMouse && label !== "" && tray.menuItem === null
                anchor.item: entry
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                anchor.margins.top: 4
                color: "transparent"
                implicitWidth: tip.implicitWidth + 16
                implicitHeight: tip.implicitHeight + 10

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: Colors.background
                    border.color: Colors.border
                    border.width: 1

                    Text {
                        id: tip
                        anchors.centerIn: parent
                        text: tooltip.label
                        textFormat: Text.PlainText
                        color: Colors.foreground
                        font.family: Fonts.family
                        font.pixelSize: tray.bar.fontSize - 1
                    }
                }
            }
        }
    }

    // Context menu: only exists while open (zero cost otherwise).
    Loader {
        active: tray.menuItem !== null
        sourceComponent: TrayMenu {
            screen: tray.bar.screen
            item: tray.menuItem
            anchorX: tray.menuAnchorX
            barHeight: tray.bar.barHeight
            fontSize: tray.bar.fontSize
            onCloseRequested: tray.menuItem = null
        }
    }

    // An item that disappears while its menu is open closes the menu.
    Connections {
        target: SystemTray.items
        function onValuesChanged() {
            if (tray.menuItem !== null && !SystemTray.items.values.includes(tray.menuItem))
                tray.menuItem = null;
        }
    }
}
