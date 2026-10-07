// Bar widget "scratchpad": the quick-notes icon. Click toggles the
// Scratchpad window (scratchpad/ScratchpadWindow.qml); accent while it is
// open. Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.

import QtQuick
import qs
import qs.bar

BarWidget {
    id: root

    icon: "\u{F11D7}"                       // note-text-outline
    active: Scratchpad.open
    onClicked: button => { if (button === Qt.LeftButton) Scratchpad.toggle(); }
}
