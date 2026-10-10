# Managed by Ansible (roles/diagnostics/files/diaglib.py) - do not edit by hand.
#
# Shared, read-only log functions of repo-healthcheck, repo-diagnose and
# repo-logs (/usr/local/lib/workstation/diaglib.py). One place reads the
# journal, splits Quickshell's output into runs and classifies events, so
# the three tools never count the same thing three different ways:
#   repo-healthcheck  qml_status()      - fast: current Quickshell run only
#   repo-diagnose     qml_status()      - the same split, with counts
#   repo-logs analyze analyze()         - every collector below, grouped
# Pure Python standard library; nothing here writes, starts or changes
# anything. Deterministic rules only - no network, no model, no guessing:
# an event without a rule keeps its own text and gets no explanation.

import calendar
import glob
import json
import os
import re
import subprocess
import time

# QML problems that mean a broken component, not a missing capability.
QML_BROKEN = re.compile(r"\b(ERROR|CRIT)\b|TypeError|ReferenceError|RangeError|SyntaxError|Binding loop"
                        r"|is not a function|Cannot (read|assign)")
QML_WARN = re.compile(r"\bWARN\b")
# Quickshell's own markers: a process starts a run, every config reload a new one.
QS_LAUNCH = "Launching config"
QS_RELOAD = "Reloading configuration"

SEVERITIES = ("critical", "warning", "info")

# Units whose failure breaks the workstation's core (AGENTS.md ownership table).
CORE_UNITS = {"NetworkManager.service", "systemd-logind.service", "workstation-firewall.service",
              "dbus.service", "dbus-broker.service", "systemd-journald.service", "polkit.service",
              "ly@tty2.service", "upower.service", "power-profiles-daemon.service"}

# Unit / identifier -> component name in the report.
COMPONENTS = [
    (re.compile(r"^workstation-firewall|^firewall-rules$"), "Firewall"),
    (re.compile(r"^snapper|^snapperd|^pre-transaction-snapshot$|^system-snapshot$|^snapshot-create$"), "Snapper"),
    (re.compile(r"^system-update|^workstation-system-update"), "System-Update"),
    (re.compile(r"^NetworkManager|^wpa_supplicant|^nm-"), "Netzwerk"),
    (re.compile(r"^bluetooth|^bluetoothd"), "Bluetooth"),
    (re.compile(r"^pipewire|^wireplumber"), "Audio"),
    (re.compile(r"^ly|^ly-dm$"), "Login (Ly)"),
    (re.compile(r"^sudo$|^pkexec$|^polkit"), "Rechte (sudo/polkit)"),
    (re.compile(r"^xdg-desktop-portal"), "Portale"),
    (re.compile(r"^hypr|^Hyprland$"), "Hyprland"),
    (re.compile(r"^kernel$"), "Kernel"),
    (re.compile(r"^systemd"), "systemd"),
]

# Known, documented harmless messages: (identifier regex, message regex,
# reason). Each reason states what the message means - nothing more.
KNOWN_HARMLESS = [
    (r"^kernel$", r"kvm_amd: CPU \d+ isn't AMD or Hygon",
     "kvm_amd lädt auf einer Intel-CPU nicht; zuständig ist kvm_intel."),
    (r"^kernel$", r"TDX not supported by the host platform",
     "Intel TDX (vertrauliche VMs) gibt es auf dieser Plattform nicht; nichts hängt davon ab."),
    (r"^wpa_supplicant$", r"multicast RX registrations are not supported",
     "Der WLAN-Treiber bietet eine optionale nl80211-Funktion nicht an."),
    (r"^ly-dm$|^login$", r"gkr-pam: unable to locate daemon control file",
     "gnome-keyring lief beim PAM-Schritt des Logins noch nicht; es wird mit der Sitzung gestartet."),
    (r"^xdg-desktop-portal$", r"Failed to load RealtimeKit property",
     "rtkit ist nicht installiert (optional, AGENTS.md: Portal-Warnungen untersucht, harmlos)."),
]
KNOWN_HARMLESS = [(re.compile(i), re.compile(m), r) for i, m, r in KNOWN_HARMLESS]

FS_ERROR = re.compile(r"BTRFS (error|critical)|EXT4-fs error|XFS .*(corruption|error)|I/O error|"
                      r"critical medium error|blk_update_request: .*error|Buffer I/O error|"
                      r"\bcorrupt(ed|ion)?\b.*(block|inode|tree|leaf|csum)|csum failed", re.I)


