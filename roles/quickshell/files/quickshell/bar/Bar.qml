// The bar host (RICE v1, modelled on Omarchy's bar engine - see
// docs/feature-architecture.md "Bar"). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. One instance per
// monitor (shell.qml's Variants).
//
// The bar itself shows nothing: it places the widgets of BarLayout's
// registry in three zones (left / center / right) and moves them around.
//   - every available widget is instantiated once per bar and positioned
//     absolutely from the layout (computePositions) - reordering never
//     recreates a widget, so an open popup or a running drag survives
//   - left zone grows rightwards from the left edge, right zone leftwards
//     from the right edge; in the center the clock is the anchor: it sits
//     at the exact geometric center, other center widgets flank it (no
//     clock in the center -> the center group is centered)
//   - drag & drop: a DragHandler per widget slot. Past a small threshold it
//     takes the pointer over from the widget (the widget's click is
//     cancelled, so a drag never clicks), the widget follows the pointer,
//     the drop place is outlined and the neighbours slide aside (preview =
//     the layout with the widget moved there). The drop is decided from
//     the pointer itself: Hyprland keeps delivering motion to the bar
//     (implicit pointer grab) while the button is held, even below it, so
//     the drag corridor reaches BarStyle.dragCorridor px below the visible
//     bar without any extra input surface. Release inside the corridor ->
//     BarLayout.move() (written to the user's layout file at once).
//     Further down the preview shows the old layout and the release
//     changes nothing.
//   - one tooltip popup per bar, shared by all widgets
//   - background: BarLayout.background - "solid" (theme background) or
//     "transparent" (only the widgets are drawn; no blur, no shadow)
// No process, no timer except the short one-shot settle timer of a drop.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.bar.widgets.Workspaces as Workspaces
import qs.bar.widgets.Clock as Clock
import qs.bar.widgets.Connectivity as Connectivity
import qs.bar.widgets.Audio as Audio
import qs.bar.widgets.Power as Power
import qs.bar.widgets.Coffee as Coffee
import qs.bar.widgets.Theme as Theme

