#!/usr/bin/env python3
"""RICE v1 performance measurements (docs/RICE_PERFORMANCE_BASELINE.md).

A test tool: never deployed, never run by Ansible. Copy it to the machine
and run it there as the desktop user inside the graphical session:
    python3 rice-measure.py [idle-seconds=120] [runs=3]
Results: /tmp/rice-measure.json (written after every section). Leave the
machine untouched while it runs (~10 min); during the wallpaper part a test
background layer and a fullscreen throwaway window appear for ~2 minutes.
Needs: quickshell, hyprctl, ghostty, ffmpeg, prlimit (util-linux).


- production processes: RSS/PSS/private from /proc/<pid>/smaps_rollup, CPU
  from utime+stime over a window, process counts
- isolated Quickshell test instances (`quickshell -p <dir>`, the production
  process' own environment): empty ShellRoot vs. the overlays only (no bar,
  notifications, tray, wallpaper, power policy, portal watcher - nothing that
  owns a D-Bus name or changes state); time to "Configuration Loaded", PSS
  after settling, idle CPU
- wallpaper: a background-layer test instance with the production PNG vs. a
  temporary GIF (generated from it in /tmp), visible and covered by a
  fullscreen throwaway window; Hyprland CPU in the same window
Every test instance is terminated afterwards; nothing is written outside /tmp.
"""
import json, os, re, shutil, signal, subprocess, sys, time

HZ = os.sysconf("SC_CLK_TCK")
OUT = {}
RESULT = "/tmp/rice-measure.json"


def save():
    """after every section: a crash later never loses what was measured"""
    json.dump(OUT, open(RESULT + ".tmp", "w"), indent=1, ensure_ascii=False)
    os.replace(RESULT + ".tmp", RESULT)


def smaps(pid):
    d = {}
    try:
        for l in open("/proc/%d/smaps_rollup" % pid):
            m = re.match(r"(\w+):\s+(\d+) kB", l)
            if m:
                d[m.group(1)] = int(m.group(2))
    except OSError:
        return None
    # swapped-out pages are not in Rss/Pss: a process pushed to swap looks
    # smaller than it is (2026-10-10: after an OOM event) - report them
    return {"rss_mb": round(d.get("Rss", 0) / 1024, 1), "pss_mb": round(d.get("Pss", 0) / 1024, 1),
            "private_mb": round((d.get("Private_Clean", 0) + d.get("Private_Dirty", 0)) / 1024, 1),
            "swap_mb": round(d.get("Swap", 0) / 1024, 1)}


def ticks(pid):
    try:
        f = open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()
        return int(f[11]) + int(f[12])
    except OSError:
        return None


def cpu_pct(pids, seconds):
    a = {p: ticks(p) for p in pids}
    t0 = time.monotonic()
    time.sleep(seconds)
    dt = time.monotonic() - t0
    b = {p: ticks(p) for p in pids}
    return {p: round(100.0 * (b[p] - a[p]) / HZ / dt, 2) for p in pids if a[p] is not None and b[p] is not None}


def pids_of(comm, exact_cmd=None):
    out = []
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            if open("/proc/%s/comm" % p).read().strip() != comm:
                continue
            if exact_cmd is not None and open("/proc/%s/cmdline" % p, "rb").read().replace(b"\0", b" ").strip() != exact_cmd:
                continue
            out.append(int(p))
        except OSError:
            pass
    return sorted(out)


prod_qs = pids_of("quickshell", b"quickshell")[0]
env = dict(kv.split("=", 1) for kv in open("/proc/%d/environ" % prod_qs, "rb").read().decode(errors="replace").split("\0") if "=" in kv)
env.pop("INVOCATION_ID", None)


def hypr(*args):
    return subprocess.run(["hyprctl"] + list(args), env=env, capture_output=True, text=True).stdout


# ---- 0.1 production ---------------------------------------------------------
procs = {"quickshell": prod_qs, "Hyprland": pids_of("Hyprland")[0]}
for c in ("hyprpolkitagent", "hypridle", "wl-paste", "pipewire", "wireplumber", "pipewire-pulse", "xdg-desktop-portal",
          "xdg-desktop-por", "NetworkManager", "upowerd", "power-profiles-", "bluetoothd"):
    p = pids_of(c)
    if p:
        procs[c] = p[0]
OUT["production"] = {c: smaps(p) for c, p in procs.items()}
OUT["counts"] = {"quickshell(desktop)": len(pids_of("quickshell", b"quickshell")), "quickshell(all)": len(pids_of("quickshell")),
                 "Hyprland": len(pids_of("Hyprland"))}
idle_window = int(sys.argv[1]) if len(sys.argv) > 1 else 120
OUT["production_cpu_pct"] = {c: v for c, v in zip(procs, cpu_pct(list(procs.values()), idle_window).values())}
OUT["production_cpu_window_s"] = idle_window
OUT["hyprlock_running"] = bool(pids_of("hyprlock"))
save()