def run(argv, timeout=15, env=None):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env)
        return r.returncode, r.stdout, r.stderr.strip()
    except (OSError, subprocess.SubprocessError) as e:
        return 127, "", str(e)


def _text(v):
    if isinstance(v, str):
        return v
    if isinstance(v, list):                     # journald: non-UTF-8 MESSAGE = byte list
        try:
            return bytes(v).decode("utf-8", "replace")
        except (TypeError, ValueError):
            return ""
    return "" if v is None else str(v)


def journal(args, limit=5000, timeout=20):
    """(ok, error, [entry]) - journalctl -o json with `args`; entry = dict with
    ts (epoch s), pid, prio (int|None), ident, unit, boot, cursor, msg, transport.
    ok False (and why) when journalctl failed (no permission, no journal)."""
    rc, out, err = run(["journalctl", "--no-pager", "-q", "-o", "json", "-n", str(limit)] + list(args), timeout=timeout)
    if rc != 0:
        return False, err or "journalctl exit %d" % rc, []
    return True, "", parse_journal(out)


def parse_journal(text):
    entries = []
    for line in text.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        try:
            ts = int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6
        except ValueError:
            ts = 0
        prio = e.get("PRIORITY")
        entries.append({
            "ts": ts,
            "pid": _text(e.get("_PID")) or None,
            "prio": int(prio) if isinstance(prio, str) and prio.isdigit() else None,
            "ident": _text(e.get("SYSLOG_IDENTIFIER")) or _text(e.get("_COMM")),
            "unit": _text(e.get("_SYSTEMD_UNIT")) or _text(e.get("_SYSTEMD_USER_UNIT")),
            "boot": _text(e.get("_BOOT_ID")),
            "cursor": _text(e.get("__CURSOR")),
            "transport": _text(e.get("_TRANSPORT")),
            "msg": _text(e.get("MESSAGE")).rstrip(),
        })
    return entries


# --- Quickshell runs ---------------------------------------------------------

def quickshell_runs(entries):
    """Split Quickshell's journal lines into runs: a new run starts with every
    process (other _PID) and every config (re)load inside one process
    ("Reloading configuration..."). -> [{pid, gen, start, lines}] in order."""
    runs = []
    for e in entries:
        cur = runs[-1] if runs else None
        if cur is None or e["pid"] != cur["pid"] or QS_RELOAD in e["msg"]:
            gen = cur["gen"] + 1 if cur is not None and e["pid"] == cur["pid"] else 0
            cur = {"pid": e["pid"], "gen": gen, "start": e["ts"], "lines": []}
            runs.append(cur)
        cur["lines"].append(e)
    return runs


def qml_status(entries, current_pid, since=None):
    """Which QML errors belong to the RUNNING Quickshell config, which are history.
    current = errors of the last run of `current_pid` (its newest config load,
    successful or not - a failed reload keeps the old config, so its error
    stays current until a later load succeeds); with `since` (system-update)
    also every error from that moment on. Errors of earlier runs - another
    process or an earlier config load of this one - are `earlier`: still
    shown (repo-logs analyze), never a current failure.
    -> {current: [entry], earlier: [entry], earlier_runs: [(pid, gen, n)],
        current_run: (pid, gen) | None}"""
    runs = quickshell_runs(entries)
    pid = str(current_pid) if current_pid is not None else None
    mine = [r for r in runs if pid is not None and r["pid"] == pid]
    last = mine[-1] if mine else None
    current, earlier, earlier_runs = [], [], []
    for r in runs:
        errs = [e for e in r["lines"] if QML_BROKEN.search(e["msg"])]
        if r is last:
            current += errs
            continue
        late = [e for e in errs if since is not None and e["ts"] >= since]
        current += late
        old = [e for e in errs if e not in late]
        earlier += old
        if old:
            earlier_runs.append((r["pid"], r["gen"], len(old)))
    return {"current": current, "earlier": earlier, "earlier_runs": earlier_runs,
            "current_run": (last["pid"], last["gen"]) if last else None}


# --- grouping ----------------------------------------------------------------

