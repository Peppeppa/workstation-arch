// FEATURE: power_profiles (see group_vars/all.yml power_profiles_enabled
// and docs/feature-architecture.md). Managed by Ansible: do not edit by
// hand, see roles/quickshell in workstation-arch. Loaded by Bar.qml only
// while the feature is enabled.
//
// The bar's power entry point: on machines WITHOUT a battery it shows the
// current power profile as an icon (so profiles stay reachable on a
// workstation); with a battery the battery slot itself opens the popup.
// Profiles via Quickshell's PowerProfiles (power-profiles-daemon over
// D-Bus, event-driven - no polling; setting `profile` is the switch).

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Item {
    id: control

    required property var bar
    required property bool hasBattery

    property bool popupOpen: false
    property real popupAnchorX: 0

    function open(item) {
        popupAnchorX = item.mapToItem(null, item.width / 2, 0).x;
        popupOpen = !popupOpen;
    }

    function profileIcon(p) {
        return p === PowerProfile.Performance ? "\u{F14DE}"     // rocket
             : p === PowerProfile.PowerSaver ? "\u{F032A}"      // leaf
             : "\u{F05D1}";                                      // scale (balanced)
    }

    visible: !hasBattery
    implicitWidth: hasBattery ? 0 : 22
    implicitHeight: bar.barHeight

    Text {
        visible: !control.hasBattery
        anchors.centerIn: parent
        text: control.profileIcon(PowerProfiles.profile)
        color: Colors.foreground
        font.family: Fonts.icons
        font.pixelSize: control.bar.fontSize + 1
    }

    MouseArea {
        anchors.fill: parent
        enabled: !control.hasBattery
        onClicked: control.open(control)
    }

    Loader {
        active: control.popupOpen
        sourceComponent: PowerPopup {
            screen: control.bar.screen
            anchorX: control.popupAnchorX
            barHeight: control.bar.barHeight
            fontSize: control.bar.fontSize
            profileIcon: control.profileIcon
            onCloseRequested: control.popupOpen = false
        }
    }
}
