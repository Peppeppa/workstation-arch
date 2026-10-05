// Bar widget "visuals": four controls that move as ONE layout item (one
// id in bar-layout.json, one drag handle) but stay separately clickable,
// all permanently visible, each a normal icon frame (BarWidget - same
// size, hitbox, hover and active look as every bar icon), in this order:
//   Timer      click: the timer popup (TimerPopup.qml, Countdown.qml);
//              while running the remaining time stands next to the icon
//   Day/Night  click: warm display colors on/off (NightLight.qml)
//   Light/Dark left click: `theme toggle`; right click: the theme popup
//              (bar/widgets/Theme/Popup.qml) - the existing theme system
//   Coffee     click: pause idle lock/DPMS (CoffeeMode.qml, the bar's
//              IdleInhibitor) - only with the lock_idle feature
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

    Row {
        id: row
        height: parent.height

        BarWidget {
            id: timer
            bar: root.bar
            icon: "\u{F051B}"                          // timer-outline
            text: Countdown.active ? Countdown.format(Countdown.remaining) : ""
            active: Countdown.active
            onClicked: button => { if (button === Qt.LeftButton) timer.togglePopup(); }

            Loader {
                active: timer.popupOpen
                sourceComponent: TimerPopup {
                    owner: timer
                    onCloseRequested: timer.closePopup()
                }
            }
        }

        BarWidget {
            bar: root.bar
            icon: "\u{F050E}"                          // theme-light-dark: split sun/moon
            active: NightLight.active
            muted: !NightLight.active
            onClicked: button => { if (button === Qt.LeftButton) NightLight.active = !NightLight.active; }
        }

        BarWidget {
            id: theme
            bar: root.bar
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

        BarWidget {
            visible: BarFeatures.coffee
            bar: root.bar
            icon: "\u{F0F4}"                           // coffee cup
            active: CoffeeMode.active
            muted: !CoffeeMode.active
            onClicked: button => { if (button === Qt.LeftButton) CoffeeMode.active = !CoffeeMode.active; }
        }
    }
}