def normalize(msg):
    """Message -> grouping key: numbers, hex, addresses and pids folded."""
    m = re.sub(r"0x[0-9a-fA-F]+|\b[0-9a-f]{8,}\b", "#", msg)
    m = re.sub(r"\[\d+\]", "[#]", m)
    m = re.sub(r"\d+(\.\d+)*", "N", m)
    return re.sub(r"\s+", " ", m).strip()


def component_of(e):
    for key in (e.get("unit") or "", e.get("ident") or ""):
        name = re.sub(r"@.*|\.service$|\.scope$|\.socket$", "", key)
        for rx, comp in COMPONENTS:
            if name and rx.search(name):
                return comp
    return e.get("ident") or e.get("unit") or "?"


def harmless(e):
    for irx, mrx, reason in KNOWN_HARMLESS:
        if irx.search(e.get("ident") or "") and mrx.search(e["msg"]):
            return reason
    return None


def finding(severity, component, summary, entries=None, current=True, note="", ref="", lines=None,
            first=None, last=None, count=None):
    entries = entries or []
    ts = [e["ts"] for e in entries if e.get("ts")]
    pids = sorted({e["pid"] for e in entries if e.get("pid")})
    boots = sorted({e["boot"] for e in entries if e.get("boot")})
    return {
        "severity": severity, "component": component, "summary": summary,
        "count": count if count is not None else max(1, len(entries)),
        "first": first if first is not None else (min(ts) if ts else None),
        "last": last if last is not None else (max(ts) if ts else None),
        "pids": pids, "boots": boots, "current": current, "note": note, "ref": ref,
        "lines": lines if lines is not None else [format_entry(e) for e in entries[-200:]],
    }


PRIO = {0: "EMERG", 1: "ALERT", 2: "CRIT", 3: "ERR", 4: "WARN", 5: "NOTICE", 6: "INFO", 7: "DEBUG"}


def format_entry(e):
    t = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(e["ts"])) if e.get("ts") else "-"
    who = e.get("ident") or "?"
    return "%s  %-6s %s%s: %s" % (t, PRIO.get(e.get("prio"), ""), who, "[%s]" % e["pid"] if e.get("pid") else "", e["msg"])


def group(entries):
    """[(key, [entries])] - one group per (identifier, normalized message), in
    order of first appearance."""
    groups = {}
    for e in entries:
        groups.setdefault((e.get("ident") or e.get("unit") or "?", normalize(e["msg"])), []).append(e)
    return list(groups.items())


# --- collectors (repo-logs analyze) -------------------------------------------

def collect_units(ctx):
    out = []
    for user in (False, True):
        rc, o, _ = run(["systemctl"] + (["--user"] if user else []) + ["list-units", "--state=failed", "--no-legend", "--plain", "--all"])
        for unit in [l.split()[0] for l in o.splitlines() if l.strip()]:
            ts = None
            rc2, v, _ = run(["systemctl"] + (["--user"] if user else []) + ["show", "-p", "StateChangeTimestampMonotonic", "--value", unit])
            try:
                ts = ctx["boot_time"] + int(v.strip()) / 1e6
            except (ValueError, TypeError):
                pass
            if user:
                cur = not (ctx.get("session_start") and ts and ts < ctx["session_start"])
                sev = "warning"
            else:
                cur = True
                sev = "critical" if unit in CORE_UNITS else "warning"
            out.append(finding(sev, component_of({"unit": unit}), "%s-Unit fehlgeschlagen: %s" % ("User" if user else "System", unit),
                               current=cur, first=ts, last=ts, count=1, lines=[],
                               note="" if cur else "aus einer früheren Sitzung (vor dem Start dieses Hyprland)",
                               ref="systemctl %sstatus %s; journalctl %s-b -u %s" % ("--user " if user else "", unit, "--user " if user else "", unit)))
    return out


