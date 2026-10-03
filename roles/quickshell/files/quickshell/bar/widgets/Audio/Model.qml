// Bar widget "audio" - default output/input state (core). Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
// Quickshell.Services.Pipewire, event-driven. The trackers bind the
// default nodes so their volume/mute are live and settable; nothing here
// starts or configures PipeWire/WirePlumber (roles/audio owns them).

import QtQuick
import Quickshell.Services.Pipewire

Item {
    id: model

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property bool muted: ready && sink.audio.muted
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool micMuted: source !== null && source.ready && source.audio !== null && source.audio.muted

    readonly property string icon: !ready ? "\u{F0581}"                 // volume-off
        : muted ? "\u{F075F}"                                           // volume-mute
        : volume < 0.34 ? "\u{F057F}" : volume < 0.67 ? "\u{F0580}" : "\u{F057E}"

    function toggleMute() {
        if (ready) sink.audio.muted = !sink.audio.muted;
    }

    // Clamped to [0, 1]: no accidental boost past unity gain via a stray scroll.
    function step(delta) {
        if (ready) sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
    }

    PwObjectTracker {
        objects: [model.sink, model.source].filter(n => n !== null)
    }
}
