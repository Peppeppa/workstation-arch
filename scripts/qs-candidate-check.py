#!/usr/bin/env python3
"""Load-test a candidate Quickshell config before it is deployed (test tool,
never deployed, never run by Ansible).

Run ON the test machine, as the desktop user, inside the graphical session:
    qs-candidate-check.py <repo-source-dir> [seconds=8] [target:fn[:arg] ...]
<repo-source-dir> holds roles/, group_vars/, host_vars/ of the candidate
(e.g. copied there with tar). The tool
  1. copies the DEPLOYED ~/.config/quickshell to /tmp/qs-candidate,
  2. overlays the candidate's QML files with the same mapping as
     roles/quickshell/tasks/main.yml and renders its three templates with
     Jinja2 from the role defaults + group_vars/all.yml + host_vars/<host>.yml,
  3. drops everything that owns a D-Bus name or changes state (notifications,
     power policy, portal watcher, battery watcher, wallpaper; tray off),
  4. starts `quickshell -p /tmp/qs-candidate` with the production
     Quickshell's environment under a 4 GB address-space limit and a hard
     timeout, waits for "Configuration Loaded" (or an error), lets it run
     <seconds>, terminates it and prints a JSON report of ERROR/WARN lines.
With actions: after loading, each `qs ipc -p <config> call target fn [arg]`
runs on the TEST instance, then (only if no hyprlock is running - a locked
session is never screenshotted as if it were the desktop) one grim
screenshot to /tmp/qs-candidate-shots/NN-target-fn.png, then
`shell closeActive`. Only read-only surfaces belong in the list (never
firewall/scratchpad: pkexec prompt / a second writer of the note file).
The running desktop is not touched; a second bar is visible for a moment.
Exit 0 = loaded without QML errors.
"""
import json, os, re, shutil, signal, subprocess, sys, time

import jinja2
import yaml

SRC = os.path.abspath(sys.argv[1])
SECONDS = int(sys.argv[2]) if len(sys.argv) > 2 else 8
ACTIONS = sys.argv[3:]
SHOTS = "/tmp/qs-candidate-shots"
DEST = "/tmp/qs-candidate"
HOME = os.path.expanduser("~")
QS = os.path.join(SRC, "roles/quickshell")
host = os.uname().nodename

# ---- variables (role defaults < group_vars < host_vars, like Ansible) -------
v = {}
for role in sorted(os.listdir(os.path.join(SRC, "roles"))):
    p = os.path.join(SRC, "roles", role, "defaults/main.yml")
    if os.path.exists(p):
        v.update(yaml.safe_load(open(p)) or {})
v.update(yaml.safe_load(open(os.path.join(SRC, "group_vars/all.yml"))) or {})
hv = os.path.join(SRC, "host_vars/%s.yml" % host)
if os.path.exists(hv):
    v.update(yaml.safe_load(open(hv)) or {})
v["ansible_facts"] = {"user_dir": HOME, "nodename": host}
v["playbook_dir"] = os.path.join(HOME, "repos/Peppeppa/workstation-arch")
v.setdefault("power_menu_hibernate_available", False)
env_j = jinja2.Environment(loader=jinja2.FileSystemLoader(os.path.join(QS, "templates")), keep_trailing_newline=True,
                           trim_blocks=True)
env_j.filters["to_json"] = json.dumps
env_j.filters["bool"] = lambda x: x if isinstance(x, bool) else str(x).lower() in ("true", "yes", "1", "on")


def render(name, dest):
    # Jinja in Ansible evaluates nested templates in variables; ours are plain
    for _ in range(3):
        for k, val in list(v.items()):
            if isinstance(val, str) and "{{" in val:
                try:
                    v[k] = jinja2.Template(val).render(**v)
                except jinja2.exceptions.UndefinedError:
                    pass  # needs a fact this tool does not gather; unused by the QML templates
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "w").write(env_j.get_template(name).render(**v))


# ---- build ---------------------------------------------------------------
shutil.rmtree(DEST, ignore_errors=True)
shutil.copytree(os.path.join(HOME, ".config/quickshell"), DEST, symlinks=True)
F = os.path.join(QS, "files")


def cp(src, dst):
    s, d = os.path.join(F, src), os.path.join(DEST, dst)
    if os.path.isdir(s):
        shutil.copytree(s, d, dirs_exist_ok=True)
    else:
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copy(s, d)


