// The common bar popup (RICE v1): every widget popup is one of these.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.
//
// Same overlay pattern as before, now in one place: while open, a
// transparent layer surface covers the bar's output - a click outside the
// panel or Escape closes it; it is created by the owner's Loader only while
// open, so a closed popup leaves no surface and no input region behind.
// The bar strip itself is left out of the input region: a click on another
// bar widget reaches it directly (and switches popups in one click).
// The panel opens below its widget (centered on it, kept on screen), with
// one width/padding/border/radius for all popups.
//
// Content: ONE child item, sized to the panel width (anchors.left/right:
// parent.left/right). Optional keyFilter(event) -> true when the popup
// handled a key itself (e.g. Escape closing a dialog inside the popup).

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
    id: popup

    required property Item owner          // the widget (or part of it) the popup opens below
    property var ownerBar: owner.bar      // the Bar it sits in
    property int panelWidth: BarStyle.popupWidth
    property int fontSize: BarStyle.popupFontSize
    readonly property int barHeight: BarStyle.height
    property var keyFilter: null
    property real maxPanelHeight: height - barHeight - 2 * BarStyle.popupGap - 8
    default property alias content: body.data

    // Where the widget's center is (bar coordinates), taken when opening.
    property real anchorX: 0

    signal closeRequested

    screen: ownerBar.screen
    visible: true
    focusable: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
        item: inputArea
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-popup"

    Component.onCompleted: {
        anchorX = owner.mapToItem(null, owner.width / 2, 0).x;
        keyHandler.forceActiveFocus();
    }

    // Everything below the bar: the input region (see mask).
    Item {
        id: inputArea
        y: popup.barHeight
        width: popup.width
        height: popup.height - popup.barHeight
    }

    MouseArea {
        anchors.fill: parent
        onClicked: popup.closeRequested()
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (popup.keyFilter && popup.keyFilter(event)) {
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                popup.closeRequested();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        id: panel

        x: Math.round(Math.max(6, Math.min(popup.anchorX - width / 2, popup.width - width - 6)))
        y: popup.barHeight + BarStyle.popupGap
        width: popup.panelWidth
        height: Math.min(body.childrenRect.height + 2 * BarStyle.popupPadding, popup.maxPanelHeight)
        radius: BarStyle.popupRadius
        color: Colors.background
        border.color: Colors.borderActive
        border.width: 1
        clip: true

        // Clicks on the panel never reach the close area underneath.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: BarStyle.popupPadding
        }
    }
}