# ---- test instances ---------------------------------------------------------
BASE = "/tmp/qs-measure"
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
src = os.path.expanduser("~/.config/quickshell")


def variant(name, shell_qml, copy_tree):
    d = os.path.join(BASE, name)
    if copy_tree:
        shutil.copytree(src, d, symlinks=True)
    else:
        os.makedirs(d)
    open(os.path.join(d, "shell.qml"), "w").write(shell_qml)
    return d


prod_shell = open(os.path.join(src, "shell.qml")).read()


def strip(qml, names):
    """Remove top-level ShellRoot children (4-space indented blocks) by type name."""
    out, skip, depth = [], False, 0
    for line in qml.splitlines(True):
        if not skip and re.match(r"^    (%s) \{" % "|".join(names), line):
            skip, depth = True, 0
        if skip:
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                skip = False
            continue
        out.append(line)
    return "".join(out)


EMPTY = "import QtQuick\nimport Quickshell\nShellRoot {}\n"
overlays_qml = strip(prod_shell, ["Variants", "BatteryWatcher", "PowerPolicy", "Wallpaper", "PortalWatcher", "Notifications"])


def run_instance(d, settle=15, cpu_window=30, during=None):
    t0 = time.monotonic()
    p = subprocess.Popen(["quickshell", "-p", d], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         start_new_session=True)
    loaded, errors, lines = None, [], []
    os.set_blocking(p.stdout.fileno(), False)
    while time.monotonic() - t0 < 20 and loaded is None:
        try:
            l = p.stdout.readline()
        except (IOError, TypeError):
            l = ""
        if l:
            lines.append(l.rstrip())
            if "Configuration Loaded" in l:
                loaded = round(time.monotonic() - t0, 3)
            if "ERROR" in l:
                errors.append(l.strip()[:160])
        else:
            if p.poll() is not None:
                break
            time.sleep(0.01)
    time.sleep(settle)
    if during:
        during()
    pid = p.pid
    mem = smaps(pid)
    cpu = cpu_pct([pid, procs["Hyprland"]], cpu_window)
    try:
        rest = p.stdout.read() or ""
        errors += [l.strip()[:160] for l in rest.splitlines() if "ERROR" in l]
    except (IOError, TypeError):
        pass
    os.killpg(p.pid, signal.SIGTERM)
    try:
        p.wait(10)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
    return {"load_s": loaded, "mem": mem, "cpu_pct": cpu.get(pid), "hyprland_cpu_pct": cpu.get(procs["Hyprland"]),
            "errors": errors[:5]}


runs = int(sys.argv[2]) if len(sys.argv) > 2 else 3
v_empty = variant("empty", EMPTY, False)
v_over = variant("overlays", overlays_qml, True)
OUT["isolated"] = {"empty": [run_instance(v_empty) for _ in range(runs)]}
save()
OUT["isolated"]["overlays_only"] = [run_instance(v_over) for _ in range(runs)]
save()

# ---- 0.3 wallpaper ----------------------------------------------------------
png = json.load(open(os.path.expanduser("~/.config/workstation/theme/colors.json")))["wallpaper"]["path"]
gif = os.path.join(BASE, "test.gif")
# exactly 20 frames (-frames:v), under a hard 2 GB address-space limit: the
# first run looped the still image without end and was OOM-killed
subprocess.run(["prlimit", "--as=2000000000", "ffmpeg", "-loglevel", "error", "-y", "-framerate", "10", "-loop", "1",
                "-i", png, "-frames:v", "20", "-vf", "scale=1920:1080,hue=h=t*180", "-loop", "0", gif],
               check=True, timeout=120)
OUT["gif"] = {"bytes": os.path.getsize(gif), "frames": 20, "fps": 10, "size": "1920x1080"}
WALL = """import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "qs-measure-wallpaper"
        color: "transparent"
        %s {
            anchors.fill: parent
            source: "file://%s"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            %s
        }
    }
}
"""
v_png = variant("wall-png", WALL % ("Image", png, "cache: false"), False)
v_gif = variant("wall-gif", WALL % ("AnimatedImage", gif, "playing: true"), False)


def cover():
    hypr("dispatch", 'hl.dsp.exec_cmd("ghostty --class=org.workstation.measure --title=measure -e sleep 300")')
    time.sleep(3)
    hypr("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
    time.sleep(2)


def uncover():
    for c in json.loads(hypr("clients", "-j") or "[]"):
        if c.get("class") == "org.workstation.measure":
            os.kill(c["pid"], signal.SIGTERM)


OUT["wallpaper"] = {"png_visible": run_instance(v_png)}
save()
OUT["wallpaper"]["gif_visible"] = run_instance(v_gif)
save()
try:
    OUT["wallpaper"]["gif_covered_fullscreen"] = run_instance(v_gif, during=cover)
finally:
    uncover()
shutil.rmtree(BASE, ignore_errors=True)
OUT["done"] = True
save()
