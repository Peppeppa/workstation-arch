// Bar widget "updates": shown only while at least one official package update
// is pending (any update counts, no "major" classification), dimmed while the
// check fails but the last good result had updates, accent while an update
// runs. Tooltip: count + names. Click: the updater dialog (the same one as
// power menu -> Update). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch. Deployed only with recovery_enabled.

import QtQuick
import qs.bar
import qs.updates

BarWidget {
    id: root

    visible: Updates.iconVisible
    icon: "\u{F06B0}"                       // update
    active: Updates.updating
    muted: !Updates.updating && Updates.status !== "ok"
    tooltip: Updates.tooltip
    onClicked: button => { if (button === Qt.LeftButton) Updates.openDialog(); }
}