def classify_journal(entries, user, ctx):
    """Priority 0-3 events of the current boot (system or user journal),
    Quickshell and the kernel excluded (their own collectors)."""
    out = []
    for (ident, key), es in group(entries):
        e0 = es[0]
        comp = component_of(e0)
        why = harmless(e0)
        prio = min(e["prio"] for e in es if e["prio"] is not None) if any(e["prio"] is not None for e in es) else 3
        ref = "journalctl %s-b -t %s -p err" % ("--user " if user else "", ident)
        if why:
            out.append(finding("info", comp, "Bekannte harmlose Meldung: %s" % e0["msg"][:120], es, note=why, ref=ref))
        elif ident == "sudo" and re.search(r"auth|password|conversation failed", e0["msg"], re.I):
            sev = "warning" if len(es) >= 3 else "info"
            out.append(finding(sev, comp, "sudo-Authentifizierung fehlgeschlagen: %s" % e0["msg"][:100], es, ref=ref,
                               note="Mehrere Fehlversuche können faillock auslösen (faillock --user %s)." % os.environ.get("USER", "")
                               if sev == "warning" else ""))
        elif prio <= 2:
            out.append(finding("critical", comp, e0["msg"][:140], es, ref=ref))
        else:
            out.append(finding("warning", comp, e0["msg"][:140], es, ref=ref))
    return out


def collect_journal(ctx):
    out = []
    for user in (False, True):
        args = (["--user"] if user else []) + ["-b", "-p", "0..3"]
        ok, err, es = journal(args, limit=3000)
        if not ok:
            out.append(finding("info", "Journal", "%s-Journal nicht lesbar" % ("User" if user else "System"),
                               current=True, note=err[:160], lines=[], count=1))
            continue
        es = [e for e in es if e["transport"] != "kernel" and e["ident"] != "quickshell"]
        out += classify_journal(es, user, ctx)
    return out


def collect_kernel(ctx):
    ok, err, es = journal(["-k", "-b", "-p", "0..4"], limit=3000)
    if not ok:
        return [finding("info", "Kernel", "Kernel-Meldungen nicht lesbar", note=err[:160], lines=[], count=1)]
    out, once = [], []
    for (ident, key), g in group(es):
        e0 = g[0]
        why = harmless(e0)
        prio = min((e["prio"] for e in g if e["prio"] is not None), default=4)
        ref = "journalctl -k -b -p warning"
        if FS_ERROR.search(e0["msg"]):
            out.append(finding("critical", "Kernel (Dateisystem/Datenträger)", e0["msg"][:140], g, ref=ref))
        elif why:
            out.append(finding("info", "Kernel", "Bekannte harmlose Meldung: %s" % e0["msg"][:110], g, note=why, ref=ref))
        elif prio <= 2:
            out.append(finding("critical", "Kernel", e0["msg"][:140], g, ref=ref))
        elif prio == 3 or len(g) >= 5:
            out.append(finding("warning", "Kernel", ("Wiederkehrend: " if len(g) >= 5 and prio > 3 else "") + e0["msg"][:130], g, ref=ref))
        else:
            once += g
    if once:
        out.append(finding("info", "Kernel", "%d einmalige Kernel-Warnung(en) dieses Boots (meist Firmware/Treiber beim Start)" % len(once),
                           once, ref="journalctl -k -b -p warning",
                           note="Einzeln aufgeführt in den Originalmeldungen; ohne Regel keine Bewertung."))
    return out


def collect_quickshell(ctx):
    ok, err, es = journal(["--user", "-b", "-t", "quickshell"], limit=20000)
    if not ok:
        return [finding("info", "Quickshell", "Quickshell-Journal nicht lesbar", note=err[:160], lines=[], count=1)]
    st = qml_status(es, ctx.get("qs_pid"))
    out = []
    cur_ids = {id(e) for e in st["current"]}
    runs = quickshell_runs(es)
    for (ident, key), g in group([e for e in es if QML_BROKEN.search(e["msg"])]):
        cur = [e for e in g if id(e) in cur_ids]
        old = [e for e in g if id(e) not in cur_ids]
        ref = "journalctl --user -b -t quickshell _PID=%s" % (g[-1]["pid"] or "")
        if cur:
            out.append(finding("warning", "Quickshell (QML)", cur[0]["msg"].strip()[:140], cur, ref=ref,
                               note="im laufenden Quickshell (seit dem letzten Laden der Konfiguration)"))
        if old:
            pids = sorted({e["pid"] for e in old})
            out.append(finding("warning", "Quickshell (QML)", old[0]["msg"].strip()[:140], old, current=False, ref=ref,
                               note="frühere Instanz/früheres Laden (pid %s); der laufende Quickshell lädt ohne diesen Fehler"
                               % ", ".join(pids)))
    warns = [e for e in es if QML_WARN.search(e["msg"]) and not QML_BROKEN.search(e["msg"])]
    for (ident, key), g in group(warns):
        cur_run = st["current_run"]
        cur = [e for e in g if cur_run and e["pid"] == cur_run[0]]
        out.append(finding("info", "Quickshell (QML)", "Warnung: " + g[0]["msg"].strip()[:130], g,
                           current=bool(cur), ref="journalctl --user -b -t quickshell"))
    starts = [r for r in runs if r["gen"] == 0]
    if runs:
        out.append(finding("info", "Quickshell", "%d Prozessstart(s), %d Konfigurations-Ladevorgang/-vorgänge dieses Boots"
                           % (len(starts), len(runs)), [r["lines"][0] for r in runs], ref="journalctl --user -b -t quickshell -g 'Launching|Reloading|Loaded'"))
    return out


