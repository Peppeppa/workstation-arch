#!/usr/bin/env python3
"""Minimal resumable test controller for supervised hardware tests.

Runs on the CONTROLLING machine, never on the test host. One plan (JSON)
lists tests; each test is a list of steps run over SSH. State is a JSON
file next to the logs, written atomically after every transition, so the
controller can be killed at any point and resumed with the same command.

Guarantees:
- a step marked "destructive" is launched at most once: the run id is
  checkpointed before the launch and the remote side refuses a second
  launch of the same run id (atomic mkdir marker); a resumed controller
  never relaunches it, it only collects or verifies
- remote commands run detached with their own timeout and write
  <run>.out / <run>.rc on the host, so a dropped SSH connection loses no
  result: the controller reconnects and fetches it
- every wait is finite; SSH loss -> grace wait, bounded polling, then
  WAITING_FOR_LOCAL_INTERVENTION (exit 3)
- one controller per state directory (flock); a second one exits 4

Step kinds:
  remote   cmd, timeout, expect_rc (default 0), expect_re, capture (var
           name for stripped stdout), destructive, expect_disconnect
           (launch only; the outcome is verified by later steps),
           retries (non-destructive only), sudo (run under sudo, password
           from --secret-stdin over the SSH stdin; synchronous launch),
           secret_to_cmd (with sudo: the command reads the password once
           more from its stdin, e.g. to type it into a login screen)
  wait_ssh initial_delay, timeout, interval, require_new_boot (boot id
           differs from var "boot_id")
  approve  text - stops with AWAITING_APPROVAL until `approve <test>`
  note     text - recorded only

Exit codes: 0 all requested tests PASS, 1 a test FAILED, 2 BLOCKED /
awaiting approval, 3 WAITING_FOR_LOCAL_INTERVENTION, 4 already running,
5 usage / plan error.
"""
import argparse
import fcntl
import json
import os
import re
import shlex
import subprocess
import sys
import time

FINAL = {"PASS", "FAIL", "BLOCKED", "DEFERRED", "NOT_EXECUTED"}
SCALE = float(os.environ.get("TESTCTL_TIME_SCALE", "1"))   # simulations only
SSH = shlex.split(os.environ.get("TESTCTL_SSH", "ssh"))
SUDO = os.environ.get("TESTCTL_SUDO", "sudo -S -p ''")             # simulations: a stub
REMOTE_DIR = ".cache/testctl"


def now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def sleep(seconds):
    time.sleep(seconds * SCALE)


