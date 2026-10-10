# RICE v1 - Performance Baseline (phase 0)

Measured before any visual RICE v1 change, so later phases can be compared
against it. Tool: `scripts/rice-measure.py` (run on the machine, as the
desktop user, in the session; never deployed). Measured 2026-10-11 ~00:00
on the test laptop.

## Hardware and software

| | |
|---|---|
| Machine | ThinkPad T440p, Intel Core i7-4712MQ, 16 GB RAM, Intel HD 4600 (i915, Mesa crocus), SATA SSD |
| Display | eDP-1 1920x1080 @ 60.05 Hz, scale 1, no external monitor |
| Software | Arch Linux, kernel 7.2.9-arch1-1, Hyprland 0.56.2, Quickshell 0.3.2, Qt 6.12.0, Mesa 26.2.4 |
| Desktop | repo commit `07a2fc4` (before RICE v1), theme Retro 82 (dark), text size 12, PNG wallpaper (1920x1080), Coffee on (no idle lock during the run), AC power |

## Method

- **Memory**: `/proc/<pid>/smaps_rollup` - RSS, PSS (shared pages split
  between users) and private memory; PSS is the comparison value.
  Swapped-out pages are NOT in RSS/PSS (see "Limits").
- **CPU**: `utime + stime` of the process over a 120 s (production) or
  30 s (test instance) window, in % of one core.
- **Isolated Quickshell**: test instances `quickshell -p <dir>` with the
  production process' own environment, side by side with the running
  desktop (which is not touched): an empty `ShellRoot {}`, and the
  production `shell.qml` reduced to its 10 overlay components (OS menu,
  Appearance, Firewall, Scratchpad, Cheatsheet, power menu, updater,
  snapshot slots, snapshot mode, clipboard - no bar, notifications, tray,
  wallpaper, power policy, portal watcher: nothing that owns a D-Bus name or
  changes state). 3 runs each: start -> "Configuration Loaded" (time), 15 s
  settle, memory, 30 s CPU, terminate.
- **Wallpaper**: a test instance with one background-layer surface showing
  the production PNG (`Image`) vs. a 20-frame 10 fps 1920x1080 GIF generated
  from it in `/tmp` (`AnimatedImage`, playing) - visible, then covered by a
  fullscreen throwaway window. Hyprland's CPU in the same window.

## Results

**Production session** (the running desktop):

| Process | Count | RSS | PSS | Swapped | CPU idle (120 s) |
|---|---|---|---|---|---|
| quickshell | 1 | 141 MB | 138 MB | ~100 MB | 0.01 % |
| Hyprland | 1 | 22 MB | 19 MB | ~70 MB | 0.02 % |
| hyprpolkitagent | 1 | 2 MB | 1.7 MB | ~15 MB | 0 % |
| hypridle / wl-paste (clipboard) | 1 / 1 | 1.8 / <0.1 MB | 0.8 / <0.1 MB | | 0 % |
| pipewire / wireplumber / xdg-desktop-portal | 1 each | 2.7 / 7.7 / 3.1 MB | | | 0 / 0.01 / 0 % |
| NetworkManager / upowerd (system) | | | | | 0.02 / 0.01 % |

The production memory values are **not representative**: the run followed
an OOM event of the first (faulty) measurement attempt, which pushed parts
of every desktop process into zram swap. For orientation, the same session
before that event showed quickshell 315 MB RSS and Hyprland 150 MB RSS (`ps`,
UI audit). The CPU values are valid: the desktop costs nothing measurable
while idle. Quickshell's start at login: 0.47 s from "Launching config" to
"Configuration Loaded" (journal).

**Isolated Quickshell instances** (fresh processes, reliable relative values):

| Instance | Load time (runs) | PSS (runs) | Private | CPU idle |
|---|---|---|---|---|
| empty `ShellRoot` (Qt + Quickshell base) | 0.48* / 0.10 / 0.09 s | 91.6 / 91.7 / 91.8 MB | 83 MB | 0 % |
| the 10 overlays only | 0.32 / 0.26 / 0.25 s | 156 / 143 / 158 MB | 133-148 MB | 0-0.03 % |

\* first start, cold caches. **The 10 overlays cost ~52-67 MB PSS** and
~0.15-0.2 s of load time while closed (instantiated but unmapped); the
variance between runs is ~15 MB (QML/JS heap, image cache).

**Wallpaper** (one background surface, 1920x1080):

| | PSS | CPU quickshell | CPU Hyprland |
|---|---|---|---|
| PNG, visible | 135 MB (~43 MB over the empty instance) | 0 % | 0.03 % |
| GIF 20 frames @ 10 fps, visible | 286 MB (**~194 MB** over empty) | **1.8 %** | **1.4 %** |
| the same GIF, covered by a fullscreen window | 272 MB | **1.7 %** | **1.6 %** |

GIF file: 14.9 MB. An animated wallpaper keeps all frames decoded and keeps
animating **while invisible** (Quickshell/Qt does not pause it under a
fullscreen window; Hyprland keeps compositing the frames): ~3 % of a core
permanently and ~150 MB more than a PNG on this machine - a real cost on the
T440p (battery, fan). PNG/JPG wallpapers cost nothing while idle.

## Limits

- Single machine, single session, one evening; numbers vary by ~10 % per
  run (memory) - compare ranges, not single values.
- Production memory distorted by swap (above); re-measure in a fresh
  session for the absolute values.
- GPU load is not measured directly (no `intel_gpu_top`); Hyprland's CPU is
  the proxy for compositing work.
- The overlay cost is measured without the bar and the other always-on
  parts; the interaction effects (shared image cache etc.) are not separated.
- The first attempt of this measurement (2026-10-10 23:45) generated the
  test GIF with an unbounded ffmpeg loop and was OOM-killed (13.7 GB); the
  tool now caps ffmpeg (20 frames, 2 GB address space) and saves after
  every section.

## Comparing later phases

Run `scripts/rice-measure.py 120 3` in a session that is idle (no lock,
Coffee on, AC power, same theme/text size/wallpaper type) after a fresh
login or a Quickshell restart, and compare:

- isolated overlays vs. empty: the RICE dialog work must not grow the ~55-65 MB
  overlay cost notably (> 10 MB) - the shared dialog frame of phase 3 should
  rather reduce it; lazy instantiation of the overlays is the obvious lever
  if it does
- idle CPU of quickshell and Hyprland stays ~0 % (no permanent animation)
- dialog transitions (<= 120 ms) must not leave timers or animations running
  after they end: CPU over 120 s with all dialogs closed = baseline
- GIF wallpapers: candidates for later work - pause the animation while
  the wallpaper is covered or on battery; until then, document the cost in
  the README
