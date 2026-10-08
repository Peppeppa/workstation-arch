// Applications - the app model (non-visual). Managed by Ansible: do not
// edit by hand, see roles/quickshell in workstation-arch.
//
// Moved unchanged from the former Launcher.qml. App data comes entirely
// from Quickshell's DesktopEntries (XDG .desktop parsing) - no app list of
// our own. Shown is an entry that passes (docs/DESIGN_SYSTEM.md "Launcher"):
//   1. its own metadata: NoDisplay=true / Hidden=true are dropped
//      (Quickshell parses both; Hidden entries never reach `applications`).
//      Quickshell 0.3.1 does not evaluate OnlyShowIn/NotShowIn/TryExec -
//      the few entries that rely on them are covered by rule 3.
//   2. category rule: settings dialogs and debuggers are not apps one
//      launches (hiddenCategories) - this also keeps the NetworkManager
//      connection editor (Settings) out: it is the OS menu's Network entry.
//   3. a small denylist of desktop-file ids for technical tools that
//      dependencies bring along (hiddenIds) - packages stay installed,
//      only their launcher entry is hidden.

import QtQuick
import Quickshell

Scope {
    id: model

    // Rows the page is tall; a search shows at most this many matches. The
    // empty search lists EVERY shown app (scrollable) - it was cut to the
    // first 8 alphabetically, so e.g. Thunderbird only appeared after typing.
    readonly property int maxResults: 8

    // Rule 2: entries in any of these categories are system configuration
    // or debugging helpers (e.g. Qt's D-Bus viewer).
    readonly property var hiddenCategories: ["Settings", "DesktopSettings", "Debugger"]

    // Rule 3: desktop-file ids (file name without .desktop) of technical
    // tools pulled in by dependencies, with the package that brings them.
    readonly property var hiddenIds: [
        "avahi-discover", "bssh", "bvnc",            // avahi (needed by CUPS, PipeWire-Pulse, Flatpak/ostree)
        "lstopo",                                    // hwloc (via onetbb <- appstream <- Flatpak)
        "designer", "linguist", "assistant",         // qt6-tools (needed by VirtualBox)
        "qv4l2", "qvidcap",                          // v4l-utils (needed by ffmpeg)
        "stoken-gui", "stoken-gui-small",            // stoken: RSA soft token (needed by openconnect, NM VPN plugin)
        "jconsole-java25-openjdk", "jshell-java25-openjdk" // jdk25-openjdk (roles/development): JMX monitor + terminal REPL
    ]

    function shown(e) {
        return !e.noDisplay
            && hiddenIds.indexOf(e.id) === -1
            && !(e.categories || []).some(c => hiddenCategories.indexOf(c) !== -1);
    }

    // The ranking of a text match (used for apps and, in the OS menu's
    // type-to-search, for its own entries): 0 name starts with the query,
    // 1 name contains it, 2 generic name contains it, 3 keywords contain
    // it, -1 no match.
    function matchScore(needle, name, generic, keywords) {
        const n = (name || "").toLowerCase();
        if (n.startsWith(needle)) return 0;
        if (n.includes(needle)) return 1;
        if ((generic || "").toLowerCase().includes(needle)) return 2;
        if ((keywords || "").toLowerCase().includes(needle)) return 3;
        return -1;
    }

    // Matching apps of a non-empty query as [{entry, score}], best first.
    function scored(q) {
        const needle = q.toLowerCase();
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (!model.shown(e)) continue;
            const score = matchScore(needle, e.name, e.genericName, (e.keywords || []).join(" "));
            if (score >= 0) out.push({ entry: e, score: score });
        }
        out.sort((a, b) => a.score - b.score || a.entry.name.localeCompare(b.entry.name));
        return out;
    }

    // Name matches first, then generic name, then keywords; empty query:
    // all shown apps, alphabetical. Only the name is shown - the rest only
    // helps finding.
    function search(q) {
        if (q.length === 0) {
            return DesktopEntries.applications.values.filter(e => model.shown(e))
                .sort((a, b) => a.name.localeCompare(b.name));
        }
        return scored(q).slice(0, maxResults).map(s => s.entry);
    }
}
