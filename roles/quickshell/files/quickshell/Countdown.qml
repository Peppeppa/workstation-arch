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

    // Typed duration -> seconds, or -1 (also for 0 and anything >= 100 h).
    //   digits only, read from the right as [H]MM:SS like a microwave:
    //     5 -> 0:05, 230 / 0230 -> 2:30, 9000 -> 90:00, 13000 -> 1:30:00;
    //     the last two digits are seconds (75 = 1:15)
    //   colons: M:SS / MM:SS (minutes may exceed 59: 90:00) or H:MM:SS,
    //     every part after the first two digits and below 60
    function parse(text) {
        const t = String(text).trim();
        let h = 0, m = 0, sec = 0, p;
        if ((p = /^(\d{1,6})$/.exec(t))) {
            const d = p[1].padStart(6, "0");
            h = parseInt(d.slice(0, 2), 10);
            m = parseInt(d.slice(2, 4), 10);
            sec = parseInt(d.slice(4), 10);
        } else if ((p = /^(\d{1,3}):([0-5]\d)$/.exec(t))) {
            m = parseInt(p[1], 10);
            sec = parseInt(p[2], 10);
        } else if ((p = /^(\d{1,2}):([0-5]\d):([0-5]\d)$/.exec(t))) {
            h = parseInt(p[1], 10);
            m = parseInt(p[2], 10);
            sec = parseInt(p[3], 10);
        } else {
            return -1;
        }
        const s = h * 3600 + m * 60 + sec;
        return s > 0 && s < 100 * 3600 ? s : -1;
    }

    // Below one hour MM:SS, from one hour on H:MM:SS.
    function format(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m) + ":" + two(r) : two(m) + ":" + two(r);
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