class Ctl:
    def __init__(self, state_dir, plan, hosts):
        self.dir = state_dir
        self.plan = plan
        self.hosts = hosts             # [[label, ssh args...], ...]
        os.makedirs(os.path.join(state_dir, "logs"), exist_ok=True)
        self.state_path = os.path.join(state_dir, "state.json")
        self.state = self.load()
        self.secret = None             # sudo password, memory only (--secret-stdin)
        for k, v in plan.get("vars", {}).items():
            self.state["vars"].setdefault(k, v)

    # ---- state ------------------------------------------------------------
    def load(self):
        try:
            with open(self.state_path) as f:
                return json.load(f)
        except FileNotFoundError:
            # the session token keeps run ids of a fresh state apart from old
            # remote results (~/.cache/testctl on the host survives)
            return {"session": os.urandom(3).hex(), "tests": {}, "vars": {}, "events": []}

    def save(self):
        tmp = self.state_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.state, f, indent=1)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.state_path)

    def event(self, test, msg):
        line = f"{now()} [{test}] {msg}"
        self.state["events"].append(line)
        self.state["events"] = self.state["events"][-400:]
        print(line, flush=True)
        self.save()

    def t(self, tid):
        return self.state["tests"].setdefault(tid, {"status": "PENDING", "step": 0, "runs": {}})

    def log(self, name, text):
        with open(os.path.join(self.dir, "logs", name), "a") as f:
            f.write(text)

    # ---- transport ----------------------------------------------------------
    def ssh(self, cmd, timeout, stdin=None):
        """One SSH call over the first host that answers. Returns (rc, out) or
        (None, err) when no host could be reached."""
        last = ""
        for label, *args in self.hosts:
            argv = SSH + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                          "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2"] + args + [cmd]
            try:
                p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout * SCALE + 15, input=stdin)
            except subprocess.TimeoutExpired:
                last = f"{label}: local timeout"
                continue
            if p.returncode == 255:               # ssh's own failure (no connection)
                last = f"{label}: {p.stderr.strip()[-200:]}"
                continue
            return p.returncode, p.stdout
        return None, last

    def reachable(self, timeout=20):
        rc, _ = self.ssh("true", timeout)
        return rc == 0

    def wait_reconnect(self, tid, grace, window, interval):
        """SSH dropped: grace wait, then bounded polling. True when back."""
        self.event(tid, f"SSH unreachable - waiting {grace}s, then polling up to {window}s")
        sleep(grace)
        deadline = time.monotonic() + window * SCALE
        while time.monotonic() < deadline:
            if self.reachable():
                self.event(tid, "SSH back")
                return True
            sleep(interval)
        return False

    # ---- remote run protocol -------------------------------------------------
    def launch(self, run, cmd, timeout, sudo=False, to_cmd=False):
        d = REMOTE_DIR
        if sudo:
            # synchronous: the password goes over this SSH call's stdin into
            # sudo only (never a file or argv); for a reboot the call drops
            # and the marker alone says "launched"
            if self.secret is None:
                raise SystemExit("this step needs --secret-stdin")
            script = (
                f"mkdir -p {d} && cd {d} && "
                f"if mkdir {run}.lock 2>/dev/null; then "
                f"printf %s {shlex.quote(cmd)} > {run}.cmd; R=$HOME/{d}/{run}; cd; "
                f"timeout {int(timeout)} {SUDO} bash $R.cmd > $R.out 2>&1; "
                f"echo $? > $R.rc.tmp && mv $R.rc.tmp $R.rc; echo LAUNCHED; else echo EXISTS; fi")
            return self.ssh(script, timeout + 30, stdin=(self.secret + "\n") * (2 if to_cmd else 1))
        script = (
            f"mkdir -p {d} && cd {d} && "
            f"if mkdir {run}.lock 2>/dev/null; then "
            f"printf %s {shlex.quote(cmd)} > {run}.cmd; "
            f"setsid nohup sh -c 'R=$HOME/{d}/{run}; cd; timeout {int(timeout)} bash $R.cmd > $R.out 2>&1; "
            f"echo $? > $R.rc.tmp && mv $R.rc.tmp $R.rc' </dev/null >/dev/null 2>&1 & "
            f"echo LAUNCHED; else echo EXISTS; fi")
        return self.ssh(script, 30)

    def collect(self, run):
        d = REMOTE_DIR
        rc, out = self.ssh(
            f"cd {d} 2>/dev/null || {{ echo NODIR; exit 0; }}; "
            f"if [ -e {run}.rc ]; then echo DONE $(cat {run}.rc); cat {run}.out; "
            f"elif [ -d {run}.lock ]; then echo RUNNING; else echo UNKNOWN; fi", 60)
        if rc is None:
            return None, None, None
        head, _, body = out.partition("\n")
        if head.startswith("DONE"):
            return "DONE", int(head.split()[1]), body
        return head.strip(), None, None

    # ---- steps ---------------------------------------------------------------
    def subst(self, text):
        return re.sub(r"\{(\w+)\}", lambda m: str(self.state["vars"].get(m.group(1), m.group(0))), text)

    def step_remote(self, tid, st, i, ts):
        cmd = self.subst(st["cmd"])
        timeout = st.get("timeout", 120)
        destructive = st.get("destructive", False)
        retries = 0 if destructive else st.get("retries", 1)
        key = str(i)
        runinfo = ts["runs"].setdefault(key, {"attempt": 0, "phase": "new"})
        while True:
            run = f"{self.state.get('session', 's')}.{tid}.{i}.{runinfo['attempt']}"
            run = re.sub(r"[^A-Za-z0-9_.-]", "_", run)
            if runinfo["phase"] == "new":
                runinfo.update(phase="launching", run=run, at=now())
                self.save()                                  # checkpoint BEFORE launch
                rc, out = self.launch(run, cmd, timeout, st.get("sudo", False), st.get("secret_to_cmd", False))
                if rc is None:
                    if destructive:
                        # did it start? only the remote marker can tell - never guess
                        self.event(tid, f"step {i}: launch of destructive {run} unconfirmed; will verify marker")
                    elif not self.wait_reconnect(tid, *self.ssh_policy()):
                        return "WAIT"
                    continue
                runinfo["phase"] = "launched"
                self.save()
                self.event(tid, f"step {i}: {out.strip()} {run}" + (" (destructive)" if destructive else ""))
            if runinfo["phase"] == "launching":
                state, _, _ = self.collect(run)
                if state is None:
                    if not self.wait_reconnect(tid, *self.ssh_policy()):
                        return "WAIT"
                    continue
                if state in ("UNKNOWN", "NODIR"):
                    if destructive:
                        # marker absent: the launch never reached the host - safe to launch once
                        self.event(tid, f"step {i}: no marker for {run} - launch never arrived, launching")
                    runinfo["phase"] = "new"
                    continue
                runinfo["phase"] = "launched"
                self.save()
            if st.get("expect_disconnect"):
                runinfo["phase"] = "done"
                self.save()
                return "OK"
            # poll for the result
            deadline = time.monotonic() + timeout + 30      # real: the remote side has its own timeout
            result = None
            while time.monotonic() < deadline:
                state, rc, body = self.collect(run)
                if state is None:
                    if not self.wait_reconnect(tid, *self.ssh_policy()):
                        return "WAIT"
                    deadline = max(deadline, time.monotonic() + 60 * SCALE)
                    continue
                if state == "DONE":
                    result = (rc, body)
                    break
                if state in ("UNKNOWN", "NODIR"):
                    result = ("lost", "")
                    break
                sleep(st.get("poll", 3))
            if result is None:
                result = ("timeout", "")
            rc, body = result
            self.log(f"{run}.log", f"$ {cmd}\n{body}\n[rc={rc}]\n")
            ok = rc == st.get("expect_rc", 0)
            if ok and st.get("expect_re") and not re.search(self.subst(st["expect_re"]), body or "", re.M):
                ok = False
            if ok:
                if st.get("capture"):
                    self.state["vars"][st["capture"]] = (body or "").strip()
                runinfo["phase"] = "done"
                self.save()
                self.event(tid, f"step {i} ok: {st.get('name', cmd[:60])}")
                return "OK"
            tail = (body or "").strip().splitlines()[-3:]
            if not destructive and runinfo["attempt"] < retries and rc == "lost":
                runinfo.update(attempt=runinfo["attempt"] + 1, phase="new")
                self.event(tid, f"step {i}: {rc}, retry {runinfo['attempt']}/{retries}")
                continue
            ts["note"] = f"step {i} ({st.get('name', '')}): rc={rc} {' | '.join(tail)}"
            return "FAIL"

    def ssh_policy(self):
        p = self.plan.get("ssh_policy", {})
        return p.get("grace", 120), p.get("window", 600), p.get("interval", 10)

    def step_wait_ssh(self, tid, st, ts):
        sleep(st.get("initial_delay", 0))
        deadline = time.monotonic() + st.get("timeout", 900) * SCALE
        while time.monotonic() < deadline:
            rc, out = self.ssh("cat /proc/sys/kernel/random/boot_id", 20)
            if rc == 0:
                bid = out.strip()
                if st.get("require_new_boot") and bid == self.state["vars"].get("boot_id"):
                    sleep(st.get("interval", 10))
                    continue
                self.state["vars"]["boot_id"] = bid
                self.event(tid, f"SSH up, boot id {bid[:8]}")
                return "OK"
            sleep(st.get("interval", 10))
        return "WAIT"

    # ---- tests ---------------------------------------------------------------
    def run_test(self, tid):
        test = self.plan["tests"].get(tid)
        if test is None:
            print(f"unknown test {tid}", file=sys.stderr)
            return 5
        ts = self.t(tid)
        if ts["status"] in FINAL:
            print(f"[{tid}] already {ts['status']} - not rerun", flush=True)
            return 0 if ts["status"] == "PASS" else 1 if ts["status"] == "FAIL" else 2
        for dep in test.get("requires", []):
            ds = self.t(dep)["status"]
            if ds != "PASS":
                ts.update(status="BLOCKED", note=f"requires {dep} PASS (is {ds})", ended=now())
                self.event(tid, f"BLOCKED: {ts['note']}")
                return 2
        if ts["status"] == "PENDING":
            ts.update(status="RUNNING", started=now())
            self.event(tid, f"start: {test.get('title', '')}")
        steps = test["steps"]
        while ts["step"] < len(steps):
            i = ts["step"]
            st = steps[i]
            kind = st.get("kind", "remote")
            if kind == "approve":
                if ts.get("approved_step") != i:
                    ts["status"] = "AWAITING_APPROVAL"
                    self.event(tid, f"AWAITING_APPROVAL: {st['text']}")
                    return 2
                res = "OK"
            elif kind == "note":
                self.event(tid, st["text"])
                res = "OK"
            elif kind == "wait_ssh":
                ts["status"] = "WAITING_SSH"
                self.save()
                res = self.step_wait_ssh(tid, st, ts)
            else:
                ts["status"] = "RUNNING"
                res = self.step_remote(tid, st, i, ts)
            if res == "WAIT":
                ts["status"] = "WAITING_FOR_LOCAL_INTERVENTION"
                self.event(tid, "WAITING_FOR_LOCAL_INTERVENTION (rerun the same command to keep waiting)")
                return 3
            if res == "FAIL":
                ts.update(status="FAIL", ended=now())
                self.event(tid, f"FAIL: {ts['note']}")
                return 1
            ts["step"] = i + 1
            ts["status"] = "RUNNING"
            self.save()
        ts.update(status="PASS", ended=now())
        self.event(tid, "PASS")
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--plan", required=True)
    ap.add_argument("--host", action="append", default=[],
                    help="label=ssh-args (repeatable, tried in order), e.g. eth='-p 22 user@10.0.0.2'")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("tests", nargs="+")
    sub.add_parser("status")
    a = sub.add_parser("approve")
    a.add_argument("test")
    ap.add_argument("--secret-stdin", action="store_true", help="read the sudo password (one line) from stdin")
    m = sub.add_parser("mark")
    m.add_argument("test")
    m.add_argument("status", choices=sorted(FINAL))
    m.add_argument("note")
    args = ap.parse_args()

    with open(args.plan) as f:
        plan = json.load(f)
    hosts = []
    for h in args.host:
        label, _, rest = h.partition("=")
        hosts.append([label] + shlex.split(rest))

    os.makedirs(args.state, exist_ok=True)
    lock = open(os.path.join(args.state, "lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("another controller holds this state - not starting", file=sys.stderr)
        return 4
    ctl = Ctl(args.state, plan, hosts)
    if args.secret_stdin:
        ctl.secret = sys.stdin.readline().rstrip("\n")

    if args.cmd == "status":
        for tid in plan["tests"]:
            ts = ctl.state["tests"].get(tid, {"status": "PENDING"})
            print(f"{tid:10} {ts['status']:32} {ts.get('note', '')}")
        return 0
    if args.cmd == "approve":
        ts = ctl.t(args.test)
        if ts["status"] != "AWAITING_APPROVAL":
            print(f"{args.test} is {ts['status']}, nothing to approve", file=sys.stderr)
            return 5
        ts["approved_step"] = ts["step"]
        ts["status"] = "RUNNING"
        ctl.event(args.test, "approved by the user")
        return 0
    if args.cmd == "mark":
        ts = ctl.t(args.test)
        ts.update(status=args.status, note=args.note, ended=now())
        ctl.event(args.test, f"marked {args.status}: {args.note}")
        return 0
    worst = 0
    for tid in args.tests:
        rc = ctl.run_test(tid)
        worst = max(worst, rc)
        if rc in (3, 4):
            break
    return worst


if __name__ == "__main__":
    sys.exit(main())
