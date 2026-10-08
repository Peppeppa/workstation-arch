// Bar widget "visuals": four controls that move as ONE layout item (one
// id in bar-layout.json, one drag handle) but stay separately clickable,
// each a normal icon frame (BarWidget - same size, hitbox, hover and
// active look as every bar icon), in this order:
//   Timer      click (or mainMod+E, IPC "timer"): the timer popup
//              (TimerPopup.qml, Countdown.qml); while running the
//              remaining time stands next to the icon
//   Day/Night  click (or mainMod+A, IPC "nightlight"): warm display
//              colors on/off with a 0.5 s fade
//              (NightLight.qml; clicks during the fade do nothing)
//   Light/Dark left click: `theme toggle`; right click: the theme popup
//              (bar/widgets/Theme/Popup.qml) - the existing theme system
//   Coffee     click: pause idle lock/DPMS (CoffeeMode.qml, the bar's
//              IdleInhibitor) - only with the lock_idle feature
// At rest the controls are faded out - except one that is on (a running
// timer with its remaining time, Night, Coffee) or has its popup open.
// Hovering the widget fades all four in (BarStyle.revealDuration), leaving
// fades them out. Only opacity changes: the widget keeps its width, so the
// hover area (a HoverHandler on the whole widget) never shrinks under the
// pointer, and dragging is unchanged. No animation outside a hover change.
// Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch.

import QtQuick
import Quickshell
import qs
import qs.bar
import qs.bar.widgets.Theme as Theme

Item {
    id: root

    required property var bar

    implicitHeight: bar.barHeight
    implicitWidth: row.implicitWidth

    readonly property bool revealed: (hover.hovered && !bar.dragging) || timer.popupOpen || theme.popupOpen

    // One control: shown while revealed or while it is on.
    component Control: BarWidget {
        property bool revealed
        opacity: revealed || active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: BarStyle.revealDuration; easing.type: Easing.OutQuad } }
    }

    HoverHandler {
        id: hover
    }

    Row {
        id: row
        height: parent.height

        Control {
            id: timer
            bar: root.bar
            revealed: root.revealed
            icon: "\u{F051B}"                          // timer-outline
            text: Countdown.active ? Countdown.format(Countdown.remaining) : ""
            active: Countdown.active
            onClicked: button => { if (button === Qt.LeftButton) timer.togglePopup(); }
            onPopupOpenChanged: Countdown.popupOpen = popupOpen

            // mainMod+E (Countdown.togglePopup): open on this bar's output,
            // or close ("") wherever it is open.
            Connections {
                target: Countdown
                function onPopupRequested(screenName) {
                    if (screenName === "") timer.closePopup();
                    else if (root.bar.screen && root.bar.screen.name === screenName) timer.openPopup();
                }
            }

            Loader {
                active: timer.popupOpen
                sourceComponent: TimerPopup {
                    owner: timer
                    onCloseRequested: timer.closePopup()
                }
            }
        }

        Control {
            bar: root.bar
            revealed: root.revealed
            icon: "\u{F050E}"                          // theme-light-dark: split sun/moon
            active: NightLight.active
            muted: !NightLight.active
            onClicked: button => { if (button === Qt.LeftButton) NightLight.toggle(); }
        }

        Control {
            id: theme
            bar: root.bar
            revealed: root.revealed
            icon: Colors.mode === "light" ? "\u{F185}" : "\u{F186}"   // sun / moon
            onClicked: button => {
                if (button === Qt.RightButton) theme.togglePopup();
                else if (button === Qt.LeftButton) Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/theme", "toggle"]);
            }

            Loader {
                active: theme.popupOpen
                sourceComponent: Theme.Popup {
                    owner: theme
                    onCloseRequested: theme.closePopup()
                }
            }
        }

        Control {
            visible: BarFeatures.coffee
            bar: root.bar
            revealed: root.revealed
            icon: "\u{F0F4}"                           // coffee cup
            active: CoffeeMode.active
            muted: !CoffeeMode.active
            onClicked: button => { if (button === Qt.LeftButton) CoffeeMode.active = !CoffeeMode.active; }
        }
    }
}
