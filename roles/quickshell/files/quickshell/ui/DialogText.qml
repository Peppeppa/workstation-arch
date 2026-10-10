// A wrapped plain-text paragraph inside a DialogFrame (RICE v1 phase 3).
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. kind: body (the question), detail (secondary facts),
// hint (muted small print), error (a failure, error color).

import QtQuick
import QtQuick.Layouts
import qs

Text {
    property string kind: "body"

    Layout.fillWidth: true
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    color: kind === "error" ? Colors.error : kind === "hint" ? Colors.foregroundMuted : Colors.foreground
    font.family: Fonts.family
    font.pixelSize: kind === "body" ? Style.body : kind === "hint" ? Style.caption : Style.secondary
}
