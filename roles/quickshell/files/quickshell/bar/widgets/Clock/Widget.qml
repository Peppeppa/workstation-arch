// Bar widget "clock": weekday + 24h time, e.g. "Saturday 16:03" (weekday
// in the session locale); tooltip with the full date. The bar's center
// anchor. Managed by Ansible: do not edit by hand, see roles/quickshell in
// workstation-arch. SystemClock keeps its own minute timer - no polling.

import QtQuick
import Quickshell
import qs.bar

BarWidget {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    text: Qt.formatDateTime(clock.date, "dddd HH:mm")
    tooltip: Qt.formatDate(clock.date, Locale.LongFormat)
    interactive: false
}