BASELINE = os.environ.get("QS_CAND_BASELINE") == "1"   # the deployed config as is (comparison run)
if not BASELINE:
    cp("quickshell", ".")
    for s, d in [("PowerMenu.qml", "PowerMenu.qml"), ("updates/Updates.qml", "updates/Updates.qml"),
                 ("updates/UpdaterDialog.qml", "updates/UpdaterDialog.qml"), ("updates/SnapshotDialog.qml", "updates/SnapshotDialog.qml"),
                 ("updates/SnapshotMode.qml", "updates/SnapshotMode.qml"), ("updates/Widget.qml", "bar/widgets/Updates/Widget.qml"),
                 ("Notifications.qml", "Notifications.qml"), ("tray", "bar/widgets/Tray"), ("audio", "bar/widgets/Audio"),
                 ("connectivity/Popup.qml", "bar/widgets/Connectivity/Popup.qml"), ("connectivity/PortalWatcher.qml", "PortalWatcher.qml"),
                 ("clipboard/ClipboardHistory.qml", "ClipboardHistory.qml"), ("wallpaper/Wallpaper.qml", "Wallpaper.qml"),
                 ("wallpaper/WallpaperPicker.qml", "bar/widgets/Theme/WallpaperPicker.qml")]:
        cp(s, d)
    for f in os.listdir(os.path.join(F, "bluetooth")):
        if f.endswith(".qml"):
            cp("bluetooth/" + f, "bar/widgets/Bluetooth/" + f)
    render("Fonts.qml.j2", os.path.join(DEST, "Fonts.qml"))
    render("BarFeatures.qml.j2", os.path.join(DEST, "bar/BarFeatures.qml"))
    render("shell.qml.j2", os.path.join(DEST, "shell.qml"))

# no tray host, no D-Bus owners, nothing that changes state
bf = open(os.path.join(DEST, "bar/BarFeatures.qml")).read()
open(os.path.join(DEST, "bar/BarFeatures.qml"), "w").write(re.sub(r"(property bool tray: )\w+", r"\1false", bf))
shell = open(os.path.join(DEST, "shell.qml")).read()
out, skip, depth = [], False, 0
for line in shell.splitlines(True):
    if not skip and re.match(r"^    (Notifications|PowerPolicy|PortalWatcher|BatteryWatcher|Wallpaper) \{", line):
        skip, depth = True, 0
    if skip:
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            skip = False
        continue
    out.append(line)
open(os.path.join(DEST, "shell.qml"), "w").write("".join(out))

# QS_CAND_COLORS=<colors.json>: the test instance reads that file instead of
# the user's (another theme / mode / text size for the visual audit - the
# user's theme state is never touched)
if os.environ.get("QS_CAND_COLORS"):
    cq = os.path.join(DEST, "Colors.qml")
    c = open(cq).read()
    c2 = re.sub(r'path: \(Quickshell\.env\("XDG_CONFIG_HOME"\)[^\n]*\n\s*\+ "/workstation/theme/colors\.json"',
                'path: ' + json.dumps(os.path.abspath(os.environ["QS_CAND_COLORS"])), c)
    if c2 == c:
        sys.exit("QS_CAND_COLORS: Colors.qml path not found")
    open(cq, "w").write(c2)

# ---- run -------------------------------------------------------------------
prod = None
for p in os.listdir("/proc"):
    try:
        if p.isdigit() and open("/proc/%s/cmdline" % p, "rb").read().strip(b"\0") == b"quickshell":
            prod = int(p)
    except OSError:
        pass
