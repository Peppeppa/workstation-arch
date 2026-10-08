# Feature Architecture v1

How optional desktop capabilities are added, enabled, disabled, and
removed in this repository. This is a convention + a small amount of
Ansible/Hyprland/Quickshell wiring - **not** a plugin framework, not a
config DSL, not a generic feature-loading engine. This stays a personal
Arch system for two real hosts (`laptop`, `workstation`) plus a
disposable test VM (`arch-dev`), not a platform for third parties.

If a future change to this makes the feature *system* more complicated
than the features it manages, that is a sign to simplify, not to add
more machinery.

## Core vs. Feature

**Core**: the desktop does not meaningfully function without it. Never
behind a flag, never optional.

- Hyprland (compositor)
- the Quickshell process itself, the core bar, the app launcher
- NetworkManager, PipeWire/WirePlumber, UPower
- hyprpolkitagent, the XDG portal stack
- base provisioning (packages, locale, keymap, the key-only SSH policy)
- the inbound firewall (`roles/firewall`, see "Firewall") and its
  Settings -> Firewall window

**Feature**: an optional capability layered on top of Core. The desktop
is still fully usable with every feature disabled.

Examples already in the repo or clearly feature-shaped: screenshots
(migrated to this model - see below), gaming (`gaming_enabled`, the
pattern this model generalizes), and, later, clipboard history, power
menu, lock/idle, tray, Bluetooth UI, webapps, laptop power tuning.
This list is orientation, not a spec - see `AGENTS.md` for what is
explicitly *not* being built yet.

If something doesn't clearly fit either bucket, ask: "does the desktop
still work for daily use without it?" If yes, it's a Feature.

## Source of truth

One flat boolean per feature: **`<name>_enabled`**.

- The default lives in `group_vars/all.yml`, next to `gaming_enabled` -
  that file is the single, greppable registry of which optional
  capabilities exist and whether they're on by default.
- A host overrides it in its own `host_vars/<hostname>.yml`, exactly
  like `gaming_enabled`/`gaming_gpu_vulkan_packages` already do.
- Everything the feature actually does (packages, templates, binds,
  services) stays next to its existing implementation and reads that
  one variable via `when:` (Ansible) or `{% if %}` (Jinja templates).
  `group_vars/all.yml` never grows role-specific detail - just the flag
  and a one-line pointer to where the feature lives.

**Why a flat bool, not a `desktop_features: {screenshots: true, ...}`
dict** (the shape this milestone's brief first suggested as a UX
sketch): every other variable in this repo is already flat
(`gaming_enabled`, `hyprland_terminal`, `hyprland_quickshell_cmd`, ...).
A nested dict would be the first of its kind here and buys nothing a
flat variable doesn't already give - it's still one source of truth,
still overridable per host, still a plain `when:`/`{% if %}` check,
just with an extra level of indirection (`desktop_features.screenshots`
vs. `screenshots_enabled`) that every task/template would have to
thread through. Simpler won; this is that "deutlich einfachere Lösung"
the brief explicitly said to prefer if found.

## Feature Contract

Not a YAML schema - a feature's comments and code should make each of
these answerable by reading them (see `screenshots_enabled` in
`group_vars/all.yml` and `roles/desktop/defaults/main.yml` for a worked
example):

| Question | Where it's answered |
|---|---|
| Name / variable | `<name>_enabled` |
| Default | set in `group_vars/all.yml`, with a comment why |
| Scope | common (`group_vars/all.yml`) or per-host (`host_vars/<host>.yml`) override |
| Packages | the feature's own `<name>_packages` list, in the role that already owns the domain |
| Config ownership | whichever Ansible task/template already deploys it, gated by the flag |
| UI integration | Quickshell component, if any (see Quickshell Modularity below) |
| Keybinds | Hyprland binds, if any, wrapped in `{% if %}` in `hyprland.lua.j2` |
| Lifecycle owner | who starts/stops any process - must be exactly one (see `AGENTS.md` Runtime Ownership) |
| Privileges | does it need `become: true`, a new group, a polkit rule - justify each one |
| Secrets | should almost always be "none" (see `AGENTS.md` Secrets) |
| Network access | does it open a port or call out - say so if yes |
| Disable behavior | exactly what stops when the flag is `false` (see Disable vs. Purge) |
| Persistent user data | does disabling risk deleting anything a user created |

## Feature categories

A feature can look different depending on what it actually is. The
model doesn't abstract these into one mechanism - it just says how
each kind is handled:

**A) Provisioning-only** (packages/config, no UI) - a package list
variable in the owning role's `defaults/main.yml`, installed by a task
gated `when: <name>_enabled`. Example: screenshots.

**B) Hyprland integration** (binds, window rules, exec actions) -
wrapped in `{% if <name>_enabled %}...{% endif %}` directly in
`hyprland.lua.j2`, right next to the core binds they relate to. See
Hyprland Modularity below for when this stops being enough.

**C) Quickshell feature** (UI component, IPC action, bar/overlay
integration) - see Quickshell Modularity below; not needed yet, no
Quickshell feature exists in this repo today.

**D) Background service** (its own process, a systemd unit) - needs an
explicit single Lifecycle Owner from the Runtime Ownership table in
`AGENTS.md` before it's built at all. Never a second owner for a
responsibility that already has one.

**E) Privileged/system feature** (NetworkManager, polkit, system
config) - extra scrutiny under the Security Model below; every
`become: true` task is reviewed individually, never covered by a
blanket sudoers change.

## Hyprland modularity

`hyprland.lua` is only the entry point; it `dofile()`s the modules in
`~/.config/hypr/conf/` (`roles/hyprland/templates/conf/*.lua.j2`):
`vars`, `monitors` (`hyprland_monitors`), `input`, `appearance`,
`session` (the processes Hyprland owns - started on `hyprland.start`, ended
on `hyprland.shutdown` by `~/.local/libexec/workstation/session-stop`:
SIGTERM to exactly those helpers + hyprlock, then a stop of
xdg-desktop-portal/-hyprland/-gtk, each with a bounded wait, while the
display still exists; Hyprland blocks in `os.execute` meanwhile. Not a stop of
graphical-session.target: that also stops the a11y bus and leaks its
at-spi2-registryd per logout), `binds` (incl. hardware keys).
Each module is a function taking the shared values. Feature binds/
autostarts stay `{% if <name>_enabled %}` blocks inside the module they
belong to (`binds.lua.j2`, `session.lua.j2`) - no per-feature files, no
include machinery. A module-only change triggers an explicit `hyprctl
reload` (Hyprland watches only `hyprland.lua`).

## Quickshell modularity

Checked against Quickshell 0.3.1 specifically (not a newer/unreleased
API): the idiomatic way to make part of a config conditional is plain
QML composition - a `Loader { active: <flag> }` (lazy-instantiates/
tears down its content based on a boolean, which is also good for idle
overhead: a disabled feature's QML never runs) - not a dynamic plugin-
loading mechanism.

Since Ansible, not Quickshell, owns which features are enabled, the
boolean a `Loader.active` needs has to come from the deployed config
itself. The repo already has the right-sized tool for this:
`hyprland.lua.j2` already templates Lua with Jinja; the moment a real
optional Quickshell component exists, `shell.qml` becomes
`shell.qml.j2` the same way, and the component is wrapped in
`{% if <name>_enabled %}` right in the QML text - no flag-reading
mechanism needed at runtime, no feature whose code is even present
when disabled. `Bar.qml`/`Launcher.qml` stay plain (not templated)
files as long as they have no feature-conditional content of their
own.

Implemented by Power Menu v1: `shell.qml` is now
`roles/quickshell/templates/shell.qml.j2`; feature components live
outside `files/quickshell/` (e.g. `roles/quickshell/files/
PowerMenu.qml`) and are copied only when enabled, before the root file
is rendered (the referencing file goes last). Any Quickshell config
change notifies `roles/quickshell/handlers/main.yml`, which reloads the
running instance once at the end of the run - Quickshell's own watcher
misses Ansible's atomic file replace.
A static host capability a component needs (hibernate) is resolved at
provisioning time and templated in - never polled at runtime.

## Bar (RICE v1)

Modelled on Omarchy's bar engine (`shell/plugins/bar/` in
omacom/omarchy: a bar host, separate widgets, the layout as user state
with left/center/right zones and a `centerAnchor`, a one-popout
coordinator, drag-to-reorder) - the principle, not its plugin stack: no
manifests, no plugin installation, no custom command modules, no
third-party API.

```
~/.config/quickshell/bar/
  Bar.qml            host: zones, positions, drag & drop, background toggle, opt-in tooltip (one per monitor)
  BarLayout.qml      registry of widget ids + the user layout (singleton, IPC "bar")
  BarPopups.qml      coordinator: at most one transient surface open - bar popup or overlay (singleton)
  BarStyle.qml       geometry / type sizes (singleton; colors stay in Colors)
  BarFeatures.qml    which optional parts exist (templated from the flags)
  BarWidget.qml      common frame: hitbox, hover, active/muted, underline, opt-in tooltip, popup protocol
  BarPopup.qml       common popup: overlay, outside click/Escape, below its widget
  PopupButton.qml    the button used in popups
  default-layout.json
  widgets/<Name>/    Widget.qml (+ Model.qml shared state, Popup.qml, ...)
```

| Widget id | Core / feature | Popup |
|---|---|---|
| `workspaces` | core | - |
| `clock` | core (center anchor) | - |
| `tray` | `tray_enabled` (whole widget) | item context menu |
| `connectivity` | core icon (interface of the active default route) | `connectivity_enabled`: network quick control (status, VPN, Wi-Fi) |
| `bluetooth` | `bluetooth_enabled` (whole widget; hidden without adapter) | Bluetooth popup |
| `audio` | core icon + percent (wheel volume, right click mute) | `audio_popup_enabled`: devices/volume (without it left click mutes) |
| `power` | core battery - only where a laptop battery exists (else invisible, no space, layout untouched) | battery popup (charge, UPower estimate; profiles with `power_profiles_enabled`) |
| `visuals` | core - four icon frames, one layout item: Timer, Day/Night, Light/Dark, Coffee (Coffee only with `lock_idle_enabled`) - see "Visuals" | Timer: MM:SS countdown; Light/Dark right click: brightness (only with a backlight) + themes + wallpapers |

- **Interface**: a widget gets `bar` (barHeight, screen, dragging,
  showTooltip/hideTooltip, openWidgetPopup) - nothing else. Core widgets
  are imported by `Bar.qml`; feature-only widgets (tray, bluetooth) are
  loaded by path, so a host without them has no such files.
- **Positions**: every available widget exists once per bar and is placed
  absolutely from the layout - reordering never recreates a widget. Left
  zone from the left edge, right zone from the right edge; the clock
  (center anchor) sits at the exact geometric center, other center
  widgets flank it; without the clock the center group is centered.
- **Layout state**: `~/.config/workstation/bar-layout.json`
  (`{"version": 1, "layout": {"left": [{"id": ...}], "center": [...],
  "right": [...]}, "settings": {"background": "solid"}}`), widget ids
  (+ plain values) and the bar settings only. Read once at
  start (no watcher), written atomically on each change. Unknown ids are
  ignored (and dropped on the next write); ids of switched-off features
  keep their place; a widget missing from the file is appended to its
  default zone. Ansible only creates the file if missing (`force: false`);
  `qs ipc call bar resetLayout` restores `default-layout.json`'s
  arrangement (settings stay). Migration: the former standalone `coffee`
  and `theme` ids become one `visuals` at the place of the first of
  them (the other is dropped, everything else stays), written once.