PanelWindow {
    id: bar

    // Injected by shell.qml's Variants.
    property var modelData
    screen: modelData

    // ---- the narrow interface widgets use --------------------------------
    readonly property int barHeight: BarStyle.height
    readonly property bool dragging: dragId !== ""

    function showTooltip(target, text) {
        if (dragging || text === "") return;
        tooltip.target = target;
        tooltip.text = text;
    }

    function hideTooltip(target) {
        if (target === null || tooltip.target === target) tooltip.target = null;
    }

    // Open another widget's popup on this bar (e.g. Connectivity -> Bluetooth).
    function openWidgetPopup(id) {
        const slot = slots[id];
        if (slot && slot.widget && typeof slot.widget.openPopup === "function") slot.widget.openPopup();
    }

    // ---- window ----------------------------------------------------------
    anchors {
        top: true
        left: true
        right: true
    }
    // 3 anchors + ExclusionMode.Auto: the bar's height is reserved.
    implicitHeight: BarStyle.height
    color: BarLayout.background === "transparent" ? "transparent" : Colors.background

    // Coffee mode: a Wayland idle inhibitor on this (always visible) bar
    // surface while active (CoffeeMode.qml); any one bar is enough.
    IdleInhibitor {
        window: bar
        enabled: BarFeatures.coffee && CoffeeMode.active
    }

    // ---- layout engine ---------------------------------------------------
    readonly property string centerAnchor: "clock"

    property var slots: ({})            // widget id -> slot item

    function widthOf(id) {
        const slot = slots[id];
        return slot ? slot.slotWidth : 0;
    }

    function visibleIds(list) {
        return list.filter(id => widthOf(id) > 0);
    }

    // zones {left, center, right: [id]} -> {id: x}
    function computePositions(zones, totalWidth) {
        const pos = {};
        let x = BarStyle.edgeMargin;
        for (const id of visibleIds(zones.left)) {
            pos[id] = x;
            x += widthOf(id);
        }
        x = totalWidth - BarStyle.edgeMargin;
        const right = visibleIds(zones.right);
        for (let i = right.length - 1; i >= 0; i--) {
            x -= widthOf(right[i]);
            pos[right[i]] = x;
        }
        const center = visibleIds(zones.center);
        const a = center.indexOf(centerAnchor);
        if (a !== -1) {
            const ax = Math.round((totalWidth - widthOf(centerAnchor)) / 2);
            pos[centerAnchor] = ax;
            x = ax;
            for (let i = a - 1; i >= 0; i--) {
                x -= widthOf(center[i]);
                pos[center[i]] = x;
            }
            x = ax + widthOf(centerAnchor);
            for (let i = a + 1; i < center.length; i++) {
                pos[center[i]] = x;
                x += widthOf(center[i]);
            }
        } else {
            let total = 0;
            for (const id of center) total += widthOf(id);
            x = Math.round((totalWidth - total) / 2);
            for (const id of center) {
                pos[id] = x;
                x += widthOf(id);
            }
        }
        return pos;
    }

    function without(zones, id) {
        return {
            left: zones.left.filter(i => i !== id),
            center: zones.center.filter(i => i !== id),
            right: zones.right.filter(i => i !== id)
        };
    }

    // ---- drag state --------------------------------------------------------
    property string dragId: ""
    property real dragPointerX: 0
    property real dragPointerY: 0
    property real dragGrabOffset: 0
    property string dropZone: ""
    property int dropIndex: -1
    property bool animateMoves: false   // neighbours slide only around a drag

    // Pointer inside the drag corridor (the bar + BarStyle.dragCorridor px
    // below it)? Outside it a release cancels the drag.
    readonly property bool dropAllowed: dragPointerY <= height + BarStyle.dragCorridor

    // The layout as shown: during a drag, with the widget at its drop place.
    readonly property var previewZones: {
        const zones = BarLayout.zones;
        if (!dragging || dropZone === "" || !dropAllowed) return zones;
        const base = without(zones, dragId);
        const target = base[dropZone].slice();
        target.splice(dropIndex, 0, dragId);
        base[dropZone] = target;
        return base;
    }
    readonly property var positions: computePositions(previewZones, width)

    // Order matters: dragId first, while animations are still off, so the
    // drop outline (bound to positions[dragId], 0 without a drag) is
    // already at the widget before anything may animate - otherwise it
    // visibly shoots in from the left edge.
    function beginDrag(id, pressX, pressY) {
        BarPopups.closeAll();
        tooltip.target = null;
        dragGrabOffset = pressX - (positions[id] || 0);
        dragPointerX = pressX;
        dragPointerY = pressY;
        dragId = id;
        animateMoves = true;
        updateDrag(pressX, pressY);
    }

    // Drop place = the insertion (zone, index) whose resulting position of
    // the dragged widget is nearest to where the widget is held now. Each
    // candidate is laid out for real (computePositions) - comparing raw
    // insertion points is wrong in the right zone, which grows leftwards,
    // and made the widget swap with its neighbour right at drag start.
    // Candidates come from the layout without the dragged widget, so the
    // preview never feeds back into the hit test; with no movement the
    // widget's own slot wins (distance 0).
    function updateDrag(pointerX, pointerY) {
        if (!dragging) return;
        dragPointerX = pointerX;
        dragPointerY = pointerY;
        const base = without(BarLayout.zones, dragId);
        const held = pointerX - dragGrabOffset;
        let best = null;
        for (const zone of BarLayout.zoneNames) {
            for (let index = 0; index <= base[zone].length; index++) {
                const candidate = {
                    left: base.left.slice(),
                    center: base.center.slice(),
                    right: base.right.slice()
                };
                candidate[zone].splice(index, 0, dragId);
                const d = Math.abs(computePositions(candidate, width)[dragId] - held);
                if (best === null || d < best.d) best = { d: d, zone: zone, index: index };
            }
        }
        dropZone = best ? best.zone : "";
        dropIndex = best ? best.index : -1;
    }

    function endDrag() {
        if (dragging) finishDrop(dropAllowed);
    }

    function finishDrop(commit) {
        if (commit && dropZone !== "") {
            const base = without(BarLayout.zones, dragId);
            const beforeId = dropIndex < base[dropZone].length ? base[dropZone][dropIndex] : "";
            BarLayout.move(dragId, dropZone, beforeId);
        }
        dragId = "";
        dropZone = "";
        dropIndex = -1;
        settleTimer.restart();
    }

    // Let the dropped widget and its neighbours slide into place, then stop
    // animating (no animation outside a drag).
    Timer {
        id: settleTimer
        interval: BarStyle.moveDuration + 80
        onTriggered: bar.animateMoves = false
    }

    // Drop place: outlined where the dragged widget will land. Only its
    // moves during a drag animate - never its first placement.
    Rectangle {
        id: dropOutline
        visible: bar.dragging && bar.dropZone !== "" && bar.dropAllowed
        x: bar.positions[bar.dragId] !== undefined ? bar.positions[bar.dragId] : 0
        y: BarStyle.hoverInset - 1
        width: bar.widthOf(bar.dragId)
        height: bar.height - 2 * (BarStyle.hoverInset - 1)
        radius: BarStyle.hoverRadius
        color: "transparent"
        border.color: Colors.accent
        border.width: 1
        Behavior on x {
            enabled: bar.animateMoves && dropOutline.visible
            NumberAnimation { duration: BarStyle.moveDuration; easing.type: Easing.OutCubic }
        }
    }

    // ---- widget slots ------------------------------------------------------
    // Core widgets (always deployed); feature widgets come by path.
    // (barWindow, not bar: inside a widget, `bar` is its own property.)
    readonly property var barWindow: bar
    readonly property var coreWidgets: ({
        workspaces: workspacesWidget,
        clock: clockWidget,
        connectivity: connectivityWidget,
        audio: audioWidget,
        power: powerWidget,
        coffee: coffeeWidget,
        theme: themeWidget
    })
    Component { id: workspacesWidget; Workspaces.Widget { bar: barWindow } }
    Component { id: clockWidget; Clock.Widget { bar: barWindow } }
    Component { id: connectivityWidget; Connectivity.Widget { bar: barWindow } }
    Component { id: audioWidget; Audio.Widget { bar: barWindow } }
    Component { id: powerWidget; Power.Widget { bar: barWindow } }
    Component { id: coffeeWidget; Coffee.Widget { bar: barWindow } }
    Component { id: themeWidget; Theme.Widget { bar: barWindow } }

    Repeater {
        model: BarLayout.availableWidgets

        Item {
            id: slot

            required property var modelData
            readonly property string widgetId: modelData.id
            readonly property bool placed: BarLayout.isPlaced(widgetId)
            readonly property var widget: loader.item
            readonly property real slotWidth: placed && widget && widget.visible ? widget.implicitWidth : 0
            readonly property bool lifted: bar.dragId === widgetId

            x: lifted ? bar.dragPointerX - bar.dragGrabOffset
                      : (bar.positions[widgetId] !== undefined ? bar.positions[widgetId] : 0)
            z: lifted ? 10 : 0
            width: slotWidth
            height: bar.height
            // Not bound to slotWidth: a hidden widget (visible: false) simply
            // has width 0 here; making the slot invisible would make the
            // widget report itself invisible forever.

            Behavior on x {
                enabled: bar.animateMoves && !slot.lifted
                NumberAnimation { duration: BarStyle.moveDuration; easing.type: Easing.OutCubic }
            }

            // Lifted look: the widget on a raised plate.
            Rectangle {
                visible: slot.lifted
                anchors.fill: parent
                anchors.topMargin: BarStyle.hoverInset - 1
                anchors.bottomMargin: BarStyle.hoverInset - 1
                radius: BarStyle.hoverRadius
                color: Colors.surface
                border.color: Colors.borderActive
                border.width: 1
            }

            Loader {
                id: loader
                height: bar.height
                active: slot.placed
                opacity: slot.lifted ? 0.9 : 1
                sourceComponent: bar.coreWidgets[slot.widgetId] || null
                Component.onCompleted: if (slot.modelData.path) setSource(slot.modelData.path, { bar: bar })
            }

            DragHandler {
                id: drag
                target: null
                acceptedButtons: Qt.LeftButton
                dragThreshold: BarStyle.dragThreshold
                onActiveChanged: {
                    if (active) bar.beginDrag(slot.widgetId, centroid.scenePressPosition.x, centroid.scenePressPosition.y);
                    else bar.endDrag();
                }
                onTranslationChanged: if (active) bar.updateDrag(centroid.scenePosition.x, centroid.scenePosition.y)
            }

            Component.onCompleted: {
                const next = Object.assign({}, bar.slots);
                next[widgetId] = slot;
                bar.slots = next;
            }
            Component.onDestruction: {
                if (bar.dragId === widgetId) bar.finishDrop(false);
            }
        }
    }

    // ---- shared tooltip ----------------------------------------------------
    PopupWindow {
        id: tooltip

        property Item target: null
        property string text: ""

        visible: target !== null && text !== "" && !bar.dragging
        anchor.item: target
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: BarStyle.popupGap
        color: "transparent"
        implicitWidth: tipText.implicitWidth + 16
        implicitHeight: tipText.implicitHeight + 10

        Rectangle {
            anchors.fill: parent
            radius: BarStyle.hoverRadius
            color: Colors.background
            border.color: Colors.border
            border.width: 1

            Text {
                id: tipText
                anchors.centerIn: parent
                text: tooltip.text
                textFormat: Text.PlainText
                color: Colors.foreground
                font.family: Fonts.family
                font.pixelSize: BarStyle.tooltipFontSize
            }
        }
    }
}