def collect_hyprland(ctx):
    out = []
    log = ctx.get("hyprland_log")
    if log and os.path.isfile(log):
        with open(log, errors="replace") as f:
            errs = [l.rstrip() for l in f if l.startswith("ERR")]
        groups = {}
        for l in errs:
            groups.setdefault(normalize(l), []).append(l)
        for key, ls in groups.items():
            out.append(finding("warning", "Hyprland", ls[0][:140], lines=ls[-50:], count=len(ls), ref=log))
    rc, o, _ = run(["hyprctl", "configerrors"], env=ctx.get("hypr_env"))
    errs = [l for l in o.splitlines() if l.strip()]
    if rc == 0 and errs:
        out.append(finding("warning", "Hyprland", "Konfigurationsfehler: " + errs[0][:120], lines=errs, count=len(errs),
                           ref="hyprctl configerrors"))
    for p in sorted(glob.glob(os.path.expanduser("~/.cache/hyprland/hyprlandCrashReport*.txt")), key=os.path.getmtime):
        t = os.path.getmtime(p)
        if t < ctx["boot_time"] - 7 * 86400:
            continue
        cur = bool(ctx.get("session_start") and t >= ctx["session_start"])
        out.append(finding("warning", "Hyprland", "Absturzbericht %s" % os.path.basename(p), current=cur, first=t, last=t, count=1,
                           lines=[], ref=p))
    return out


def collect_coredumps(ctx):
    rc, o, _ = run(["coredumpctl", "--no-pager", "--no-legend", "-q", "--json=short", "list", "--since", "@%d" % ctx["boot_time"]])
    try:
        dumps = json.loads(o) if rc == 0 and o.strip() else []
    except ValueError:
        dumps = []
    out = []
    groups = {}
    for d in dumps:
        groups.setdefault((os.path.basename(d.get("exe", "?")), d.get("sig")), []).append(d)
    for (exe, sig), ds in groups.items():
        ts = [d.get("time", 0) / 1e6 for d in ds]
        cur = bool(ctx.get("session_start") and max(ts) >= ctx["session_start"])
        note = ""
        if exe == "Hyprland" and sig == 11 and not cur:
            note = ("bekannt (upstream): Hyprland SIGSEGV beim Beenden mit zwei Ausgängen "
                    "(aquamarine), docs/feature-architecture.md")
        lines = ["%s  pid %s  %s  signal %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(d.get("time", 0) / 1e6)),
                                                d.get("pid"), d.get("exe"), d.get("sig")) for d in ds]
        out.append(finding("info" if note else "warning", "Abstürze (coredumps)", "%s abgestürzt (Signal %s)" % (exe, sig),
                           current=cur, first=min(ts), last=max(ts), count=len(ds), lines=lines, note=note,
                           ref="coredumpctl list %s" % exe))
    return out


PACMAN_LINE = re.compile(r"^\[(\S+)\] \[(\w+)\] (.*)$")


