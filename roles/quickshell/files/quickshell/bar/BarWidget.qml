// The common bar widget frame (RICE v1): one consistent hitbox, hover
// background, active / muted colors, "popup open" underline, tooltip, and
// the popup open/close protocol with the coordinator (BarPopups). Managed
// by Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// A widget is an icon slot (icon only, BarStyle.iconSlot wide) or an icon
// and/or label with BarStyle.textPadding on both sides. Widgets that need
// more (workspaces, tray) compose several frames or set their own content
// via `default` children and implicitWidth.
//
// The narrow interface to the bar: `bar` (Bar.qml) offers barHeight,
// screen, dragging, showTooltip(item, text)/hideTooltip(item) and
// openWidgetPopup(id). Nothing else.

import QtQuick
import qs

Item {
    id: root

    required property var bar

    property string icon: ""
    property string text: ""
    property string tooltip: ""
    property bool active: false          // accent: something is on/connected
    property bool muted: false           // dimmed: off / nothing happening
    property bool warning: false         // error color (e.g. battery low)
    property bool interactive: true
    property real fixedWidth: -1
    property color contentColor: warning ? Colors.error : active ? Colors.accent
                                : muted ? Colors.foregroundMuted : Colors.foregroundStrong

    // Popup protocol. A widget with a popup puts it in a Loader bound to
    // popupOpen; the coordinator makes sure only one is open.
    property bool popupOpen: false
    readonly property bool hovered: hover.hovered && !bar.dragging

    signal clicked(int button)
    signal scrolled(real delta)

    function openPopup() {
        if (popupOpen) return;
        BarPopups.request(root);
        popupOpen = true;
    }

    function closePopup() {
        if (!popupOpen) return;
        popupOpen = false;
        BarPopups.release(root);
    }

    function togglePopup() {
        if (popupOpen) closePopup();
        else openPopup();
    }

    Component.onDestruction: BarPopups.release(root)

    implicitHeight: bar.barHeight
    implicitWidth: fixedWidth > 0 ? fixedWidth
                 : text === "" ? BarStyle.iconSlot
                 : content.implicitWidth + 2 * BarStyle.textPadding

    // Hover background - inset, rounded, only while the pointer is here.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: BarStyle.hoverInset
        anchors.bottomMargin: BarStyle.hoverInset
        radius: BarStyle.hoverRadius
        color: Colors.surface
        visible: root.interactive && (root.hovered || root.popupOpen)
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: BarStyle.groupGap

        Text {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.contentColor
            font.family: Fonts.icons
            font.pixelSize: BarStyle.iconSize
        }

        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            textFormat: Text.PlainText
            color: root.contentColor
            font.family: Fonts.family
            font.pixelSize: BarStyle.textSize
        }
    }

    // "Popup open" mark on the edge facing the desktop.
    Rectangle {
        visible: root.popupOpen
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(10, Math.round(parent.width * 0.55))
        height: BarStyle.underlineHeight
        radius: height / 2
        color: Colors.accent
    }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered && root.tooltip !== "" && !root.popupOpen) root.bar.showTooltip(root, root.tooltip);
            else root.bar.hideTooltip(root);
        }
    }

    onTooltipChanged: if (hover.hovered) root.bar.showTooltip(root, root.tooltip)
    onPopupOpenChanged: if (popupOpen) root.bar.hideTooltip(root)

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.clicked(mouse.button)
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }
}
