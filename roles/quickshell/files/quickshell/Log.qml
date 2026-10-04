pragma Singleton

// Shell diagnostics (core). Managed by Ansible: do not edit by hand, see
// roles/quickshell in workstation-arch.
//
// One line per FAILURE, "[component] what failed: why", via Quickshell's
// own logging - which goes to the journal (`journalctl --user -t
// quickshell`, see hyprland_quickshell_exec). Never for normal operation
// (no ticks, samples, hovers, refreshes) and never with secrets (no
// passwords/PSKs/keys - callers pass names and exit codes only). The same
// message within 60 s is dropped: a failure that repeats quickly cannot
// flood the journal.

import QtQuick
import Quickshell

Singleton {
    id: log

    readonly property int repeatWindowMs: 60000
    property var lastSeen: ({})

    function warn(component, message) {
        const key = component + "|" + message;
        const now = Date.now();
        if (lastSeen[key] !== undefined && now - lastSeen[key] < repeatWindowMs) return;
        const next = Object.assign({}, lastSeen);
        next[key] = now;
        lastSeen = next;
        console.warn("[" + component + "] " + message);
    }

    // First non-empty line of a helper's stderr - enough context, bounded.
    function firstLine(text) {
        const l = (text || "").split("\n").map(s => s.trim()).filter(s => s !== "");
        return l.length > 0 ? l[0].substring(0, 200) : "";
    }
}