def parse_pacman_log(lines, since):
    """Transactions from pacman.log lines -> [{start, end, state, upgrade, lines, errors}]
    state: completed | failed | interrupted. Only transactions starting at/after `since`."""
    txs, cur, upgrade = [], None, False
    for raw in lines:
        m = PACMAN_LINE.match(raw.rstrip("\n"))
        if not m:
            continue
        stamp, src, text = m.groups()
        try:
            ts = time.mktime(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S"))
        except ValueError:
            continue
        if src == "PACMAN" and "starting full system upgrade" in text:
            upgrade = True
        if src == "ALPM" and text == "transaction started":
            if cur is not None:
                cur["state"] = "interrupted"
                txs.append(cur)
            cur = {"start": ts, "end": ts, "state": "running", "upgrade": upgrade, "lines": [raw.rstrip()], "errors": []}
            upgrade = False
            continue
        if cur is None:
            continue
        cur["lines"].append(raw.rstrip())
        cur["end"] = ts
        if src == "ALPM" and text == "transaction completed":
            cur["state"] = "completed"
            txs.append(cur)
            cur = None
        elif src == "ALPM" and text in ("transaction failed", "transaction interrupted"):
            cur["state"] = "failed"
            txs.append(cur)
            cur = None
        elif text.startswith("error:") or src == "ALPM" and text.startswith("error"):
            cur["errors"].append(raw.rstrip())
    if cur is not None:
        cur["state"] = "interrupted"
        txs.append(cur)
    return [t for t in txs if t["start"] >= since]


def collect_pacman(ctx, path="/var/log/pacman.log", days=30):
    try:
        with open(path, errors="replace") as f:
            lines = f.readlines()
    except OSError as e:
        return [finding("info", "Pacman", "pacman.log nicht lesbar", note=str(e), lines=[], count=1)]
    since = time.time() - days * 86400
    txs = parse_pacman_log(lines, since)
    out = []
    bad = [t for t in txs if t["state"] != "completed" or t["errors"]]
    last_ok = max((t["end"] for t in txs if t["state"] == "completed" and not t["errors"]), default=None)
    for t in bad:
        cur = last_ok is None or t["start"] > last_ok
        failed = t["state"] != "completed"
        sev = "critical" if failed and cur else "warning"
        what = {"failed": "fehlgeschlagen", "interrupted": "abgebrochen (kein 'transaction completed')"}.get(t["state"], "mit Fehlermeldungen")
        out.append(finding(sev, "Pacman", "Pakettransaktion %s" % what, current=cur, first=t["start"], last=t["end"], count=1,
                           lines=t["lines"][-80:], ref=path,
                           note="" if cur else "danach lief eine Transaktion erfolgreich durch"))
    ok = [t for t in txs if t["state"] == "completed" and not t["errors"]]
    ups = [t for t in ok if t["upgrade"]]
    if ok:
        out.append(finding("info", "Pacman", "%d erfolgreiche Pakettransaktion(en) in %d Tagen" % (len(ok), days),
                           first=ok[0]["start"], last=ok[-1]["end"], count=len(ok), lines=[t["lines"][0] for t in ok][-50:], ref=path))
    if ups:
        out.append(finding("info", "System-Update", "Letztes vollständiges Systemupdate erfolgreich", first=ups[-1]["start"],
                           last=ups[-1]["end"], count=len(ups), lines=ups[-1]["lines"][-80:], ref=path,
                           note="%d vollständige(s) Update(s) in %d Tagen" % (len(ups), days)))
    return out


def collect_updates(ctx):
    out = []
    ok, err, es = journal(["-t", "system-update", "--since", "-30d"], limit=500)
    if ok:
        skips = [e for e in es if "skip" in e["msg"].lower() or (e["prio"] is not None and e["prio"] <= 4)]
        if skips:
            out.append(finding("warning", "System-Update", "Update ohne Snapshot bzw. Warnung von system-update", skips,
                               ref="journalctl -t system-update"))
    # The terminal unit (workstation-system-update) only says whether the
    # terminal ended - the transaction's result is pacman.log's (collect_pacman).
    return out


def collect_snapshots(ctx):
    out = []
    if not ctx.get("recovery"):
        return out
    snaps = []
    for f in glob.glob("/.snapshots/*/info.xml"):
        try:
            with open(f, errors="replace") as fh:
                x = fh.read()
        except OSError:
            continue
        num = re.search(r"<num>(\d+)</num>", x)
        date = re.search(r"<date>([^<]+)</date>", x)
        desc = re.search(r"<description>([^<]*)</description>", x)
        if not (num and date):
            continue
        try:                            # snapper writes UTC
            ts = calendar.timegm(time.strptime(date.group(1), "%Y-%m-%d %H:%M:%S"))
        except ValueError:
            continue
        snaps.append((ts, int(num.group(1)), desc.group(1) if desc else ""))
    snaps.sort()
    if snaps:
        recent = [s for s in snaps if s[0] >= time.time() - 7 * 86400]
        t, n, d = snaps[-1]
        out.append(finding("info", "Snapper", "Letzter Snapshot #%d: %s" % (n, d or "-"), first=snaps[0][0], last=t,
                           count=len(snaps), lines=["#%d  %s  %s" % (n2, time.strftime("%Y-%m-%d %H:%M", time.localtime(t2)), d2)
                                                    for t2, n2, d2 in snaps[-30:]],
                           note="%d Snapshot(s) insgesamt, %d in den letzten 7 Tagen" % (len(snaps), len(recent)),
                           ref="snapper -c root list (Root: sudo)"))
    return out


def collect_firewall(ctx):
    rc, o, _ = run(["systemctl", "is-active", "workstation-firewall.service"])
    state = o.strip() or "unknown"
    if state != "active":
        return [finding("critical", "Firewall", "workstation-firewall.service ist %s - kein Eingangsfilter" % state, count=1, lines=[],
                        ref="systemctl status workstation-firewall; journalctl -b -u workstation-firewall")]
    ok, err, es = journal(["-b", "-u", "workstation-firewall.service"], limit=200)
    return [finding("info", "Firewall", "Firewall geladen (table inet workstation)", es[-5:] if ok else [],
                    ref="journalctl -b -u workstation-firewall")]


COLLECTORS = [collect_units, collect_journal, collect_kernel, collect_quickshell, collect_hyprland, collect_coredumps,
              collect_firewall, collect_pacman, collect_updates, collect_snapshots]


def analyze(ctx, collectors=None):
    """Every collector -> {findings (sorted), counts {current: {sev: n}, history: n}}.
    A collector that fails is reported as its own info finding, never hides the rest."""
    findings = []
    for c in collectors or COLLECTORS:
        try:
            findings += c(ctx)
        except Exception as e:          # one broken source must not end the report
            findings.append(finding("info", c.__name__.replace("collect_", ""), "Quelle nicht auswertbar: %s" % e.__class__.__name__,
                                    note=str(e)[:160], lines=[], count=1))
    order = {s: i for i, s in enumerate(SEVERITIES)}
    findings.sort(key=lambda f: (not f["current"], order[f["severity"]], -(f["last"] or 0)))
    counts = {s: sum(1 for f in findings if f["current"] and f["severity"] == s) for s in SEVERITIES}
    return {"findings": findings, "counts": counts, "history": sum(1 for f in findings if not f["current"])}


def boot_time():
    with open("/proc/stat") as f:
        return int(next(l for l in f if l.startswith("btime")).split()[1])


def started_at(pid):
    """Process start as epoch seconds (from /proc), or None."""
    try:
        with open("/proc/%d/stat" % int(pid)) as f:
            ticks = int(f.read().rsplit(")", 1)[1].split()[19])
        return boot_time() + ticks / os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, StopIteration, IndexError, TypeError):
        return None


