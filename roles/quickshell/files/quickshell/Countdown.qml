// The Visuals timer: one on-demand countdown with a reminder. Managed by
// Ansible: do not edit by hand, see roles/quickshell in workstation-arch.
//
// An absolute deadline (wall clock, Date.now() ms) is the only state; the
// remaining time is always deadline - now, never a decremented counter, so
// nothing drifts. The display tick is a single-shot Timer that exists only
// while a countdown runs and fires at the next full second of the
// remaining time. Suspend: Qt timers run on the monotonic clock, which
// stops while suspended, but the deadline is wall-clock time - the first
// tick after resume (< 1 s) sees the passed deadline and rings at once,
// instead of the countdown being extended by the time asleep.
// Finished: a notification (our own notification server) and a short
// sound (pw-play, freedesktop sound theme), then back to idle. No history,
// no repeat, no persistence: a Quickshell restart drops a running timer.

pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property real deadline: 0               // ms since epoch; 0 = no timer
    property real now: 0
    property int duration: 0                // s, as started (for the message)
    readonly property bool active: deadline > 0
    readonly property int remaining: active ? Math.max(0, Math.ceil((deadline - now) / 1000)) : 0
    readonly property string sound: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

    // "MM:SS" (minutes may exceed 59, e.g. 90:00) -> seconds, or -1.
    function parse(text) {
        const m = /^\s*(\d{1,3}):([0-5]\d)\s*$/.exec(text);
        if (!m) return -1;
        const s = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
        return s > 0 ? s : -1;
    }

    function format(s) {
        const m = Math.floor(s / 60), r = s % 60;
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    function start(seconds) {
        duration = seconds;
        now = Date.now();
        deadline = now + seconds * 1000;
        schedule();
    }

    function stop() {
        deadline = 0;
        tick.stop();
    }

    function schedule() {
        const left = deadline - now;
        tick.interval = Math.max(50, left % 1000 || 1000);
        tick.restart();
    }

    function finish() {
        const text = format(duration) + " are up";
        stop();
        Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm-symbolic", "Timer finished", text]);
        Quickshell.execDetached(["pw-play", sound]);
    }

    Timer {
        id: tick
        repeat: false
        onTriggered: {
            root.now = Date.now();
            if (root.now >= root.deadline) root.finish();
            else root.schedule();
        }
    }
}
