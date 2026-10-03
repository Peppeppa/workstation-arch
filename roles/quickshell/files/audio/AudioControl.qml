// FEATURE: audio_popup (see group_vars/all.yml audio_popup_enabled and
// docs/feature-architecture.md). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch. Loaded by Bar.qml only while
// the feature is enabled.
//
// Host for the audio popup (AudioPopup.qml, created only while open) -
// the bar's volume label stays core (left click mute, wheel volume); a
// right click on it calls open(). Its only own bar content is a
// microphone-muted icon, shown only while the default input is muted
// (e.g. after the mic-mute key). Quickshell's native PipeWire API,
// event-driven - no wpctl, no polling. PipeWire/WirePlumber stay owned
// by roles/audio.

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Item {
    id: control

    required property var bar

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source !== null && source.ready && source.audio.muted

    property bool popupOpen: false
    property real popupAnchorX: 0

    function open(item) {
        popupAnchorX = item.mapToItem(null, item.width / 2, 0).x;
        popupOpen = !popupOpen;
    }

    visible: micMuted
    implicitWidth: micMuted ? 18 : 0
    implicitHeight: bar.barHeight

    // Binds the default input so its mute state is live (same reason as
    // the default-sink tracker in shell.qml).
    PwObjectTracker {
        objects: control.source ? [control.source] : []
    }

    Text {
        anchors.centerIn: parent
        text: "\u{F036D}"           // microphone-off
        color: Colors.foregroundMuted
        font.family: Fonts.icons
        font.pixelSize: control.bar.fontSize + 1
    }

    MouseArea {
        anchors.fill: parent
        onClicked: control.open(control)
    }

    Loader {
        active: control.popupOpen
        sourceComponent: AudioPopup {
            screen: control.bar.screen
            anchorX: control.popupAnchorX
            barHeight: control.bar.barHeight
            fontSize: control.bar.fontSize
            onCloseRequested: control.popupOpen = false
        }
    }
}