def session():
    """The calling user's desktop: {hyprland_pid, qs_pid, session_start, hypr_env,
    hyprland_log} (None where absent) - from /proc and the Hyprland process'
    own environment; the desktop Quickshell is the one whose command line is
    exactly `quickshell` (test instances run with -p/-c)."""
    uid = os.getuid()
    hp = qp = None
    for p in glob.glob("/proc/[0-9]*"):
        try:
            if os.stat(p).st_uid != uid:
                continue
            with open(p + "/comm") as f:
                comm = f.read().strip()
            with open(p + "/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").strip()
        except OSError:
            continue
        if comm == "Hyprland":
            hp = int(p[6:])
        elif comm == "quickshell" and cmd == b"quickshell":
            qp = int(p[6:])
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % uid
    env = dict(os.environ, XDG_RUNTIME_DIR=runtime)
    sig = None
    if hp:
        try:
            with open("/proc/%d/environ" % hp, "rb") as f:
                for kv in f.read().split(b"\0"):
                    if kv.startswith(b"HYPRLAND_INSTANCE_SIGNATURE="):
                        sig = kv.split(b"=", 1)[1].decode(errors="replace")
        except OSError:
            pass
    if sig:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
    return {"hyprland_pid": hp, "qs_pid": qp, "session_start": started_at(hp) if hp else None, "hypr_env": env,
            "hyprland_log": os.path.join(runtime, "hypr", sig, "hyprland.log") if sig else None}


def context(recovery=False):
    ctx = session()
    ctx.update(boot_time=boot_time(), recovery=recovery)
    return ctx
