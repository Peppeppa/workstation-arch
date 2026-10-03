// FEATURE: audio_popup - bar widget "audio", its popup: output/input
// devices, default selection, volume and mute. Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// A BarPopup (click outside / Escape closes, exists only while open).
// Everything through
// Quickshell.Services.Pipewire: choosing a device sets
// Pipewire.preferredDefaultAudioSink/Source (WirePlumber stores the
// choice like any other client's), volume/mute write the default nodes'
// PwNodeAudio. Volumes are clamped to [0, 1] like the bar's wheel.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.bar

BarPopup {
    id: popup

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // Hardware devices only (no application streams).
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var inputs: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)


    function nodeLabel(n) {
        return n.description || n.nickname || n.name;
    }

    // Live volume/mute of both defaults while the popup is open.
    PwObjectTracker {
        objects: [popup.sink, popup.source].filter(n => n !== null)
    }

    component SectionTitle: Text {
        Layout.topMargin: 6
        color: Colors.foregroundMuted
        font.family: Fonts.family
        font.pixelSize: popup.fontSize - 2
    }

    // Mute button + volume bar for one default node.
    component VolumeRow: RowLayout {
        id: vrow
        required property var node
        required property string icon
        required property string mutedIcon
        readonly property bool live: node !== null && node.ready && node.audio !== null
        readonly property bool muted: live && node.audio.muted
        readonly property real volume: live ? Math.min(1, node.audio.volume) : 0

        function setVolume(v) {
            if (live) node.audio.volume = Math.max(0, Math.min(1, v));
        }

        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            implicitWidth: 28
            implicitHeight: 24
            radius: 4
            color: muteMouse.containsMouse ? Colors.surface : "transparent"

            Text {
                anchors.centerIn: parent
                text: vrow.muted ? vrow.mutedIcon : vrow.icon
                color: vrow.muted ? Colors.foregroundMuted : Colors.foreground
                font.family: Fonts.icons
                font.pixelSize: popup.fontSize + 2
            }

            MouseArea {
                id: muteMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: if (vrow.live) vrow.node.audio.muted = !vrow.node.audio.muted
            }
        }

        Item {
            Layout.fillWidth: true
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
                    width: track.width * vrow.volume
                    height: parent.height
                    radius: 3
                    color: vrow.muted ? Colors.foregroundMuted : Colors.accent
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: vrow.live
                onPressed: mouse => vrow.setVolume(mouse.x / width)
                onPositionChanged: mouse => { if (pressed) vrow.setVolume(mouse.x / width); }
                onWheel: wheel => vrow.setVolume(vrow.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
            }
        }

        Text {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: vrow.live ? Math.round(vrow.volume * 100) + "%" : "--"
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
        }
    }

    // One selectable device; the current default is highlighted.
    component DeviceRow: Rectangle {
        id: drow
        required property var modelData
        required property bool isDefault
        signal chosen

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 4
        color: isDefault ? Colors.accent : rowMouse.containsMouse ? Colors.surface : "transparent"

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            text: popup.nodeLabel(drow.modelData)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: drow.isDefault ? Colors.accentForeground : Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: drow.chosen()
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4

        Text {
            text: "Audio"
            color: Colors.foreground
            font.family: Fonts.family
            font.pixelSize: popup.fontSize + 1
            font.bold: true
        }

        SectionTitle { text: "Output" }

        VolumeRow {
            node: popup.sink
            icon: "\u{F057E}"          // volume-high
            mutedIcon: "\u{F075F}"     // volume-mute
        }

        Repeater {
            model: popup.outputs
            delegate: DeviceRow {
                isDefault: popup.sink === modelData
                onChosen: Pipewire.preferredDefaultAudioSink = modelData
            }
        }

        Text {
            visible: popup.outputs.length === 0
            text: "No output devices"
            color: Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
        }

        SectionTitle { text: "Input" }

        VolumeRow {
            node: popup.source
            icon: "\u{F036C}"          // microphone
            mutedIcon: "\u{F036D}"     // microphone-off
        }

        Repeater {
            model: popup.inputs
            delegate: DeviceRow {
                isDefault: popup.source === modelData
                onChosen: Pipewire.preferredDefaultAudioSource = modelData
            }
        }

        Text {
            visible: popup.inputs.length === 0
            text: "No input devices"
            color: Colors.foregroundMuted
            font.family: Fonts.family
            font.pixelSize: popup.fontSize - 1
        }
    }
}
