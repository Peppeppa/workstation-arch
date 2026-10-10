#!/usr/bin/env python3
"""roles/diagnostics: diaglib.py (shared log functions) and repo-logs, run by
tests/run.sh. Isolated test data only: journal entries are built here, and
journalctl / nvim / systemctl are stubs on a private PATH - no real journal,
no real log is read or changed.

  - Quickshell runs: current vs historical QML errors (healthcheck's rule)
  - pacman.log transactions: completed / failed / interrupted, history
  - journal classification: known harmless, priority, repetition, sudo
  - journalctl failing (no permission) and an empty journal
  - repo-logs: fixed sources only, a private read-only copy that is gone
    after the viewer, usage errors, the analysis report (JSON + text)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import jinja2
import yaml

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(ROOT, "roles/diagnostics/files"))
import diaglib  # noqa: E402

fails = 0


def eq(what, got, want):
    global fails
    if got != want:
        fails += 1
        print("FAIL %s: %r != %r" % (what, got, want))


def e(pid, msg, ts, prio=None, ident="quickshell"):
    return {"ts": ts, "pid": str(pid) if pid is not None else None, "prio": prio, "ident": ident, "unit": "",
            "boot": "b0", "cursor": "", "transport": "stdout", "msg": msg}


LAUNCH, RELOAD, LOADED = 'INFO: Launching config: "shell.qml"', "INFO: Reloading configuration...", "INFO: Configuration Loaded"
BAD = '  ERROR:   caused by @shell.qml[153:9]: Cannot assign to non-existent property "snapshotDialog"'

# 1 current QML error: in the running process' newest load
st = diaglib.qml_status([e(10, LAUNCH, 1), e(10, LOADED, 2), e(10, "WARN qml: TypeError: x is undefined", 3)], 10)
eq("current error counted", (len(st["current"]), len(st["earlier"])), (1, 0))

# 2 historical: an earlier process had the error, the running one is clean
st = diaglib.qml_status([e(5, LAUNCH, 1), e(5, BAD, 2), e(10, LAUNCH, 3), e(10, LOADED, 4)], 10)
eq("other instance = history", (len(st["current"]), len(st["earlier"]), st["earlier_runs"]), (0, 1, [("5", 0, 1)]))

# 3 new successful start after a failed reload IN THE SAME process (the real 15:21 case)
st = diaglib.qml_status([e(7, LAUNCH, 1), e(7, LOADED, 2), e(7, RELOAD, 3), e(7, "ERROR: Failed to load configuration", 4),
                         e(7, BAD, 5), e(7, RELOAD, 6), e(7, LOADED, 7)], 7)
eq("failed reload, then a good one = history", (len(st["current"]), len(st["earlier"]), st["current_run"]), (0, 2, ("7", 2)))

# 4 several restarts: only the last run of the running pid counts
st = diaglib.qml_status([e(1, LAUNCH, 1), e(1, BAD, 2), e(2, LAUNCH, 3), e(2, BAD, 4), e(3, LAUNCH, 5), e(3, LOADED, 6)], 3)
eq("restarts: history from both earlier pids", (len(st["current"]), [r[0] for r in st["earlier_runs"]]), (0, ["1", "2"]))

# 5 failed CURRENT start/reload: its error stays current (the old config runs on)
st = diaglib.qml_status([e(7, LAUNCH, 1), e(7, LOADED, 2), e(7, RELOAD, 3), e(7, "ERROR: Failed to load configuration", 4), e(7, BAD, 5)], 7)
eq("failed newest load = current", len(st["current"]), 2)

# 6 no journal lines at all / no Quickshell running
st = diaglib.qml_status([], 7)
eq("empty journal", (st["current"], st["earlier"], st["current_run"]), ([], [], None))
st = diaglib.qml_status([e(5, BAD, 1)], None)
eq("no running Quickshell: nothing current", (len(st["current"]), len(st["earlier"])), (0, 1))

# 7 old + new errors mixed
st = diaglib.qml_status([e(5, LAUNCH, 1), e(5, BAD, 2), e(9, LAUNCH, 3), e(9, BAD, 4)], 9)
eq("old and new: one each", (len(st["current"]), len(st["earlier"])), (1, 1))

# 8 --since (system-update): errors after the update start count even in earlier runs
st = diaglib.qml_status([e(5, LAUNCH, 1), e(5, BAD, 20), e(9, LAUNCH, 30)], 9, since=10)
eq("since: late error of an earlier run is current", len(st["current"]), 1)

# warnings are not errors
st = diaglib.qml_status([e(9, LAUNCH, 1), e(9, "WARN scene: @Scratchpad.qml[18:5]: Unable to assign [undefined] to bool", 2)], 9)
eq("WARN is not a QML error", st["current"], [])

# --- normalize / harmless / classification
eq("normalize folds numbers/hex", diaglib.normalize("x[123]: 0xdeadbeef at 12.5 s"), diaglib.normalize("x[9]: 0x1 at 3.25 s"))
k = e(None, "kvm_amd: CPU 0 isn't AMD or Hygon", 1, 3, "kernel")
eq("known harmless kvm_amd", bool(diaglib.harmless(k)), True)
eq("unknown message has no explanation", diaglib.harmless(e(None, "something odd", 1, 3, "foo")), None)
cls = diaglib.classify_journal([e(1, "boom", 1, 2, "NetworkManager"), e(2, "pam_unix(sudo:auth): conversation failed", 2, 3, "sudo"),
                                e(3, "odd thing 1", 3, 3, "foo"), e(3, "odd thing 2", 4, 3, "foo"),
                                e(4, "gkr-pam: unable to locate daemon control file", 5, 3, "ly-dm")], False, {})
eq("classification", [(f["severity"], f["component"], f["count"]) for f in cls],
   [("critical", "Netzwerk", 1), ("info", "Rechte (sudo/polkit)", 1), ("warning", "foo", 2), ("info", "Login (Ly)", 1)])
eq("harmless finding carries its reason", bool(cls[3]["note"]), True)
three = diaglib.classify_journal([e(i, "pam_unix(sudo:auth): auth could not identify password", i, 3, "sudo") for i in range(3)], False, {})
eq("3 sudo failures = warning (faillock)", three[0]["severity"], "warning")

burst = [e(None, "efi: mem%d: [Reserved] range=[0x1-0x2] (invalid)" % i, 100, 4, "kernel") for i in range(7)]
spread = [e(None, "usb 1-1: device descriptor read/64, error -71", t, 4, "kernel") for t in (100, 200, 300, 400, 500)]
eq("recurring: a boot burst is not", diaglib.recurring(burst), False)
eq("recurring: 5x over minutes is", diaglib.recurring(spread), True)

# --- pacman.log
LOG = """[2026-10-01T10:00:00+0200] [PACMAN] Running 'pacman -Syu'
[2026-10-01T10:00:01+0200] [PACMAN] starting full system upgrade
[2026-10-01T10:00:02+0200] [ALPM] transaction started
[2026-10-01T10:00:03+0200] [ALPM] upgraded foo (1-1 -> 1-2)
[2026-10-01T10:00:04+0200] [ALPM] transaction completed
[2026-10-02T10:00:02+0200] [ALPM] transaction started
[2026-10-02T10:00:03+0200] [ALPM] error: could not extract bar
[2026-10-02T10:00:04+0200] [ALPM] transaction failed
[2026-10-03T10:00:02+0200] [ALPM] transaction started
[2026-10-03T10:00:03+0200] [ALPM] installed baz (1-1)
[2026-10-03T10:00:04+0200] [ALPM] transaction completed
[2026-10-04T10:00:02+0200] [ALPM] transaction started
[2026-10-04T10:00:03+0200] [ALPM] upgraded qux (1-1 -> 1-2)
""".splitlines(True)
txs = diaglib.parse_pacman_log(LOG, 0)
eq("pacman states", [(t["state"], t["upgrade"], len(t["errors"])) for t in txs],
   [("completed", True, 0), ("failed", False, 1), ("completed", False, 0), ("interrupted", False, 0)])
tmp = tempfile.mkdtemp()
try:
    pl = os.path.join(tmp, "pacman.log")
    with open(pl, "w") as f:
        f.writelines(LOG)
    fs = diaglib.collect_pacman({}, path=pl, days=100000)
    eq("pacman findings", [(f["severity"], f["current"]) for f in fs if f["severity"] != "info"],
       [("warning", False), ("critical", True)])       # failed then fixed = history; interrupted last = current
    eq("pacman info: successes + last upgrade", sorted(f["summary"][:10] for f in fs if f["severity"] == "info"),
       ["2 erfolgre", "Letztes vo"])

    # --- stubs: journalctl failing / empty, nvim, systemctl
    bindir = os.path.join(tmp, "bin")
    os.mkdir(bindir)

    def stub(name, body):
        p = os.path.join(bindir, name)
        with open(p, "w") as f:
            f.write("#!/bin/sh\n" + body + "\n")
        os.chmod(p, 0o755)

    stub("journalctl", 'echo "No journal files were opened due to insufficient permissions." >&2; exit 1')
    old_path = os.environ["PATH"]
    os.environ["PATH"] = bindir + ":" + old_path
    ok, err, es = diaglib.journal(["-b"])
    eq("journal without permission", (ok, "insufficient permissions" in err, es), (False, True, []))
    stub("journalctl", "exit 0")
    eq("empty journal", diaglib.journal(["-b"]), (True, "", []))
    os.environ["PATH"] = old_path

    # --- repo-logs, rendered like Ansible
    v = {}
    v.update(yaml.safe_load(open(os.path.join(ROOT, "roles/diagnostics/defaults/main.yml"))))
    v.update(recovery_enabled=True, diagnostics_lib_dir=os.path.join(ROOT, "roles/diagnostics/files"))
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(os.path.join(ROOT, "roles/diagnostics/templates")),
                             undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
    env.filters["bool"] = bool
    rl = os.path.join(tmp, "repo-logs")
    with open(rl, "w") as f:
        f.write(env.get_template("repo-logs.j2").render(**v))
    seen = os.path.join(tmp, "seen")
    stub("journalctl", 'printf \'%s\\n\' \'{"__REALTIME_TIMESTAMP":"1791642140000000","_PID":"1200","PRIORITY":"3",'
                       '"SYSLOG_IDENTIFIER":"NetworkManager","MESSAGE":"dhcp failed","_BOOT_ID":"b1"}\'')
    # the viewer stub records its argv and the file it got (then the copy must be gone)
    stub("nvim", 'for a; do last="$a"; done; printf "%%s\\n" "$@" > "{0}.argv"; cat "$last" > "{0}"; '
                 'stat -c %%a "$last" > "{0}.mode"'.format(seen).replace("%%", "%"))
    stub("systemctl", "exit 0")
    stub("coredumpctl", "exit 1")
    stub("hyprctl", "exit 1")
    runtime = os.path.join(tmp, "run")
    os.mkdir(runtime, 0o700)
    renv = dict(os.environ, PATH=bindir + ":" + old_path, XDG_RUNTIME_DIR=runtime, NO_COLOR="1")

    def rlogs(*args):
        r = subprocess.run([sys.executable, rl] + list(args), capture_output=True, text=True, env=renv, timeout=60, stdin=subprocess.DEVNULL)
        return r.returncode, r.stdout, r.stderr

    # repo-healthcheck / repo-diagnose (they import diaglib): render + compile
    hv = dict(yaml.safe_load(open(os.path.join(ROOT, "group_vars/all.yml"))), **v)
    for role in ("theme", "display_manager"):
        d = os.path.join(ROOT, "roles", role, "defaults/main.yml")
        if os.path.exists(d):
            hv = dict(yaml.safe_load(open(d)) or {}, **hv)
    hv.update(playbook_dir=ROOT, ssh_server_enabled=True)
    for t in ("repo-healthcheck.j2", "repo-diagnose.j2", "repo-logs.j2"):
        src = env.get_template(t).render(**hv)
        try:
            compile(src, t, "exec")
        except SyntaxError as ex:
            eq("%s compiles" % t, str(ex), "")

    rc, out, _ = rlogs("sources", "--json")
    eq("sources", [s["id"] for s in json.loads(out)],
       ["journal", "boot", "boot-errors", "kernel", "user", "pacman", "quickshell", "hyprland", "firewall", "snapper", "updates"])
    rc, out, _ = rlogs("view", "boot-errors")
    eq("view rc", rc, 0)
    text = open(seen).read()
    eq("view: formatted journal line", "ERR    NetworkManager[1200]: dhcp failed" in text, True)
    eq("view: header names the query", "# journalctl -b -p 0..3" in text, True)
    eq("view: copy read-only", open(seen + ".mode").read().strip(), "400")
    argv = open(seen + ".argv").read().split("\n")
    eq("view: nvim -R -M -n", argv[:3], ["-R", "-M", "-n"])
    eq("view: copy deleted afterwards", os.listdir(os.path.join(runtime, "workstation-logs")), [])
    rc, _, err = rlogs("view", "../../etc/shadow")
    eq("view: unknown source refused", (rc, "unknown source" in err), (2, True))
    rc, _, err = rlogs("view", "boot", "-x")
    eq("usage error", rc, 2)
    rc, out, _ = rlogs("analyze", "--json")
    res = json.loads(out)
    eq("analyze json: NetworkManager err = warning finding",
       [(f["severity"], f["component"]) for f in res["findings"] if f["summary"] == "dhcp failed"][:1], [("warning", "Netzwerk")])
    rc, out, _ = rlogs("analyze")
    eq("analyze text: summary line", "Aktuell:  Critical: " in out and "Historisch:" in out, True)
    stub("journalctl", 'echo "No journal files were opened due to insufficient permissions." >&2; exit 1')
    rc, out, _ = rlogs("view", "kernel")
    eq("view without permission: says so, still opens", "nicht verfügbar: No journal files" in open(seen).read(), True)
finally:
    shutil.rmtree(tmp)

print("diaglib: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