- **Tooltips**: none by default - bar widgets do not show hover tooltips
  (`docs/DESIGN_SYSTEM.md` "Bar look"); `BarWidget.tooltip` is an opt-in
  for a widget explicitly meant to have one.
- **Background**: `settings.background` = `solid` (theme `background`,
  default) or `transparent` (only the widgets are drawn - no blur, no
  shadow). Runtime interface, e.g. for a later settings menu:
  `qs ipc call bar setBackground solid|transparent` (applied at once, no
  Quickshell restart, written atomically into the same file) and
  `qs ipc call bar getBackground`. A file without `settings` means
  `solid`; Ansible never rewrites an existing file.
  Appearance -> Bar "Transparent bar background" and a right click on
  free bar space (no widget under the pointer - a widget's own right
  click keeps its function, the passive clock is not free space) both
  flip it through the same `BarLayout.setBackground()` - one value, so
  the checkbox and the right click always agree.
- **Drag & drop**: a `DragHandler` per slot (threshold 6 px) takes the
  pointer over from the widget - the widget's click is cancelled, so a
  drag never clicks. The widget follows the pointer, the landing place is
  outlined, neighbours slide aside (preview = layout with the widget
  there). Landing place = the insertion whose real resulting position
  (each candidate laid out with the same engine) is nearest to where the
  widget is held - candidates come from the layout *without* it, so there
  is no feedback, and an unmoved widget keeps its own slot (raw
  insertion points would make it swap with its neighbour in the
  leftwards-growing right zone). Works across zones; empty zones accept drops at their
  anchor. The outline appears right at the widget (its first placement
  is never animated - only later moves are). Drag corridor: only while
  a drag is active the bar's transparent surface grows
  `BarStyle.dragCorridor` (100 px) below the visible bar (26 px at the
  default text size; exclusive zone = the bar height - windows never move; back to 26 px right after the
  drop). Needed because Hyprland keeps the pointer on the bar below it
  only while a window lies there - on an empty desktop the bar got a
  leave and Qt cancelled the drag (measured on arch-dev). Release within
  the corridor saves at once; further down the preview falls back to the
  old layout, and a release there or a drag Qt cancels changes nothing.
  Outside a drag there is no extra input surface.
- **Popups**: each popup belongs to its widget (Loader bound to
  `popupOpen`), built on `BarPopup`: overlay layer covering the output
  except the bar strip (another widget switches popups in one click),
  outside click / Escape close, panel centered under its widget. The
  coordinator closes the previous popup on `request()` - and the overlays
  (OS menu, Appearance, power menu, clipboard history) register with the
  same coordinator, so a bar popup and an overlay are never open together
  (before, the OS menu opened over a popup, and the popup kept no keyboard
  once the menu closed). Content with its own input field gives the keyboard
  back with `BarPopup.restoreKeyFocus()` when the field disappears (network
  password box, Bluetooth PIN), so Escape keeps closing the popup.
- **Cost**: no process, no watcher, no timer except one short one-shot
  settle timer per drop.

## Visuals (bar widget)

Core bar widget `visuals` (`bar/widgets/Visuals/`): four icon frames -
**Timer | Day/Night | Light/Dark | Coffee** - that form one layout item
(one id, one drag handle; dragging moves all four) but stay separately
clickable. Each is a plain `BarWidget` frame: same icon size, hitbox,
hover, active (accent) / muted look as every bar icon. At rest they are
faded out, except a control that is on (running timer, Night, Coffee) or
has its popup open; hovering the widget fades all four in, leaving fades
them out (`BarStyle.revealDuration`, 140 ms). Only opacity changes - the
width stays, so the hover area (one HoverHandler on the widget) never
shrinks under the pointer.

| Control | Implementation | Runtime cost |
|---|---|---|
| Timer | `Countdown.qml` (singleton): input in `TimerPopup.qml` (also mainMod+E -> IPC `timer toggle`: opens the popup on the focused output's bar or closes it; never touches the countdown; `timer state` -> `{popupOpen, active, remaining}`) - digits read from the right as [H]MM:SS (5 = 0:05, 230 = 2:30, 9000 = 90:00, 13000 = 1:30:00; the last two digits are seconds) or with colons (2:30, 90:00, 3:30:00), up to 99:59:59; Enter = Start (one parse/start path); the hint previews the parsed time, the field is never reformatted; running display MM:SS, H:MM:SS from one hour; state = an absolute wall-clock deadline, remaining = deadline - now (never a decremented counter); a single-shot tick, only while a timer runs, aligned to the next full second; the remaining time stands next to the icon. Done: notification (`notify-send` -> our notification server) + `alarm-clock-elapsed.oga` via `pw-play`, then idle. Suspend: Qt timers use the monotonic clock (stops while asleep) but the deadline is wall time - the first tick after resume rings at once. No history, repeat, persistence | nothing while idle |
| Day/Night | `NightLight.qml` (singleton; also mainMod+A -> IPC `nightlight toggle` = the same `toggle()`, `nightlight state` -> `{active, busy, running}` with `running` = the hyprsunset child really up): Night = `hyprsunset` (hyprwm's blue-light filter, official `extra`, Hyprland's `hyprland-ctm-control` protocol) as a child of Quickshell, 4500 K; Day = the process ends and Hyprland drops the color transform. 0.5 s fade: hyprsunset starts neutral (`--identity`) and is stepped 6500 <-> 4500 K in 10 steps over its IPC (`hyprctl hyprsunset temperature`, one call at a time, overlapping steps replaced - no queue); clicks during a fade do nothing. Not persisted (every start is Day), no schedule, no slider; if hyprsunset dies, the toggle shows Day again | one small process only while Night is on; a step timer only during the 0.5 s fade |
| Light/Dark | the existing theme system: left click `theme toggle`, right click the theme popup (`bar/widgets/Theme/Popup.qml`) | none |
| Coffee | the existing `CoffeeMode` + the bar's Wayland `IdleInhibitor` (only with `lock_idle_enabled`). Read-only status: `qs ipc call coffee status` -> `on`/`off` (no setter - the icon is the only switch) | none |

## OS menu

Core (no flag). `mainMod+Space` -> `qs ipc call osmenu toggle`
(`roles/hyprland` binds). Replaces the standalone launcher.

```
~/.config/quickshell/osmenu/
  OsMenu.qml       host: window, page state, keyboard, destination hand-over
  RootPage.qml     a list of entries - the root: Applications, Settings, System
  AppsPage.qml     Applications: search + results (the former launcher view)
  AppModel.qml     the app model/filter (moved unchanged from Launcher.qml)
  SettingsPage.qml Settings: the same list with Appearance, Network, Firewall
  SearchPage.qml   type-to-search results (menu entries + applications)
  PageHeader.qml   back chevron + title of a page below the root
```

| Root entry | Action |
|---|---|
| Applications | page inside the menu (selected on every open) |
| Settings | page inside the menu: **Appearance** (close the menu, open the Appearance window), **Network** (close the menu, start `nm-connection-editor` on demand) and **Firewall** (close the menu, open the Firewall window - see "Firewall") |
| System | close the menu, open the existing Power Menu (sole owner of lock/suspend/hibernate/logout/reboot/shutdown; entry hidden without `power_menu_enabled`) |

Keyboard: **type to search**. The first printable key on a list page
(any letter - `j`/`k` included - digit, umlaut) opens `SearchPage.qml`: the
menu's own entries (`OsMenu.rootEntries` / `settingsEntries`, the one list
the pages render, plus search keywords) and the applications (AppModel's
ranking for both: name prefix, name, generic name, keywords; entries before
apps on a tie), best match preselected - `Super+Space chrom Enter` starts
Chromium, `appearance Enter` opens the same Appearance window as the
Settings page (`OsMenu.activate()`). Up/Down or Ctrl+J/Ctrl+K move, Enter
runs, Backspace edits; an emptied query or Escape returns to the unchanged
root list (never an empty results view); Escape with no query closes the
menu. On the lists: Down/Up (Ctrl+J/K) move, Right/Enter open, Left back,
Backspace back on Settings; no plain-letter navigation any more.
Applications: the search field has the focus (Up/Down/Enter). Bluetooth is
a bar widget, not a menu entry - not a search target. The search exists
only while typed: built per keystroke from data already in memory, nothing
while the menu is closed.
Mouse: hover selects (only after the pointer really moved since opening -
the menu maps under a resting pointer, whose first hover report must not
replace the preselection; same in the power menu and clipboard history),
click opens, the page header goes back, a click outside the panel closes. Surface: overlay on the focused output below the
bar strip, only while open (unmapped when closed). IPC `osmenu`:
`toggle`, `close`, `openPage <root|apps|settings>`, `state` (JSON, tests: page, query, results, selection).

## Appearance

Core. Opened from the OS menu (IPC `appearance`: `toggle`, `close`,
`state`). `~/.config/quickshell/appearance/` (window, content, theme
selector, theme import dialog, wallpaper picker) on top of shared, non-visual models in
`services/` and one neutral control in `ui/`:

| Model | Owner of | Used by |
|---|---|---|
| `services/ThemeModel.qml` | QML side of the `theme` helper: `status --json`, `select`, `wallpaper set`, `text-size`; refreshes on the Colors reload the helper triggers (no watcher) | bar theme popup, Appearance |
| `services/BrightnessModel.qml` | backlight via `brightnessctl -c backlight` (read once per open, coalesced writes); `available` false without a backlight -> control hidden/"Not available" (nothing faked) | bar theme popup (first control), Appearance |
| `services/DisplayModel.qml` | outputs (`hyprctl monitors -j`, per open and after a change), the runtime display scale (`~/.config/workstation/display-scale.lua`), "Change" (host_vars in Neovim) | Appearance |
| `ui/LevelSlider.qml` | a 0..1 slider (the volume slider's look) | both |

Sections: Theme (Dark and Light selectors, each listing only themes with
that marker; picking = `theme select`, applied at once when that mode is
active), Wallpaper (current preview -> picker: previews of the ACTIVE
theme's `backgrounds/`, click = `theme wallpaper set` + close, Cancel /
Escape / outside click = no change; GIFs show their first frame + badge),
Bar (Transparent bar background - BarLayout's own setting, see "Bar"),
Brightness, Text size, Display. Everything inside exists only while the
window is open (Loader): no process, no timer when closed.

**Text size** - ONE desktop typography preference, presets 9 10 11 12
14 16 18 px, default 11 (= the GTK font size, `desktop_ui_font_size`).
Owner: the `theme` helper (state key `text-size`, `theme text-size
<px>`), because it already owns the runtime appearance state, its
outputs and the live apply - no second state file. Each consumer derives
its size from it, relative to the default (at 11 everything is as before):

| Consumer | How |
|---|---|
| Quickshell (bar, popups, OS menu, Appearance, notifications, power menu, clipboard, tray menus) | `colors.json` `text_size` -> `Fonts.size`; every size is written for the default and goes through `Fonts.px()` - text and the rows/panels holding text; the bar never shrinks below its default height. Images, borders, the QR code do not scale |
| Ghostty (and Neovim inside it) | `font-size` in the helper's Ghostty include (12 pt default scaled, 0.5 pt steps), live via SIGUSR2 |
| GTK3/GTK4/libadwaita | GSettings `text-scaling-factor` = size / 11, written only by the helper |
| Chromium, IntelliJ, web pages | not forced - they keep their own zoom |

Text size and display scale are independent: one is typography, the
other the output scale.

**Display** - per output (as `hyprctl monitors -j` reports it):
resolution/refresh, the scale presets 1x 1.25x 1.6x 2x 4x (active one
marked) and **Change**. Ownership:

| What | Owner |
|---|---|
| mode, position, default scale per output | `hyprland_monitors` in `host_vars/<host>.yml` (declarative) -> Ansible renders `~/.config/hypr/conf/monitors.lua` |
| the scale picked in Appearance | runtime state `~/.config/workstation/display-scale.lua` (`return { ["eDP-1"] = 1.25 }`), written only by Appearance (atomic; output names checked against `[A-Za-z0-9._-]`), never by Ansible |

`monitors.lua` loads the runtime file with `pcall` (missing/broken = host
defaults) and lets its scale win for that output; an output that is not
in `hyprland_monitors` gets the catch-all rule's mode/position with it.
Applying = rewrite the file + `hyprctl reload` (Hyprland re-runs its
config); "Use the host default" removes the output's line. **Change**
opens the persistent source, `host_vars/<host>.yml` in the repository
checkout (path rendered by Ansible), in Neovim at `hyprland_monitors`
(the host's `hyprland_terminal`); `./bootstrap.sh` applies an edit. No
graphical resolution editor.

## Diagnostics and logging

Quiet when healthy, enough context when something fails; journald is the
only log store - no logging daemon, follower, rotation or timer of ours.

| Source | Where it goes |
|---|---|
| Quickshell (QML, Process failures, our `[component]` lines) | `journalctl --user -t quickshell` - started as `systemd-cat -t quickshell -- env NO_COLOR=1 ... quickshell` (systemd-cat execs: still one process under Hyprland, command line still `quickshell`). Before this, Hyprland's exec sent it to /dev/null and only Quickshell's runtime-dir log existed (gone at logout) |
| hypridle (+ hyprlock, its child) | `journalctl --user -t hypridle`, hypridle with `-q` (errors only; it logs ~90 lines per start otherwise) |
| polkit agent | stays discarded: hyprtoolkit logs ~80 DEBUG lines per login with no level setting; authentication results are in the system journal (polkitd/PAM) |
| OS menu / popup hand-offs (nm-connection-editor) | `systemd-cat -t app-launch -p err -- systemd-run --user --quiet --collect -- ...`: a failed launch is an err line (systemd-run logs it as `systemd-run`), the app runs in its own transient unit |
| Hyprland | `~/.local/state/ly-session.log` (session stdout), runtime `hyprland.log`, crash reports in `~/.cache/hyprland/` |
| NetworkManager, BlueZ, PPD, UPower, logind, Ly/PAM | their own units in the system journal |
| PipeWire / WirePlumber | their user units |
| bootstrap / Ansible | its own output; `ansible.cfg`: YAML results + task path on failure; `bootstrap.sh` prints where to look next |

Our own messages (`roles/quickshell/files/quickshell/Log.qml`): one line
per FAILURE, `[network|bluetooth|theme|wallpaper|brightness|power|osmenu|appearance|bar] what failed: why`
(exit code + first stderr line), never for normal operation (no timer
ticks, traffic samples, hovers, popup open/close, refreshes) and never
with secrets (names and exit codes only - no PSK, password, key). The same
message within 60 s is dropped. Capabilities that simply are not there
(no backlight, no battery, no Bluetooth controller) are not errors and
log nothing. A missing file is reported by FileView itself - no second
line of ours.

`repo-healthcheck` (`roles/diagnostics`, `/usr/local/bin`): the PASS/WARN/FAIL
view - "do the invariants hold?", exit 0 (HEALTHY) or 1 (UNHEALTHY: N checks
failed; WARN never fails), compact, ~0.5 s, read-only (state files are only
parsed). Checks, expectations templated from the feature flags: graphical
wayland session (via Ly if enabled), exactly one Hyprland, session and
activation environment, exactly one desktop Quickshell as Hyprland's child,
session helpers (polkit agent, hypridle, clipboard watcher - children of this
Hyprland, counts per flag, at most one hyprlock), no failed system/user units,
no user timers and no locally defined timer units, core services active
(NetworkManager, logind, UPower, PipeWire, WirePlumber, PPD per flag), no
competing owner process (second notification daemon, network manager/applet,
PulseAudio, idle daemon, wallpaper daemon, bar, launcher; systemd-networkd/iwd
inactive), audio stack, D-Bus owners of `org.freedesktop.Notifications` and
`org.kde.StatusNotifierWatcher` = Quickshell (per flag), no pairing agent
older than its 60 s limit, NetworkManager state + a default route when
connected, Bluetooth service only where a controller exists, bar layout
structure (unknown/duplicate ids: WARN - the bar ignores them), theme registry
(`theme status`: every directory valid, both modes, no duplicate names), theme
state (valid ids/modes; vanished wallpaper choice: WARN), theme outputs
current (colors.json = the active theme's colors, wallpaper file exists),
coredumps in this session (earlier this boot: WARN), QML exceptions/binding
loops in this session, `hyprctl configerrors`. Absent hardware (battery,
backlight, Bluetooth, Wi-Fi) is never a failure. Details stay repo-diagnose's.

`repo-diagnose [--full]` (`roles/diagnostics`, `/usr/local/bin`): read-only
Python, runs only when called. Default: one screen (session, shell + QML
warnings, network/default route/VPN summary, Bluetooth, audio, power,
desktop/theme, failed units, duplicate processes, recent errors,
coredumps) - exits 1 if it marked an issue. `--full`: unit table,
allowlisted environment (no full env), monitors, bounded journal excerpts
per component, hardware capabilities. Expectations come from the feature
flags (e.g. hypridle only with `lock_idle_enabled`). Failed units and
coredumps from before the current Hyprland start are listed as such, not as
issues - a normal logout leaves none since `session-stop` (see "Hyprland
modularity"); a session killed from outside (SIGTERM) still can. Privacy: only fields
collected on purpose (connection types, never names or profiles), and
every line passes a redaction filter (private-key blocks, `key=value` and
`*.psk VALUE` / `--password VALUE` forms, long base64 keys, all sudo
`COMMAND=` arguments).

## Ansible structure

Not every feature needs its own role. A small feature (a package list
+ a gated task + maybe a bind) lives in whichever existing role already
owns that domain (screenshots → `roles/desktop`, since that role
already owns clipboard/portals/notifications). A feature large enough
to need its own packages, templates, *and* handlers/services on a scale
comparable to `roles/gaming` or `roles/audio` gets its own role, tagged
the same way every role already is. Don't invent a third pattern
(generic "features/" directory, dynamically-included task files keyed
by a loop over feature names, ...) until an actual feature's size
demands it - and if that day comes, prefer the simplest of the two
existing patterns (small addition to an owning role, or a full role)
over a new one.

## Security model

1. **Least privilege.** A feature gets exactly the access it needs -
   no speculative extra group membership, no broader pacman/systemd
   scope "in case it's useful later."
2. **No implicit sudo.** No new sudoers rule without an explicit,
   reviewed reason in the task/commit that adds it. None exist today.
   The one privileged runtime path is a polkit action for a single
   root helper with a validated argv interface (`firewall-rules`, see
   "Firewall") - the pattern for any future one, never `sudo <tool>`
   from QML.
3. **No secrets in the repo.** Same rule as everywhere else in this
   project (see `AGENTS.md` Secrets and Public Repository) - a feature
   that needs a credential gets it from the separate private-config
   repository, never committed here.
4. **Package Source Policy applies unchanged**: official Arch → clean
   official upstream → Flathub → AUR last resort. No `curl | sh`. A
   feature is not an excuse to skip this ladder.
5. **Explicit lifecycle ownership.** Exactly one owner per persistent
   process (see Runtime Ownership in `AGENTS.md`), stated in the
   feature's own comments: who starts it, who stops it, why it exists.
   No duplicate autostart paths.
6. **Minimize background work.** No polling daemon if a native
   event/signal exists (see `AGENTS.md` Performance Rules) - this
   applies to features exactly as much as to Core.
7. **IPC/D-Bus used deliberately.** A feature's IPC surface (e.g. a
   Quickshell `IpcHandler` target) should be as narrow as the feature
   actually needs - see `Launcher.qml`'s `toggle`/`close` for the
   pattern, not a general-purpose remote-control interface.
8. **Disabling must not be destructive.** See Disable vs. Purge -
   `<name>_enabled: false` must be safe to flip without risking
   personal data.

## Disable vs. Purge

Two different, deliberately separate operations:

- **Disable** (`<name>_enabled: false`): the feature stops being used -
  its keybinds disappear, its config stops being deployed/managed, any
  process it owned stops being started. **Packages already installed
  while the feature was enabled are left alone** - Ansible's
  `pacman: state: present` with a list never removes a package that's
  simply no longer listed, and this project doesn't fight that default
  for a reversible toggle: removing packages on every disable risks
  pulling a dependency something else still needs, and makes
  re-enabling slower than it needs to be. This is why a plain
  `<name>_enabled: false` is safe by design - it cannot delete
  anything.
- **Remove/Purge** (actually uninstalling packages or deleting
  persistent data a feature created): a distinct, explicit, future
  operation - e.g. the `state: absent` cleanup this repo already used
  once for retiring fuzzel entirely (see `roles/hyprland/tasks/main.yml`,
  commit `03d0b78`) when a feature is being permanently removed, not
  just toggled off. Not built generically here; do this per-feature,
  deliberately, when actually needed - never automatically as a side
  effect of flipping a flag to `false`.

Disabling a feature must never delete anything a user created (history,
saved state, config they edited by hand outside this repo's own
managed files).

## How to add a new feature

1. Decide: is this actually a Feature (optional, desktop works without
   it) or Core? If Core, it doesn't belong in this model at all.
2. Add `<name>_enabled: <true|false>` to `group_vars/all.yml`, with a
   one-line comment: what it is, why this default, where it's
   implemented (which role/template).
3. Add the feature's packages as `<name>_packages` in the
   `defaults/main.yml` of whichever role already owns that domain (or
   a new role if it's genuinely that large - see Ansible Structure).
4. Gate the install task(s) with `when: <name>_enabled`.
5. If it needs Hyprland binds: add them to `hyprland.lua.j2` wrapped in
   `{% if <name>_enabled %}...{% endif %}`.
6. If it needs a Quickshell UI component: see Quickshell Modularity.
7. If it needs a persistent process: pick exactly one lifecycle owner
   per the Runtime Ownership rules in `AGENTS.md` - add it there too.
8. Work through the Feature Contract table above in the feature's own
   comments - it doesn't need a separate metadata file.
9. Validate: syntax-check, render-check any templated file, real/VM
   test both `true` and (if safe) `false`, idempotence.
10. Document anything user-facing in `README.md`; update `AGENTS.md`
    Runtime Ownership if it introduces a new owned process.

## Proof of concept: screenshots v1

`screenshots_enabled` (`group_vars/all.yml`, default `true` - already-
working daily-driver functionality, not something requiring unknown
host hardware the way `gaming_enabled` does) gates:

- `screenshot_packages` (`grim`, `slurp`, `libnotify`, `xdg-user-dirs` -
  `roles/desktop/defaults/main.yml`)
- the deployed on-demand helper script (`roles/desktop/files/
  screenshot.sh` -> `~/.local/bin/screenshot`, modes `smart`/`ocr`/
  `monitor` - `roles/desktop/tasks/main.yml`), which owns the selection
  (one on-demand `hyprctl clients/monitors -j` call feeds the visible
  window rectangles to `slurp -o`, which itself decides drag = region
  vs. click = window/empty desktop = monitor), file naming
  (`~/Pictures/Screenshots/Screenshot_<timestamp>.png`, mode 0600,
  collision-safe, respects a custom XDG Pictures dir via
  `xdg-user-dir`), the `wl-copy` clipboard write, and the `notify-send`
  confirmation
- the Hyprland bind that starts it (`mainMod + X` -> smart -
  `roles/hyprland/templates/hyprland.lua.j2`). The `monitor` mode has
  no bind on purpose (rarely needed).

**Sub-feature: `screenshots_ocr_enabled`** (default `true`) - the
pattern for a feature that only makes sense on top of another: its own
flat flag, gated as `when: screenshots_enabled and
screenshots_ocr_enabled` / a nested `{% if %}`, and the dependency
stated in the flag's comment. No dependency engine. It adds
`screenshot_ocr_packages` (`tesseract` + only `tesseract-data-deu`/
`-eng`) and the `mainMod + SHIFT + X` bind (same selection, `grim |
tesseract stdin stdout -l deu+eng` over a pipe - no image ever touches
disk - recognized text -> clipboard). Fully local, no network.

No Quickshell component, no persistent process - the script (and
tesseract, for OCR) is started on demand by the bind and exits on its
own once done (see `AGENTS.md` Runtime Ownership "temporary UI helper
-> started on demand only"), no new privileges. The only thing that
outlives it is `wl-copy`'s own forked clipboard owner, which is how the
Wayland clipboard works for any copy and ends when something else is
copied. Feature Category A (provisioning-only) plus Category B
(Hyprland binds).

## Power menu v1

`power_menu_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | Quickshell component + one Hyprland bind |
| Packages | `power_menu_packages`: `ttf-jetbrains-mono-nerd` (icons; also in `roles/apps`) |
| Config ownership | `roles/quickshell` (`files/PowerMenu.qml`, `templates/shell.qml.j2`), `roles/hyprland` (bind) |
| UI | `PowerMenu.qml`, centered layer-shell overlay inside the running Quickshell |
| Keybind | `mainMod + Escape` -> `qs ipc call powermenu toggle` (IPC exposes only `toggle`/`close`) |
| Lifecycle owner | the existing Quickshell instance under Hyprland - no new process |
| Privileges | none added: `systemctl suspend/hibernate/reboot/poweroff` via logind's normal active-session polkit rules; logout = Hyprland `hl.dsp.exit()` |
| Reboot / Shutdown | `workstation_end_session("reboot"\|"poweroff")` (roles/hyprland `session.lua`): the session ends like a logout (ordered `session-stop`), then the shutdown hook asks logind - a plain `systemctl reboot` SIGTERMed the whole session scope at once and every helper crashed. A refused request leaves the user at Ly (which offers reboot/shutdown itself) |
| Secrets / Network | none / none |
| Hibernate | shown only if logind `CanHibernate` was `yes`/`challenge` when the host was provisioned; the resume setup itself is the host capability `hibernate_enabled` (see "Hibernate") |
| Lock | listed, unavailable ("not set up") until the Lock/Idle milestone - never faked |
| Preselection | Lock, also when the menu opens under a resting pointer: hover selects only after real movement (before, the row under the pointer replaced it and Enter could log out or shut down - found on arch-dev) |
| Disable | no bind, component not instantiated/deployed; an already-deployed `PowerMenu.qml` stays unreferenced; nothing deleted |
| Persistent user data | none |

## Hibernate (host capability)

`hibernate_enabled` (`group_vars/all.yml`, default `false`; per host in
`host_vars/<host>.yml`), implemented in `roles/power`. Not a UI feature:
it gives a host a real resume target; the power menu keeps asking logind
(`CanHibernate`, unchanged) whether to offer Hibernate.

| Contract | |
|---|---|
| Resume target | a disk swapfile (`hibernate_swapfile_path`, default `/swapfile`, size = RAM rounded up to GiB, `hibernate_swapfile_size_mib`), created with `mkswap --file` (no holes, 0600, No_COW on btrfs), in `/etc/fstab` with `pri=0` |
| zram | stays (installer's `zram-generator`, priority 100) and keeps doing day-to-day swapping; systemd never hibernates to zram, it picks the swapfile |
| Kernel | `resume=UUID=<fs of the swapfile> resume_offset=<first physical block>` written into `hibernate_kernel_cmdline_file` (`/etc/kernel/cmdline`, the UKI cmdline of archinstall's systemd-boot + UKI layout); only these two parameters are (re)set, everything else stays |
| Initramfs | busybox initramfs (archinstall default): `/etc/mkinitcpio.conf.d/50-workstation-resume.conf` appends the `resume` hook (after `udev` and any `encrypt`); systemd initramfs (`systemd` hook) or an existing `resume` hook: nothing added. Then `mkinitcpio -P` rebuilds the UKI |
| Encryption | a swapfile inside an encrypted root is encrypted with it; the initramfs unlocks the root before it resumes - no separate swap key |
| Guards | stops (assert) instead of guessing when: no `/etc/kernel/cmdline` (other bootloader layout), filesystem not ext4/xfs/btrfs, less than size + 2 GiB free. Never partitions, never creates btrfs subvolumes |
| Cost | none at runtime: no process, no timer, no polling - a file, an fstab line, two kernel parameters |
| Disable | `false` again changes nothing on disk (Disable vs. Purge); remove swapfile/fstab line/cmdline parameters by hand if wanted |

Tested so far (arch-dev): dry run (`--check --diff -e hibernate_enabled=true`) -
the size guard stops the default 16 GiB swapfile on arch-dev's 14 GiB free
root; with 4 GiB the plan is swapfile + fstab line + resume hook, nothing
else touched; the offset/UUID script against a real ext4 test swapfile
(matches `filefrag`). arch-dev itself stays without hibernate: its kernel
reports `/sys/power/disk` = `[disabled]` and logind `CanHibernate` = `na`,
and a VM is no place to trust resume - no VM-only workaround.

Real-hardware bring-up (laptop/workstation), in this order:
1. Check the layout: `lsblk -f`, `findmnt /`, `cat /etc/kernel/cmdline`,
   `grep ^HOOKS /etc/mkinitcpio.conf`, `free -g`, `swapon --show`. On a
   btrfs root create a non-snapshotted subvolume for the swapfile first
   (e.g. `@swap` at `/swap`) and set `hibernate_swapfile_path`.
2. Secure Boot with kernel lockdown disables hibernation in the kernel -
   check `cat /sys/kernel/security/lockdown` and `/sys/power/disk`.
3. `host_vars/<host>.yml`: `hibernate_enabled: true` (+ path/size if not
   the defaults), then `./bootstrap.sh`.
4. Reboot (the new UKI carries resume=/resume_offset=), then
   `cat /proc/cmdline`, `busctl call org.freedesktop.login1
   /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate`
   -> `s "yes"`.
5. `./bootstrap.sh` once more - the power menu now lists Hibernate.
6. Real test: open apps, `systemctl hibernate`, power on, unlock - the
   session is back; `journalctl -b -1 -u systemd-hibernate`.

## Recovery (host capability)

`recovery_enabled` (`group_vars/all.yml`, default `false`; `laptop` on),
implemented in `roles/recovery`; full design and test results:
`docs/recovery-design.md` (section 21 = as built).

| Contract | |
|---|---|
| Layout | needs a Btrfs root as `subvol=/@`, `rootflags=subvol=@` in `/etc/kernel/cmdline`, systemd-boot + UKI, vfat ESP at `/boot` - the role asserts it and stops otherwise. Adds `@snapshots` (`/.snapshots`) and the unmounted `@recovery` container (+ `@swap` with hibernate); never partitions, never touches LUKS, `@home`, `@log`, `@pkg` |
| Snapshots | snapper config `root`: no timeline, no qgroups, `NUMBER_LIMIT` 10 pairs, 4 important, `EMPTY_PRE_POST_CLEANUP="no"`; `snapper-cleanup.timer` (the one allowed timer) |
| Recovery slots | `before-update`, `previous-update`, `known-good`: pinned read-only snapshot + writable clone `@recovery/<slot>` + UKI with the booted kernel/initramfs (`/boot/EFI/workstation/recovery/`) + boot entry "Recovery: ..." (never the default) |
| Commands | on demand only, never run by Ansible: `system-update` (preflight, healthcheck, slot, `pacman -Syu`, post checks - never rolls back by itself), `system-snapshot` (`"label"`, `--known-good "label"`, `--list`), `system-rollback <slot\|N>` (new `@` from the snapshot, old one kept as `@broken-<date>`, main UKI rebuilt) |
| Cost | no process; ESP ~45 MB per slot; snapshot space only for changed blocks |
| Disable | `false` changes nothing on disk; slots/snapshots stay until removed by hand |


`display_manager_enabled` (`group_vars/all.yml`, default `true`),
`roles/display_manager`. Ly only - not a display-manager framework.

| Contract | |
|---|---|
| Package | `ly` from official `extra` (1.4.1 at introduction; deps pam, glibc, libxcb) - no AUR, no source build |
| Unit / VT | the package's `ly@.service`, enabled as `ly@tty2` (Arch/upstream default VT; it carries `Conflicts=getty@tty2`, and getty@tty2 is not enabled on Arch). tty1 keeps `getty@tty1`, ttys 3-6 get `autovt` gettys on demand. Enabled only - provisioning never starts it (that would switch the console away from a running session); it takes over at the next boot |
| PAM | the package's `/etc/pam.d/ly` unchanged (`include login`, optional `pam_gnome_keyring` - unlocks the login keyring for Bitwarden's Secret Service). `ly-autologin` is unused: no autologin is configured |
| Session | Ly's own session dir `/etc/ly/wayland-sessions` with one symlink to the hyprland package's `hyprland.desktop` (`Exec=/usr/bin/start-hyprland`, the same watchdog start as by hand). Needed because Ly ignores `TryExec` and listed the package's `hyprland-uwsm.desktop` first (no uwsm here). Ly's built-in `shell` session stays. Quickshell, hypridle, polkit agent, clipboard watcher and the activation-environment import keep their single owner: Hyprland's `hyprland.start` |
| Config | `/etc/ly/config.ini` from the package, only these keys set in place: `waylandsessions`, `allow_empty_password = false` (upstream: true), `hide_version_string = true`, static colours after Retro 82 (`fg` #FFF1DA, `border_fg` #2A6A73, `error_fg` #F85525). Upstream defaults kept: no animation, no big clock, password as `*`, last user/session remembered (`save`) |
| Theme | static on purpose - Ly runs before any user session, so it is not part of the runtime theme helper; no watcher, no IPC, no theme-state dependency |
| Cost | while logged in: `ly-dm` (root, the parent that waits for the session and closes PAM on logout) - Ly's normal architecture; no timer, no polling of ours |
| Disable | `ly@tty2` no longer enabled (next boot: plain TTY login on every VT); package and config stay; `start-hyprland` from a console login works either way |

Session environment (verified after a real Ly login on arch-dev): Ly sets
`XDG_SESSION_TYPE=wayland`, `XDG_SESSION_CLASS=user`,
`XDG_SESSION_DESKTOP`/`XDG_CURRENT_DESKTOP=Hyprland`; Hyprland's
`hyprland.start` imports `XDG_SESSION_TYPE/CLASS/DESKTOP` into the systemd
user manager (D-Bus activation), Hyprland itself adds `WAYLAND_DISPLAY`,
`DISPLAY`, `XDG_CURRENT_DESKTOP`; host-only extras
(`hyprland_activation_environment`) stay host-only (arch-dev's
`LIBGL_ALWAYS_SOFTWARE=1`).

Recovery: tty1 console login (`Ctrl+Alt+F1`), ttys 3-6 on demand, sshd
where `ssh_server_enabled`;
from a console `start-hyprland` starts the session by hand; a broken Ly:
`systemctl disable --now ly@tty2` (or the flag + bootstrap).

## Lock + Idle v1

`lock_idle_enabled` (`group_vars/all.yml`, default `true`). One flag:
lock and idle share the same daemon (hypridle is also the logind Lock
handler), so splitting them would buy nothing.

| Contract | |
|---|---|
| Scope | `roles/hyprland`: packages, `hypridle.conf.j2`, `files/hyprlock.conf`, autostart + bind in `hyprland.lua.j2`; Power Menu Lock entry (`lockAvailable`) |
| Packages | `lock_idle_packages`: `hyprlock`, `hypridle` (official `extra`) |
| Lock path | `loginctl lock-session` only (Super+Delete, power menu, idle listener, `before_sleep_cmd`) -> logind Lock -> hypridle `lock_cmd` -> `pidof hyprlock \|\| hyprlock` |
| Idle | `lock_idle_lock_timeout` 300 s -> lock, `lock_idle_dpms_timeout` 600 s -> `hl.dsp.dpms` off, on at activity (ext-idle-notify, no polling) |
| Suspend | hypridle holds a logind delay inhibitor until Hyprland reports the session locked (`inhibit_sleep` auto -> lock-notify) |
| Lifecycle owner | Hyprland session start; a bootstrap inside a running session asks that Hyprland to exec it; config/start-command changes restart it (handler); `session-stop` ends it (and a running hyprlock) at session end |
| Privileges / Auth | none added; unlock only via hyprlock's package PAM file (`auth include login`), no `unlock_cmd` |
| Secrets / Network | none / none |
| Coffee mode (v1.1) | bar toggle left of the clock -> Quickshell `IdleInhibitor` (Wayland idle-inhibit) on the bar surface; hypridle's listeners obey it, explicit/sleep locks don't go through idle events so they're unaffected; not persisted, dropped by the compositor if Quickshell exits |
| Host overrides | `lock_idle_hypridle_cmd` (arch-dev: `env LIBGL_ALWAYS_SOFTWARE=1 hypridle`, inherited by hyprlock) |
| Disable | no bind, no autostart, power menu Lock unavailable, running hypridle stopped, `hypridle.conf`/`hyprlock.conf` removed (feature-owned config); packages stay |
| Persistent user data | none |

## Notifications v1

`notifications_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/quickshell/files/Notifications.qml`, composed by `shell.qml.j2` |
| Packages | none (Quickshell is the daemon); `mako` is uninstalled as part of the core change, independent of the flag |
| D-Bus / lifecycle owner | Quickshell's `NotificationServer` owns `org.freedesktop.Notifications` inside the existing Quickshell process (Hyprland-started) - exactly one owner, no activatable fallback daemon |
| UI | toasts top-right below the bar, newest on top, max 5 shown; app icon/image (theme names only if they exist), app name, summary, plain-text body; click / x closes |
| Timeouts | sender `expire_timeout` (ms) or 5 s, paused on hover; critical urgency never expires; one QML Timer per shown toast, window unmapped when empty |
| Not in v1 | actions, inline reply, history/center, sound, persistence (all advertised as unsupported) |
| Privileges / Secrets / Network | none / none / none |
| Disable | component not instantiated -> no notification owner at all (`notify-send` fails; `screenshot.sh` treats toasts as best effort) |
| Persistent user data | none |

## System Tray v1

`tray_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/quickshell/files/tray/` (`Tray.qml`, `TrayMenu.qml`, `TrayMenuLevel.qml`), loaded by `Bar.qml` through a Loader |
| Packages | none (Quickshell 0.3.1 `Quickshell.Services.SystemTray`); named icons need `QS_ICON_THEME` in Quickshell's start env (`hyprland_quickshell_exec`, core) |
| D-Bus / lifecycle owner | the running Quickshell owns `org.kde.StatusNotifierWatcher` and registers as the one StatusNotifierHost - no other watcher/host |
| UI | items first in the bar's status zone, 15px icons in 24px slots, Passive items hidden, zone invisible with no items; no hover tooltip. Collapsed: only a `<` handle; hovering the widget slides the items out to the LEFT of it (width + fade, 140 ms - an animation only while it changes); leaving collapses them. The hover area is the whole widget, so handle -> icon never collapses it; an open item menu keeps it expanded |
| Actions | left `activate()` (menu for `onlyMenu` items), middle `secondaryActivate()`, right DBusMenu context menu, wheel `scroll()` - only the item's own SNI/DBusMenu interfaces |
| Menu | rendered by us via `QsMenuOpener` (themed, live switch; separators, disabled, checkbox/radio, inline submenus); overlay surface exists only while open, click outside / Escape closes |
| Privileges / Secrets / Network | none / none / none |
| Disable | Loader inactive: no tray component, Quickshell never becomes watcher/host; files stay unreferenced |
| Persistent user data | none |
| Test | `scripts/sni-test-client.py` (on demand, python-gobject only) |

## Bluetooth v1 (+ v2 rows)

`bluetooth_enabled` (`group_vars/all.yml`, default `true`). Bluetooth stays
its own bar widget - not part of the network popup or the OS menu.

| Contract | |
|---|---|
| Scope | `roles/bluetooth` (packages, `bluetooth.service`); `roles/quickshell/files/bluetooth/` (`Widget.qml`, `Popup.qml` -> `bar/widgets/Bluetooth/`; `bluetooth-agent.py` -> `~/.local/libexec/workstation/bluetooth-agent`) |
| Packages | `bluez`, `python-gobject` (audio: PipeWire's bluez5 plugin is already in `pipewire-audio`; no `bluez-utils`) |
| Lifecycle | `bluetoothd`: systemd system service, enabled; it carries `ConditionPathIsDirectory=/sys/class/bluetooth`, so without an adapter it never runs (zero cost) and udev's `bluetooth.target` starts it when one appears. UI: the existing Quickshell instance. Agent: Quickshell child, only during a user-started pairing |
| API | Quickshell 0.3.1 `Quickshell.Bluetooth` (BlueZ D-Bus, event-driven): `adapter.enabled` = Powered (runtime on/off, never `systemctl`), `adapter.discovering`, `device.connect/disconnect/pair/cancelPair/forget`, `trusted`, `battery` |
| UI (v2) | status-zone icon (hidden without adapter; muted off/blocked, normal on, accent connected), no tooltip. Popup: on/off, rfkill soft/hard (one `rfkill --json` read when Blocked, unblock for soft), sections Connected / Known devices / Available, Scan, in-popup pairing dialogs. Row = monochrome device glyph (Nerd Font, theme colors) chosen from BlueZ's own `Icon` property - headphones/headset, speaker, keyboard, mouse, gamepad, phone, computer, display, printer, camera; anything else the Bluetooth glyph, never guessed from the name - then name and state - a connected device that reports its battery (BlueZ `Battery1`, D-Bus property signals, no polling) shows the level (`72%`) instead of "Connected"; **click the row** = disconnect (connected) / connect (known) / pair (new; click again cancels). Right side: state icon; for a known device an **X replaces it while hovered** - its own click area: forget, never connect/disconnect. New devices have no X |
| Scanning | user-started only, auto-stop after 30 s, stopped on popup close if we started it |
| Pairing | Quickshell 0.3.1 has no BlueZ agent; established ones (bt-agent, blueman) are persistent with terminal/own-GUI prompts. `bluetooth-agent` (Gio, ~150 lines): registered as default agent only while pairing, JSON lines over stdin/stdout to the popup (confirm/authorize/PIN/passkey/display), accepts calls only from `org.bluez`'s owner, never logs codes, exits on quit/stdin close/60 s. No agent otherwise: nothing pairs unless the user starts it. Paired devices are trusted + connected: **one click on an Available device = pair, then exactly one connect** - Quickshell's `connect()` when no link is up; when the pairing's own baseband link is still up (BlueZ already says Connected, no profile is), one `busctl call org.bluez <path> org.bluez.Device1 Connect` (Quickshell refuses `connect()` on a "connected" device); "Already Connected" = fine. A failed connect leaves the device paired + disconnected (click to retry) |
| Privileges / Secrets / Network | none at runtime (no sudo; `rfkill unblock` as the session user) / no codes stored or logged / Bluetooth radio only |
| Disable | no UI (Loader inactive), `bluetooth.service` disabled + stopped; `/var/lib/bluetooth` pairings and packages kept |
| Persistent user data | BlueZ's own pairing store (`/var/lib/bluetooth`), never touched by us |
| Hardware-only validation | real pairing/agent prompts, connect/disconnect, hover-X forget, battery, BT audio via WirePlumber, rfkill soft/hard + unblock (arch-dev has no adapter) |

## Battery / power widget v2 (+ power profiles, lid)

Battery: core. Profiles: `power_profiles_enabled` (`group_vars/all.yml`,
default `true`).

| Contract | |
|---|---|
| Scope | `roles/power` (PPD, logind lid drop-in, host default profile); `roles/quickshell/files/quickshell/bar/widgets/Power/` (`Model.qml`, `Widget.qml`, `Popup.qml` - core) and `BatteryWatcher.qml` |
| Capability | the widget exists only where UPower's `displayDevice` is a present laptop battery (`isPresent && isLaptopBattery` - hardware data, not the hostname). Without one it is invisible with width 0: no empty slot, the persisted layout keeps its `power` entry untouched, no popup, nothing extra watched |
| Icon | on external power: plug; discharging: battery filled in 10 % steps; <= 15 % while discharging: the theme's `error` color |
| Low battery | `BatteryWatcher.qml`: one critical notification on crossing <= 15 % while discharging; re-armed only by external power or once back >= 20 % (no spam around the threshold). Event-driven (UPower signals), no timer |
| Popup | "Battery" + percentage on one row, a wide charge bar (error color when low), below it UPower's own estimate ("3h 42m remaining" / "1h 08m until full") only when UPower has one - never computed by us; then, **on battery only**, "Power profile": Power Saver / Balanced / Performance, active one highlighted, Performance disabled where PPD does not offer it (`hasPerformanceProfile`); on external power one line names the profile the AC policy holds |
| AC policy (laptops, `power_profiles_enabled`) | `PowerPolicy.qml`, one instance (shell.qml): external power -> Performance (Balanced where the platform has none); battery -> the profile last chosen ON BATTERY, remembered in `~/.config/workstation/power-battery-profile` (written only by the policy - AC Performance never overwrites it). Event-driven (UPower `OnBattery`, PPD `ActiveProfile`), sets a profile only when it differs (duplicate events/resume set nothing). No laptop battery (workstation): does nothing |
| Profiles API | Quickshell `PowerProfiles` (PPD D-Bus, event-driven): `profile` set = switch; PPD's polkit allows the active local session - no sudo, no Ansible at runtime |
| Host default | `power_profile_default` (roles/power, "" = leave PPD alone); the workstation (no battery, so no profile switch in the bar) sets `performance`. Applied once per value (`powerprofilesctl set` + marker `/var/lib/workstation/power-profile-default`), skipped with a note when the platform lacks it - a later runtime choice is never reset, no helper keeps forcing it |
| Lid (core) | `HandleLidSwitch=suspend`, `...ExternalPower=suspend`, `...Docked=ignore` (logind drop-in, SIGHUP, no restart); hypridle locks before sleep |
| Packages | `power-profiles-daemon` |
| Disable (profiles) | no profile row; PPD disabled + stopped; package stays |
| Persistent user data | `~/.config/workstation/power-battery-profile` (the battery choice); PPD keeps its own last profile |

## Audio popup v1

`audio_popup_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/quickshell/files/audio/` (`AudioControl.qml`, `AudioPopup.qml`, loaded by `Bar.qml`) |
| Packages | none (PipeWire/WirePlumber core, `roles/audio`) |
| API | Quickshell `Pipewire`: hardware nodes (`isSink`, `!isStream`), `preferredDefaultAudioSink/Source` (WirePlumber persists the choice), `PwNodeAudio.volume/muted`; trackers only for the default nodes |
| UI | bar widget `audio` (icon + percent, wheel volume, right click mute); left click opens the popup (outputs/inputs, default highlighted, mute + volume bar for both, clamped 0-100 %); mic-off glyph in the widget while the default input is muted |
| Hardware keys | core binds (`binds.lua`): volume +/-, mute, mic mute (`wpctl`), brightness (`brightnessctl`), play/pause/next/prev (`playerctl`) - all `locked`, volume/brightness `repeating` |
| Privileges / Secrets / Network | none / none / none |
| Disable | no popup, no mic icon; the core label stays |
| Persistent user data | none (WirePlumber's own default-node state) |

## Network (connectivity) v2

Bar icon: core. Popup: `connectivity_enabled` (`group_vars/all.yml`,
default `true`). NetworkManager stays the only network owner.

| Contract | |
|---|---|
| Scope | `bar/widgets/Connectivity/Model.qml` (core), `roles/quickshell/files/connectivity/` (`Popup.qml`; `wifi-qr.py` -> `~/.local/libexec/workstation/wifi-qr`) |
| Bar icon | the interface carrying the **active default route**: kernel routes (`/proc/net/route`, `/proc/net/ipv6_route` via FileView), lowest metric among NM's physical devices (Wi-Fi with signal level / Ethernet), else disconnected. Ethernet + Wi-Fi both up -> whichever owns the default route; cable gone -> follows the route. A VPN holding the default route keeps the physical uplink as icon (`vpnDefault`, "via VPN" in the popup). Re-read on NM events (device states, active networks, connectivity) + one 1.5 s one-shot re-read for routes that settle late - no poller, no process (one exception: Wi-Fi up on a profile Quickshell does not attach - see "Popup: Wi-Fi" - reads its signal with one `nmcli device wifi list --rescan no` per NM event, value as of that event). A pure route change NM raises no event for (e.g. `nmcli device reapply` with a new metric) reaches the bar on the next NM event or as soon as the popup opens (its 1 s timer re-reads the routes too) |
| Popup: status | NM connectivity: Full / "Login required" (portal: button opens NM's own `ConnectivityCheckUri` in Chromium, so the portal redirects - no probing of ours) / Limited / No internet; global addresses per interface with type icon (`ip -j -d addr`, on open + on NM events; only links that are up - a stopped Docker's `docker0` keeps its address while DOWN; no loopback/link-local; at most one stable IPv6 per interface, dimmed); default gateway with its interface type |
| Traffic | the ONLY sampling: ↓/↑ of the default-route interface, a 1 s Timer reading `/sys/class/net/<if>/statistics/{rx,tx}_bytes` (FileView, no process). It lives inside the popup (exists only while open): starts when the popup appears, gone when it closes - zero wakeups afterwards; follows the interface when the default route moves |
| Popup: VPN (before Wi-Fi) | NM `vpn`/`wireguard` profiles (`nmcli -t` on open, on NM events, after each action): row click = up/down by UUID. No create/import/edit/delete here. "via VPN" also for NM's WireGuard full tunnel, which routes by policy (default route in its own table behind an ip rule; the main table and NM's `Default` flag still show the physical uplink): `ip -j route get 203.0.113.1` (FIB lookup, nothing sent) at the same moments as the address list |
| Popup: Wi-Fi | radio on/off; **Known networks** = saved NM profiles (`known`), connected one highlighted with "Connected"; Quickshell 0.3.1 attaches a saved profile to its network only when the profile spells out `802-11-wireless.mode infrastructure` (NM's default for an unset mode is the same) - profiles created over D-Bus without it (the eduroam CAT installer's `eduroam`/`THWS`, system-wide, `permissions user:<you>`) were neither known nor connected and showed as "enterprise, set up in settings". Those come from NM itself: `nmcli -t connection show uuid ...` (id, UUID, SSID, mode, key-mgmt, active state - no secrets) at the same moments as the VPN list, one row per profile (identity = UUID, also out of range), click = `nmcli connection up uuid <uuid> ifname <wifi>` / `down` - the stored profile with its 802.1X settings, nothing created or changed; NM's own error (out of range, secrets required, auth failed) is shown. These rows have no forget X (802.1X profiles are removed in nm-connection-editor); their SSID never appears under Other networks; **Other networks** = visible, not saved. Signal icon before the SSID, lock on the right if secured; on a known row an X replaces the lock (or appears) while hovered - forget, in its own click area. Row click: known -> connect (connected -> disconnect), open -> connect, WPA/WPA2/WPA3-Personal -> inline password (eye toggle: shows/hides the same field, starts concealed; Copy/Cut blocked); wrong password -> box stays with an error; success -> NM stores it, it moves to Known. **Other networks** is a ListModel keyed by SSID (synced by move/insert/remove - rows keep their identity; a Repeater over a recomputed array recreated every row on each scan and lost the typed password) and is **frozen while a password is typed or sent**: the wanted order is applied once when the box closes (cancel, success, popup closed). Its own scroll area: up to 10 rows (+ the open box), scrollbar only when longer, heading and other sections fixed; Up/Down/Enter select/connect with the selection scrolled into view. Enterprise/WEP -> note + "Open" (nm-connection-editor). Scanning only while open. QR share of the current network: QR + a fixed 12-bullet mask (never the saved password itself, no reveal) + Copy (real password via `wl-copy --sensitive` stdin, not in cliphist) |
| Secrets | passwords go straight to NM (`connectWithPsk`), never logged or stored by us; QR only in memory |
| Administration | `nm-connection-editor` (roles/network, official `extra`), started on demand from the popup's own **Connections...** button (bottom), the OS menu and the enterprise note: VPN add/import/edit/delete, Ethernet/Wi-Fi profiles, WPA-Enterprise/eduroam, DHCP vs static IPv4, gateway, DNS. No `network-manager-applet`, no tray applet, no autostart |
| Privileges | NM's own polkit policy for the active session; no sudo |
| Disable | no popup; the core icon stays |
| Persistent user data | NM connection profiles (created by NM on connect; forget deletes on request) |

**NM secret agent: none, on purpose.** Our profiles keep their secrets
system-owned (`psk-flags 0`, root-only keyfile) - the popup hands the
password to NM, nm-connection-editor stores "for all users". A profile
with *agent-owned* secrets (flags 1, e.g. what an eduroam CAT installer
creates) has no agent to ask: its password must be stored once (README
"eduroam").

### Live metrics + speedtest (network popup)

Below the addresses: Download / Upload (left; the default-route
interface's `/sys/class/net/<if>/statistics` counters, 1 s, in bit/s) and
Ping / Packet loss (right; ONE `ping -n -q -c 5 -i 0.2 -W 1 -w 4 1.1.1.1`
every 5 s, both numbers from that run - Cloudflare's anycast resolver as
"the internet": answered nearby almost everywhere, no DNS lookup). A
speedometer icon starts `speedtest-cli --secure --json` once (running state,
no second start, 90 s guard); its result is a separate line next to the icon ("HH:MM  down  up Mbit/s
ping ms"), never mixed into the live values. Everything belongs
to the popup: closing it destroys the timers and kills a running ping or
speedtest - nothing measures while it is closed.

### THWS VPN (`fortinet_vpn_enabled`)

FortiGate SSL-VPN via openfortivpn and the NetworkManager plugin
`networkmanager-fortisslvpn` (pinned AUR build, `roles/network` - the
source decision is in its defaults). The popup's VPN section lists the
profile (type `vpn`) and toggles it with `nmcli connection up/down`; the
plugin takes the stored password (flags 0, system profile) - no agent.
`ppp0` counts as a VPN link in the address list. VPN state for the bar:
Quickshell's Networking module reports Wi-Fi/Ethernet only, so a
NetworkManager dispatcher hook (`/etc/NetworkManager/dispatcher.d/
50-workstation-vpn-state`, run by nm-dispatcher on (vpn-)up/down, exits)
rewrites `/run/workstation/vpn-state` (tmpfiles.d creates it at boot);
`Model.qml` watches it (inotify): icon in accent while a VPN is up, "via
VPN" top right in the popup, tunnel addresses hidden the moment NM reports
the disconnect. The gateway forwards only its route list (publisher CDNs
and general internet through the tunnel time out - measured), so library
resources outside it go through the library proxy (README). Split tunnel by profile
(`ipv4.never-default yes`): the gateway pushes ~120 routes; a default
route into the tunnel would cut the internet (measured). Disable: no
packages built/installed any more; plugin + profile stay.

### eduroam (CAT)

The institution's official GÉANT CAT Linux installer (THWS:
`eduroam-linux-THW.py`, PEAP/MSCHAPv2, SSIDs `eduroam` + `THWS`,
`anonymous@fhws.de`, CA + RADIUS server names) is the enrollment tool -
nothing is reimplemented and the script is not in this repository. Its
only dependency is `python-dbus` (roles/network). With NM 1.58 it creates
two NetworkManager profiles over D-Bus (no wpa_supplicant/iwd file of its
own; wpa_supplicant stays NM's D-Bus-activated backend): `802-1x.ca-cert`
= `~/.config/cat_installer/ca.pem`, `domain-match` = the RADIUS server
names, `anonymous-identity`, `permissions user:<you>`. Without
zenity/yad/kdialog/tk it asks in the terminal (`getpass` - never argv).
It marks the password agent-owned, so it is stored once afterwards (see
README). In the popup an enterprise profile is a Known network like any other - via the `nmcli` profile list, since the CAT profiles carry no explicit `802-11-wireless.mode` (see "Popup: Wi-Fi"). First real connect on campus (2026-10-08): autoconnect, internet, addresses/gateway in the popup correct; the profile rows and switching eduroam <-> THWS from the popup: Hardware-only validation.

Real-world items that need real hardware/networks: captive portals
(e.g. BayernWLAN - "Login required" + browser login), eduroam/802.1X
(profile in nm-connection-editor; credentials/CA never in this repo),
Ethernet/Wi-Fi default-route failover. University Fortinet VPN: pending
the university's actual FortiGate configuration - official Arch has
`openfortivpn` (CLI) and `networkmanager-openconnect`/`openconnect`
(OpenConnect speaks Fortinet's protocol in recent versions), while
`networkmanager-fortisslvpn` is AUR-only; nothing is installed until the
real setup (incl. MFA/SAML) is known. Whatever NM ends up managing appears
in the popup's VPN list automatically.

## Packages menu

Core. OS menu -> Packages (`ListPage.qml`: Packages, Packages > Install,
Packages > Remove; entries in `OsMenu.packagesEntries/installEntries/
removeEntries`, also in the type-to-search via `OsMenu.searchEntries`). A
leaf closes the menu and starts `<terminal> -e ~/.local/bin/workstation-pkg
<action>` as a transient systemd user unit - no picker in Quickshell.

| | |
|---|---|
| Helper | `roles/packages/templates/workstation-pkg.j2`: one script, six actions, one shared fzf look (header, Tab multi-select, Esc = no action, result kept on screen until a key) |
| Sources of truth | pacman sync/local databases (`-Ss`, `-Qqen`, `-Qqem`, `-Qs`), the AUR RPC (`/rpc/v5/search/<q>?by=name-desc`, reloaded while typing, nothing cached), `flatpak remote-ls --app` / `flatpak list --app` |
| AUR helper | yay, built once by bootstrap from a pinned AUR commit (makepkg as the user, pacman -U); runtime only - the baseline stays official/upstream/Flatpak first |
| Privileges | `sudo` in the terminal for pacman (the user types the password), yay/makepkg as the user, flatpak's own polkit prompt |
| Snapshots | the existing pacman pre-transaction hook - the helper takes none |
| Idle | nothing: the terminal and fzf exist only while the user works in them |
| Tests | `tests/packages-helper.sh` (stubbed pacman/fzf/yay/flatpak/curl: filters, commands, Esc) |

## Scratchpad (phase 1)

Core. Four fixed plain-text notes in a Quickshell top-level window.

| Contract | |
|---|---|
| Scope | `quickshell/Scratchpad.qml` (singleton: the window handle, `dataDir`, `stateFile`), `scratchpad/ScratchpadWindow.qml`, bar widget `bar/widgets/Scratchpad/` (id `scratchpad`, default right zone); `roles/hyprland`: `mainMod+S` (IPC `scratchpad toggle`), window rule in `conf/appearance.lua` (title `workstation-scratchpad`: float, pin, top right 48 px below the screen edge) |
| Data | `~/.local/share/workstation/scratchpad/{1..4}.txt` (UTF-8, atomic FileView writes; the directory 0700 by Ansible, files never touched by it); `~/.config/workstation/scratchpad.json` = `{note, fontSize}` (fontSize 0 = desktop text size, 8-32) |
| Why a top-level window | Super+Q (`window.close()`) then closes the scratchpad like any window and the shell keeps running; a layer popup would have let Super+Q close the app underneath. A click on free desktop (no focus change) is caught by a transparent Bottom-layer surface that exists only while open. One transient surface at a time: it requests/releases `BarPopups` like the overlays |
| Saving | single-shot 400 ms timer after a change, plus flush on note switch and on every close path (Escape, toggle, focus lost, Super+Q / compositor close, another popup, shell exit) |
| Keys (window only) | Alt+1..4 note, Ctrl+-/Ctrl++ font size, Escape close; no global binds besides mainMod+S |
| Idle cost | closed, there is no window at all (LazyLoader - it exists only while open; a window Hyprland closed cannot be shown again anyway) and no click catcher; the four notes stay in memory; no timer runs while nothing changes, no watcher, no process |
| Phase 2 (not built) | the notes are read once at shell start; syncing (e.g. `dataDir` on a synced Nextcloud folder), external-change detection and conflicts come later |

## Cheatsheet

Core. The keybinding documents in one Quickshell viewer window.

| Contract | |
|---|---|
| Scope | `quickshell/cheatsheet/CheatsheetWindow.qml` (IPC `cheatsheet`: `toggle`, `close`, `state`); `roles/hyprland`: `mainMod+T` (the only key - F1 and Shift+T are not bound), window rule (title `workstation-cheatsheet`: float, center), `cheatsheet.md.j2` -> `~/.local/share/workstation/cheatsheets/hyprland.md` (rendered from the same settings as `binds.lua`); `roles/apps`: `cheatsheet-neovim.md` -> `neovim.md` (Vim / LazyVim / workstation keymaps / VimTeX, checked against the loaded keymaps) |
| Rendering | Qt's own Markdown import (`TextEdit`, `MarkdownText`, read-only): headings, GitHub tables as real tables, inline code, bold, lists. No parser of ours, no WebEngine. Table borders are Qt's default (neutral gray) - MarkdownText offers no table styling; the round trip through Qt's HTML that would allow it hard-codes fonts and loses the heading sizes |
| Search | on the rendered document's plain text (`getText`), which maps 1:1 to document positions - a hit inside a table cell is selected exactly; case-insensitive, current document only; every hit outlined (accent), the current one = the selection (accent / accentForeground), scrolled into view |
| Keys (window only) | normal: Tab document, j/k scroll, `/` search, n/N next/previous hit (wraps), Esc = clear hits, else close. Search field: every key is text (j/k/n too), Tab nothing, Enter search (no hit -> hint, field stays), Esc cancel. Scroll position per document kept while the shell runs; every open starts on Hyprland |
| Close | mainMod+T, Esc, the x button, Super+Q (compositor close), focus lost to another window, a click on free desktop (Bottom-layer catcher, only while open), another shell popup (`BarPopups`) |
| Idle cost | closed, there is no window, no catcher and no file read (LazyLoader; the documents are read on each open); no timer, watcher or process |
| Tests | `tests/keybindings.py` (binds vs. document per host: no duplicates, no stale/missing rows), `tests/cheatsheet-render.qml` (both documents rendered by Qt: tables recognised, search hits exact), `tests/qml-logic.qml` (`findMatches`, `nextIndex`) |

## Firewall + SSH (Hardening v1)

Core (no flag) - except the SSH server, a host capability. Goals: safe on
public Wi-Fi, no accidental LAN exposure of development services, zero
idle cost, development/VPN/LocalSend/Docker unchanged. Deliberately not
here: firewalld/ufw/zones, IDS/IPS, scanners, auditd, MAC frameworks,
outbound filtering.

| Contract | |
|---|---|
| Scope | `roles/firewall` (nftables ruleset, `workstation-firewall.service`, ICMP-redirect sysctl, `firewall-rules` helper + polkit action); `roles/base` (key-only sshd drop-in, `ssh_server_enabled`); Quickshell `firewall/` (window, content, add dialog) + `services/FirewallModel.qml` |
| Packages | `nftables` (the `nft` CLI; filtering is the kernel's) |
| Lifecycle | `workstation-firewall.service`: oneshot at boot (before `network-pre.target`), `nft -f /etc/workstation/firewall.nft` + `firewall-rules restore`, then exits - no process stays. Reload (bootstrap after a ruleset change) = the same two steps. When the run's own `pacman -Syu` replaced the kernel (no `nf_tables` for the running one until reboot), the role installs the ruleset unvalidated, only enables the unit and says so - it loads at the next boot. The window and its helper calls exist only while it is open |
| Table | `inet workstation` only. The file creates-deletes-defines it in one transaction; never `flush ruleset`, never Docker's tables/chains. Sets `share_tcp`, `share_udp` (type `inet_service`) = the user's enabled rules |
| Inbound (`input`, policy drop) | loopback; established/related; invalid dropped; Docker bridges (`docker0`, `br-*`) -> host; ICMP errors; ICMPv6 errors + neighbor/router discovery + MLD query (no echo request); DHCPv4/v6 client replies; LocalSend (udp/53317 to 224.0.0.167, tcp/53317); tcp/22 only with `ssh_server_enabled`; `@share_tcp`/`@share_udp` |
| Docker (`forward`, policy accept) | `-p HOST:CTR` is a DNAT in prerouting - that traffic never reaches `input`, so a plain input firewall would not protect it. Here: established/related, traffic from Docker bridges (containers outbound, container <-> container) and anything not towards a Docker bridge pass; a NEW connection from outside towards a container passes only when it was DNATed and its ORIGINAL destination port (`ct original proto-dst`) is in the share set - the same host port the user typed. Direct routed access to container IPs is dropped. `-p 127.0.0.1:...` stays local by Docker's own design |
| Outbound | unrestricted (no output chain) - VPN clients (WireGuard/OpenVPN/OpenConnect via NetworkManager) need no rule: their traffic is outbound, replies are established |
| sysctl | `accept_redirects = 0` for IPv4 + IPv6, `all`/`default`/every interface (`/etc/sysctl.d/50-workstation-redirects.conf`) |
| SSH | `/etc/ssh/sshd_config.d/10-workstation-key-only.conf`: `PubkeyAuthentication yes`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no` (on every host). `ssh_server_enabled` (default false; laptop + arch-dev true) enables sshd and opens tcp/22; false stops/disables sshd. The SSH client is independent |
| Sharing rules | a new rule is added **disabled** (nothing opens until the user clicks Aktivieren - a typo can never expose a port). A rule = label (1-48 chars, plain text, never interpreted) / port 1-65535 / TCP or UDP (any case, stored upper-case) / enabled. Enabled: LAN can reach that host port (host service AND a Docker-published port). Disabled: unsolicited LAN access to it is dropped. A rule never starts/stops the service: enabled + nothing listening = connection refused; disabled + listening = local use works, LAN blocked. Ports the base policy already opens (LocalSend, DHCP, SSH) are refused - a switch that could not close them would lie |
| State | `/var/lib/workstation/firewall/rules.json` (root, 0644, atomic write + fsync, flock): `{"version": 1, "rules": [{"label", "port", "protocol", "enabled"}]}` - the desired list; the kernel sets are what is live |
| Privilege boundary | `pkexec /usr/local/libexec/workstation/firewall-rules list / add <label> <port> <proto> / enable|disable|remove <port> <proto>`; polkit action `org.workstation.firewall.manage`: active local session = no password, anything else = admin auth. The helper validates every argument, runs `nft` from an argv list with a validated number + one of two fixed set names, touches the kernel first and the state second (rolled back on a failed write), so a successful call always leaves both in agreement; a corrupt state is refused, never overwritten |
| UI | OS menu -> Settings -> Firewall: title + right-aligned "Hinzufügen" (dialog: Bezeichnung / Port / Protokoll), a box with one row per rule "Label / Port / Protocol", the button shows what is LIVE (`Deaktivieren` in `error`, `Aktivieren` in `success`), `×` closes the port and deletes the rule. Infrastructure rules are not listed. IPC `firewall`: `toggle`, `close`, `state`, and test hooks `submit`/`toggleRow`/`removeRow` that run the same paths as the controls (still pkexec + polkit) |
| Persistence | rules survive Quickshell restarts (read from the helper) and reboots (`restore` in the unit) |
| Disable | none for the firewall (core). `ssh_server_enabled: false` = sshd stopped + disabled, tcp/22 closed; key-only drop-in and packages stay |
| Known limits | LocalSend's port is the default 53317 (a custom port set in LocalSend is not followed); NetworkManager hotspot/connection sharing would need its DHCP/DNS opened (not used) |

## Screen sharing

One stack, no second owner: PipeWire + WirePlumber (roles/audio) ->
`xdg-desktop-portal` (frontend) -> `xdg-desktop-portal-hyprland` (the only
ScreenCast/Screenshot backend, `hyprland-portals.conf`: `hyprland;gtk`;
`AvailableSourceTypes` = monitor | window | virtual) with its picker
`hyprland-share-picker` (Qt, `qt6-wayland`). `-gtk` serves FileChooser/
Settings only; no `-wlr`/`-gnome`/`-kde`. Activation env:
`WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP=Hyprland`, `XDG_SESSION_TYPE`
(roles/hyprland). No RemoteDesktop portal (the Hyprland backend does not
implement it): remote *control* features (Zoom's "Request remote
control") are unavailable by design. Clients: Chromium, and Zoom and Discord
as Chromium web apps (WebRTC `getDisplayMedia` via the portal).

**Native Zoom: retired (2026-10-06, laptop).** Flathub `us.zoom.Zoom`
7.2.1 runs on XWayland only (its `xwayland=false` is ignored by the
Flatpak build). Capture worked (portal, DMA-BUF Y-tiled from xdph), but
during a share Zoom "froze": its main thread was idle - the clicks never
arrived. Its share toolbar (`as_toolbar`) and annotation overlay
(`annotate_toolbar`) are override-redirect X11 windows; the overlay was
also tiled by Hyprland over the toolbar, and the toolbar receives pointer
input only after the pointer entered through a managed Zoom window
(XQueryPointer kept the old position until then) - so from the second
share on Stop share / mute did nothing. Window rules fixed only the first
case. Separately, Zoom reads every captured frame back with glReadPixels
(crocus CPU de-tiling, ~one core while sharing). The web client has none
of this and is what the user uses.

## Clipboard history v1

`clipboard_history_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/hyprland` (package, watcher in `session.lua`, mainMod+V bind, start/stop tasks); `roles/quickshell/files/clipboard/ClipboardHistory.qml` |
| Packages | `cliphist` (`wl-clipboard` is core) |
| Lifecycle owner | Hyprland session start: `wl-paste --type text --watch cliphist -max-items 100 store` (one process, event-driven, ~2 MB RSS, 0 % CPU idle); bootstrap in a running session starts it via that Hyprland and replaces it when its command changed; `session-stop` ends it at session end |
| Storage | `~/.cache/cliphist/db` (dir 0700), at most `clipboard_history_max_items` (100) text entries |
| Sensitive content | text only (no images/files); content offered with the password-manager hint (`CLIPBOARD_STATE=sensitive`, e.g. `wl-copy --sensitive`, KeePassXC) is not stored |
| UI | mainMod+V toggles the popup (created only while open): `cliphist list` once, type to search, Enter/click = `cliphist decode ID | wl-copy`, Del/trash = `cliphist delete` (ID on stdin), Clear (two clicks) = `cliphist wipe` |
| Privileges / Network | none / none |
| Disable | watcher stopped, no bind/popup; the history file stays (Disable vs. Purge; `cliphist wipe` clears it) |
| Persistent user data | the history file |

## Wallpaper v1

`wallpaper_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/quickshell/files/wallpaper/` (`Wallpaper.qml` in `shell.qml.j2`, `WallpaperPicker.qml` in `ThemeDialog.qml`); the `theme` helper (`roles/theme`) resolves the wallpaper; `appearance.lua` turns Hyprland's own wallpaper/logo off |
| Registry | `themes/<id>/backgrounds/*.{png,jpg,jpeg,webp,gif}` - the directory is the list, no second registry |
| Packages | `qt6-imageformats` (WebP); first install restarts Quickshell (Qt reads its image plugins once per process) |
| Selection | per theme, runtime state of the `theme` helper (`wallpaper.<id>=<file>` in `~/.config/workstation/theme-state`): `theme wallpaper list|set <file>`; never reset by bootstrap (`theme apply` keeps it). Default: first file in sorted order; none: the theme's background color |
| Apply | the wallpaper rides in `colors.json` and switches with the theme through the existing `theme reload` IPC - no watcher |
| Renderer | the existing Quickshell: one background-layer surface per monitor; `Image` (static, decoded at screen size) or `AnimatedImage` (GIF, looping) - the animated element exists only while a GIF is selected; Qt pixmap cache off |
| Cost (arch-dev, llvmpipe) | static: 0 % CPU; animated GIF 1280x800/24 frames: ~13 % of one core (software rendering) - static is the default recommendation |
| UI | theme dialog (right click on the theme icon): thumbnails of the active theme's backgrounds, GIF badge, click applies |
| Privileges / Secrets / Network | none / none / none |
| Disable | no wallpaper surface/picker; Hyprland's default wallpaper returns; state lines stay |
| Persistent user data | own images in `themes/<id>/backgrounds/` (untracked files are never touched); the per-theme choice |

## Known upstream / VM-only behaviour (evidence from the stability audit)

Not fixed here on purpose - each was reproduced and root-caused on arch-dev:

| What | Evidence | Why it stays |
|---|---|---|
| Session ended from outside (`sudo reboot`/`poweroff` from a TTY or SSH, `loginctl terminate-session`, ACPI power key): hyprpolkitagent SIGSEGV, xdg-desktop-portal-hyprland SIGSEGV, hypridle SIGABRT | Hyprland does not raise `hyprland.shutdown` on SIGTERM (verified), and systemd SIGTERMs the whole session scope at once; stacks: SEGV inside `exit()` destructors marshalling on a dead `wl_display` (xdph: `wl_proxy_marshal_flags`, polkit agent: `sdbus::Variant`), hypridle `std::terminate` (uncaught exception) | upstream exit paths; no second process manager. The normal paths (logout, power menu) go through `session-stop` |
| `hyprland-update-screen` SIGSEGV | one-shot "Hyprland updated" window (hyprland-guiutils), crash in `wl_proxy_destroy` while destroying its own window | upstream, only after a Hyprland update |
| imv 5.0.1 spins at 100 % CPU after the compositor is gone | measured: one core, until the user manager stopped it 10 s after the last session (`UserStopDelaySec`) | upstream; with another session of the user open (SSH, TTY) it keeps running - close it before logging out there |
| `org.bluez` re-activated right after `systemctl stop bluetooth` | WirePlumber's bluez5 monitor, UPower and NetworkManager call `org.bluez` when the name drops (busctl monitor) | upstream D-Bus activation; without a controller `ConditionPathIsDirectory` keeps bluetoothd off |
| hyprlock: ~100 DEBUG lines per lock in `-t hypridle` | `-q` also drops ERR lines (verified with a broken `cmd[]` label: 3 ERR lines without, 0 with) | no errors-only level in hyprlock 0.9.6 - errors win over a quieter journal |
| mpv `--player-operation-mode=pseudo-gui` SIGABRT, zathura/imv need `LIBGL_ALWAYS_SOFTWARE=1` | `__assert_fail` in mpv's VO under software GL | VirtualBox GL 4.1 / llvmpipe only |
| Hyprland itself SIGSEGV at every logout **with two outputs** (laptop: eDP-1 + LG 4K over the dock's HDMI); never with one | stack in `exit()` -> `__cxa_finalize` -> `~CDRMBackend` -> `SDRMConnector::disconnect` -> `cancelAsyncOutput` -> `flushAsyncCommitEvents` (aquamarine 0.15.1, Hyprland 0.56.2), 4/4 with two outputs (also when the session started with both), 0/1 with one; the same without our shutdown hook (diagnostic run), so not `session-stop`; the session's helpers stay clean. Same class as hyprwm/aquamarine#272 (connector teardown in static destruction) | upstream; after Hyprland is done, no user-visible effect besides the core dump; `repo-healthcheck` shows it as WARN (earlier session) |
| Quickshell start: `org.bluez` ObjectManager warning, "Could not register app ID: Connection already associated" | once per start | no BlueZ on a host without controller / Qt's portal registration order - harmless |

## Hardware-only validation

What `arch-dev` (VirtualBox, no battery/Wi-Fi/Bluetooth adapter/GPU,
software rendering) cannot prove - to check once on `laptop` and
`workstation`:

Status on the **laptop** (ThinkPad T440p, Stage 1 bring-up): validated on
the real machine - monitors (eDP-1 + an external 4K HDMI screen over the dock,
hotplug), lid (battery -> lock + suspend x3, docked with an external screen ->
ignored), hardware keys (volume, mute, mic mute + LEDs, brightness), battery
(plug/level icons, AC/undock, percentage + bar, UPower remaining / until full),
power profiles (all three offered on this Haswell), brightness, display, audio
(internal speaker + mic), Wi-Fi (password flows, Ethernet <-> Wi-Fi route),
Bluetooth (pair, connect, disconnect, forget). Still open there: the <= 15 %
notification on the real battery (logic covered by tests/qml-logic.qml), HDMI
audio, captive portal, eduroam, real VPN, Wi-Fi QR with a phone, clipboard with
a password manager. The workstation is not yet deployed.

| Area | Check |
|---|---|
| Monitors | laptop panel + external monitor (hotplug, `hyprland_monitors` explicit entry with scale), bar/wallpaper on every output |
| Lid | closed on battery -> locked, then suspended; on AC -> same; docked (external monitor) -> ignored; resume shows hyprlock, unlock works, displays on |
| Hardware keys | volume +/-/mute, mic mute (+ bar mic icon), brightness +/- (`brightnessctl`, laptop backlight), play/pause/next/prev with a real player; all also while locked |
| Battery (v2) | widget only on the laptop; plug icon on AC, level icons while discharging, <= 15 % error color, one low-battery notification + re-arm after charging / >= 20 %, percentage + charge bar, UPower time remaining / until full, state after suspend/resume |
| Power profiles | Power Saver / Balanced / Performance availability per platform, switching from the battery popup; workstation: no battery widget, default profile `performance` applied once |
| Brightness | backlight slider (bar theme popup + Appearance) moves the real panel; keys and slider agree on the next open |
| Display | Appearance shows each real output (laptop panel + external) with resolution/refresh/scale |
| Audio | real outputs/inputs (speakers, headset, HDMI, Bluetooth headset), default switching moves playing streams, mic mute LED |
| Wi-Fi | scan, Known/Other split, connect to a new WPA2/WPA3 network via password (moves to Known), wrong password -> box stays with error, known reconnect, hover-X forget (reappears under Other only if visible), radio off/on, rfkill hardware switch note |
| Network routing | Ethernet + Wi-Fi: icon follows the default route (unplug -> Wi-Fi, replug -> Ethernet); addresses/gateway/traffic follow; VPN up -> "via VPN" |
| Captive portal | public Wi-Fi with a login page (e.g. BayernWLAN): "Login required" + Log in opens Chromium, after login back to full |
| eduroam / 802.1X | profile set up in nm-connection-editor, connects, reconnects after resume |
| Wi-Fi QR | phone scans the QR and joins; no QR for enterprise networks |
| VPN | real WireGuard profile up/down from the popup; profiles added/imported in nm-connection-editor appear automatically; university Fortinet VPN pending its real configuration |
| Bluetooth | pairing dialogs, row-click connect/disconnect, hover-X forget (no connect), battery %, audio |
| Clipboard | browser/terminal/password-manager copies (KeePassXC/Bitwarden must not appear), paste after selecting |
| Wallpaper | real 4K images, multi-monitor, GIF CPU cost with a real GPU (arch-dev: ~13 % of one core under llvmpipe) |
| Screen sharing | Chromium (WebRTC), Zoom and Discord web apps: entire screen / one monitor / one window via hyprland-share-picker; stop ends the PipeWire stream (`pw-cli ls Node` shows no xdph stream), a second share works |
| Idle baseline | fresh login: process list, RSS/CPU of Quickshell, PPD, clipboard watcher, hypridle; no timers added |
