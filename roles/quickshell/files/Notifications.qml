// FEATURE: notifications (see group_vars/all.yml notifications_enabled
// and docs/feature-architecture.md). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. Only deployed (and
// only instantiated by shell.qml) while the feature is enabled.
//
// The desktop's one notification daemon: Quickshell's own
// NotificationServer owns org.freedesktop.Notifications inside the
// already-running Quickshell process (mako is retired, see
// roles/desktop). v1 is toasts only - no history, no center, no sound,
// nothing persisted.
//
// Toasts stack top-right below the bar, newest on top, at most
// maxVisible shown (older ones wait, still counting down). Normal/low
// urgency expire after the sender's timeout or defaultTimeoutMs; hovering
// a toast pauses its countdown. Critical ones stay until closed. Click a
// toast (or its x) to close it. Bodies are rendered as plain text - no
// markup, links or remote images from senders. Timers exist only per
// visible toast; with no notifications the window is unmapped.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

Scope {
    id: root

    required property int fontSize

    readonly property int defaultTimeoutMs: 5000
    readonly property int maxVisible: 5

    NotificationServer {
        id: server

        // Tell senders what v1 actually renders.
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: false
        imageSupported: true
        persistenceSupported: false
        keepOnReload: false

        onNotification: notification => notification.tracked = true
    }

    PanelWindow {
        id: toastWindow

        readonly property int count: server.trackedNotifications.values.length

        visible: count > 0
        anchors {
            top: true
            right: true
        }
        margins {
            top: 8
            right: 8
        }
        // Normal: two-edge anchored surface without own exclusive zone,
        // so the compositor places it below the bar's.
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "quickshell-notifications"
        color: "transparent"
        implicitWidth: 360
        implicitHeight: stack.implicitHeight

        // GridLayout with one column so each toast can pick its row:
        // newest (last in the model) on top, without rebuilding
        // delegates (which would restart their timers).
        GridLayout {
            id: stack
            width: parent.width
            columns: 1
            rowSpacing: 6

            Repeater {
                model: server.trackedNotifications

                Rectangle {
                    id: toast

                    required property var modelData
                    required property int index

                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                    // Sender timeout is in seconds; <= 0 means "server default".
                    readonly property int timeoutMs: modelData.expireTimeout > 0
                                                     ? modelData.expireTimeout * 1000
                                                     : root.defaultTimeoutMs
                    readonly property string iconSource: modelData.image
                                                         || (modelData.appIcon ? Quickshell.iconPath(modelData.appIcon, true) : "")

                    Layout.row: toastWindow.count - 1 - index
                    Layout.fillWidth: true
                    visible: index >= toastWindow.count - root.maxVisible
                    implicitHeight: content.implicitHeight + 20
                    radius: 6
                    color: Colors.background
                    border.color: critical ? Colors.error : Colors.border
                    border.width: 1

                    Timer {
                        interval: toast.timeoutMs
                        running: !toast.critical && !hover.containsMouse
                        onTriggered: toast.modelData.expire()
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: toast.modelData.dismiss()
                    }

                    RowLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 10

                        Image {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            visible: toast.iconSource !== ""
                            source: toast.iconSource
                            sourceSize.width: 32
                            sourceSize.height: 32
                            fillMode: Image.PreserveAspectFit
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    Layout.fillWidth: true
                                    text: toast.modelData.appName
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: Colors.textMuted
                                    font.family: Fonts.family
                                    font.pixelSize: root.fontSize - 2
                                }

                                Text {
                                    text: ""   // x - the whole toast is clickable too
                                    color: Colors.textMuted
                                    font.family: Fonts.icons
                                    font.pixelSize: root.fontSize - 1
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: toast.modelData.summary
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Colors.text
                                font.family: Fonts.family
                                font.pixelSize: root.fontSize
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: toast.modelData.body
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                color: Colors.text
                                font.family: Fonts.family
                                font.pixelSize: root.fontSize - 1
                            }
                        }
                    }
                }
            }
        }
    }
}