env = dict(kv.split("=", 1) for kv in open("/proc/%d/environ" % prod, "rb").read().decode(errors="replace").split("\0") if "=" in kv)
env.pop("INVOCATION_ID", None)
t0 = time.monotonic()
p = subprocess.Popen(["prlimit", "--as=4000000000", "timeout", str(SECONDS + 90), "quickshell", "-p", DEST],
                     env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
os.set_blocking(p.stdout.fileno(), False)
lines, loaded = [], None
shots, locked, ipc_errors, measured = [], False, [], None
while time.monotonic() - t0 < SECONDS + 20:
    try:
        l = p.stdout.readline()
    except (IOError, TypeError):
        l = ""
    if l:
        lines.append(l.rstrip())
        if "Configuration Loaded" in l and loaded is None:
            loaded = round(time.monotonic() - t0, 3)
            deadline = time.monotonic() + SECONDS
        if "Failed to load configuration" in l:
            break
    else:
        if p.poll() is not None:
            break
        if loaded is not None and time.monotonic() > deadline:
            break
        time.sleep(0.02)
    if loaded is not None and os.environ.get("QS_CAND_MEASURE") == "1" and p.poll() is None:
        # bounded: 15 s settle + 30 s CPU window, then PSS of the test quickshell
        time.sleep(15)
        qp = [q for q in os.listdir("/proc") if q.isdigit() and os.path.exists("/proc/%s/cmdline" % q)
              and open("/proc/%s/cmdline" % q, "rb").read().split(b"\0")[:3] == [b"quickshell", b"-p", DEST.encode()]]
        def ticks(q):
            f = open("/proc/%s/stat" % q).read().rsplit(")", 1)[1].split()
            return int(f[11]) + int(f[12])
        t0c, w0 = ticks(qp[0]), time.monotonic()
        time.sleep(30)
        cpu = 100.0 * (ticks(qp[0]) - t0c) / os.sysconf("SC_CLK_TCK") / (time.monotonic() - w0)
        roll = {m.group(1): int(m.group(2)) for m in re.finditer(r"(\w+):\s+(\d+) kB", open("/proc/%s/smaps_rollup" % qp[0]).read())}
        measured = {"pss_mb": round(roll["Pss"] / 1024, 1), "rss_mb": round(roll["Rss"] / 1024, 1),
                    "swap_mb": round(roll.get("Swap", 0) / 1024, 1), "cpu_pct": round(cpu, 3)}
        break
    if loaded is not None and ACTIONS and p.poll() is None:
        shots, locked = [], any(open("/proc/%s/comm" % q).read().strip() == "hyprlock"
                                for q in os.listdir("/proc") if q.isdigit() and os.path.exists("/proc/%s/comm" % q))
        shutil.rmtree(SHOTS, ignore_errors=True)
        os.makedirs(SHOTS)
        qpid = None                      # the test quickshell (a child of timeout)
        for q in os.listdir("/proc"):
            try:
                if q.isdigit() and open("/proc/%s/cmdline" % q, "rb").read().split(b"\0")[:3] == [b"quickshell", b"-p", DEST.encode()]:
                    qpid = q
            except OSError:
                pass
        ipc = ["timeout", "5", "qs", "ipc", "--pid", str(qpid), "call"]
        ipc_errors = []
        for n, a in enumerate(ACTIONS):
            parts = a.split(":")
            r = subprocess.run(ipc + parts, env=env, capture_output=True, text=True)
            if r.returncode != 0:
                ipc_errors.append("%s: %s" % (a, (r.stderr or r.stdout).strip()[:200]))
            time.sleep(1.5)
            if not locked:
                f = os.path.join(SHOTS, "%02d-%s.png" % (n, "-".join(parts)))
                subprocess.run(["timeout", "10", "grim", f], env=env, capture_output=True)
                shots.append(f)
            subprocess.run(ipc + ["shell", "closeActive"], env=env, capture_output=True)
            time.sleep(0.5)
        try:
            while True:
                l = p.stdout.readline()
                if not l:
                    break
                lines.append(l.rstrip())
        except (IOError, TypeError):
            pass
        break
try:
    os.killpg(p.pid, signal.SIGTERM)
    p.wait(10)
except (ProcessLookupError, subprocess.TimeoutExpired):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
try:
    lines += [l.rstrip() for l in (p.stdout.read() or "").splitlines()]
except (IOError, TypeError, ValueError):
    pass
noise = re.compile(r"locale|UTF-8|reconfigure your locale|for more information|qt.qpa.wayland.textinput")
errors = [l for l in lines if re.search(r"ERROR|TypeError|ReferenceError|Binding loop|is not a type|Cannot (read|assign)", l)]
warns = [l for l in lines if "WARN" in l and not noise.search(l) and l not in errors]
shutil.rmtree(DEST, ignore_errors=True)
report = {"loaded_s": loaded, "errors": errors[:40], "warnings": warns[:40]}
if measured:
    report["measured"] = measured
if ACTIONS:
    report["screenshots"] = "locked session - none taken" if locked else shots
    report["ipc_errors"] = ipc_errors
print(json.dumps(report, indent=1, ensure_ascii=False))
sys.exit(0 if loaded is not None and not errors else 1)
