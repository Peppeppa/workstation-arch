// A 0..1 level slider (track + fill), the look of the audio popup's volume
// row. Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. Neutral building block: owned by neither the bar nor
// the Appearance window. Emits `moved(v)` on press/drag/wheel; the owner
// decides what the value means.

import QtQuick
import qs

Item {
    id: slider

    property real value: 0
    property bool enabled: true
    signal moved(real v)

    function clamp(v) {
        return Math.max(0, Math.min(1, v));
    }

    implicitHeight: 24

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Colors.surface
        border.color: Colors.border
        border.width: 1

        Rectangle {
            width: track.width * slider.clamp(slider.value)
            height: parent.height
            radius: 3
            color: slider.enabled ? Colors.accent : Colors.foregroundMuted
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: slider.enabled
        onPressed: mouse => slider.moved(slider.clamp(mouse.x / width))
        onPositionChanged: mouse => { if (pressed) slider.moved(slider.clamp(mouse.x / width)); }
        onWheel: wheel => slider.moved(slider.clamp(slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
    }
}
