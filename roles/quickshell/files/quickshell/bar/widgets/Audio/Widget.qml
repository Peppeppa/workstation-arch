// Bar widget "audio": volume icon + percent (core). Scroll = volume (5 %
// steps), right click = mute. Left click opens the audio popup (Popup.qml:
// devices, volume, mute, mic - audio_popup feature) or, without the
// feature, toggles mute. With the feature a mic-off glyph is appended while
// the default input is muted. Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch.

import QtQuick
import qs
import qs.bar

BarWidget {
    id: root

    Model {
        id: audio
    }

    icon: audio.icon
    text: (audio.ready ? Math.round(Math.min(1, audio.volume) * 100) + "%" : "--")
          + (BarFeatures.audioPopup && audio.micMuted ? "  \u{F036D}" : "")
    muted: audio.muted || !audio.ready
    onScrolled: delta => audio.step(delta > 0 ? 0.05 : -0.05)
    onClicked: button => {
        if (button === Qt.RightButton || (button === Qt.LeftButton && !BarFeatures.audioPopup)) audio.toggleMute();
        else if (button === Qt.LeftButton) root.togglePopup();
    }

    Loader {
        id: popupLoader
        active: root.popupOpen && BarFeatures.audioPopup
        Component.onCompleted: if (BarFeatures.audioPopup) setSource("Popup.qml", { owner: root })
    }

    Connections {
        target: popupLoader.item
        ignoreUnknownSignals: true
        function onCloseRequested() { root.closePopup(); }
    }
}
