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
- base provisioning (packages, locale, keymap, sshd)

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
`session` (the processes Hyprland owns), `binds` (incl. hardware keys).
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
  BarPopups.qml      coordinator: at most one bar popup open (singleton)
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
| `connectivity` | core icon | `connectivity_enabled`: Connectivity Center |
| `bluetooth` | `bluetooth_enabled` (whole widget; hidden without adapter) | Bluetooth popup |
| `audio` | core icon + percent (wheel volume, right click mute) | `audio_popup_enabled`: devices/volume (without it left click mutes) |
| `power` | core battery (only with a battery) | `power_profiles_enabled`: profiles (+ profile icon without battery) |
| `coffee` | `lock_idle_enabled` | - |
| `theme` | core | themes + wallpapers |

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
  arrangement (settings stay).
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
  Until a settings menu exists, a right click on free bar space (no
  widget under the pointer - a widget's own right click keeps its
  function, the passive clock is not free space) flips it through the
  same `BarLayout.setBackground()`.
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
  `BarStyle.dragCorridor` (100 px) below the visible 26 px bar (exclusive
  zone stays 26 px - windows never move; back to 26 px right after the
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
  coordinator closes the previous popup on `request()`.
- **Cost**: no process, no watcher, no timer except one short one-shot
  settle timer per drop.

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
| Secrets / Network | none / none |
| Hibernate | shown only if logind `CanHibernate` was `yes`/`challenge` when the host was provisioned; the resume setup itself is the host capability `hibernate_enabled` (see "Hibernate") |
| Lock | listed, unavailable ("not set up") until the Lock/Idle milestone - never faked |
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

## Lock + Idle v1

`lock_idle_enabled` (`group_vars/all.yml`, default `true`). One flag:
lock and idle share the same daemon (hypridle is also the logind Lock
handler), so splitting them would buy nothing.

| Contract | |
|---|---|
| Scope | `roles/hyprland`: packages, `hypridle.conf.j2`, `files/hyprlock.conf`, autostart + bind in `hyprland.lua.j2`; Power Menu Lock entry (`lockAvailable`) |
| Packages | `lock_idle_packages`: `hyprlock`, `hypridle` (official `extra`) |
| Lock path | `loginctl lock-session` only (Super+L, power menu, idle listener, `before_sleep_cmd`) -> logind Lock -> hypridle `lock_cmd` -> `pidof hyprlock \|\| hyprlock` |
| Idle | `lock_idle_lock_timeout` 300 s -> lock, `lock_idle_dpms_timeout` 600 s -> `hl.dsp.dpms` off, on at activity (ext-idle-notify, no polling) |
| Suspend | hypridle holds a logind delay inhibitor until Hyprland reports the session locked (`inhibit_sleep` auto -> lock-notify) |
| Lifecycle owner | Hyprland session start; a bootstrap inside a running session asks that Hyprland to exec it; config/start-command changes restart it (handler) |
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
| UI | items first in the bar's status zone, 15px icons in 24px slots, Passive items hidden, zone invisible with no items; no hover tooltip |
| Actions | left `activate()` (menu for `onlyMenu` items), middle `secondaryActivate()`, right DBusMenu context menu, wheel `scroll()` - only the item's own SNI/DBusMenu interfaces |
| Menu | rendered by us via `QsMenuOpener` (themed, live switch; separators, disabled, checkbox/radio, inline submenus); overlay surface exists only while open, click outside / Escape closes |
| Privileges / Secrets / Network | none / none / none |
| Disable | Loader inactive: no tray component, Quickshell never becomes watcher/host; files stay unreferenced |
| Persistent user data | none |
| Test | `scripts/sni-test-client.py` (on demand, python-gobject only) |

## Bluetooth v1

`bluetooth_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/bluetooth` (packages, `bluetooth.service`); `roles/quickshell/files/bluetooth/` (`BluetoothButton.qml`, `BluetoothPopup.qml` loaded by `Bar.qml`; `bluetooth-agent.py` -> `~/.local/libexec/workstation/bluetooth-agent`) |
| Packages | `bluez`, `python-gobject` (audio: PipeWire's bluez5 plugin is already in `pipewire-audio`; no `bluez-utils`) |
| Lifecycle | `bluetoothd`: systemd system service, enabled; it carries `ConditionPathIsDirectory=/sys/class/bluetooth`, so without an adapter it never runs (zero cost) and udev's `bluetooth.target` starts it when one appears. UI: the existing Quickshell instance. Agent: Quickshell child, only during a user-started pairing |
| API | Quickshell 0.3.1 `Quickshell.Bluetooth` (BlueZ D-Bus, event-driven): `adapter.enabled` = Powered (runtime on/off, never `systemctl`), `adapter.discovering`, `device.connect/disconnect/pair/cancelPair/forget`, `trusted`, `battery` |
| UI | status-zone icon (hidden without adapter; muted off/blocked, normal on, accent connected), no tooltip; popup: power, rfkill soft/hard (one `rfkill --json` read when Blocked, unblock for soft), Connected/Paired/Available, Scan, two-click Forget, in-popup pairing dialogs |
| Scanning | user-started only, auto-stop after 30 s, stopped on popup close if we started it |
| Pairing | Quickshell 0.3.1 has no BlueZ agent; established ones (bt-agent, blueman) are persistent with terminal/own-GUI prompts. `bluetooth-agent` (Gio, ~150 lines): registered as default agent only while pairing, JSON lines over stdin/stdout to the popup (confirm/authorize/PIN/passkey/display), accepts calls only from `org.bluez`'s owner, never logs codes, exits on quit/stdin close/60 s. No agent otherwise: nothing pairs unless the user starts it. Paired devices are trusted + connected |
| Privileges / Secrets / Network | none at runtime (no sudo; `rfkill unblock` as the session user) / no codes stored or logged / Bluetooth radio only |
| Disable | no UI (Loader inactive), `bluetooth.service` disabled + stopped; `/var/lib/bluetooth` pairings and packages kept |
| Persistent user data | BlueZ's own pairing store (`/var/lib/bluetooth`), never touched by us |
| Hardware-only validation | real pairing/agent prompts, connect/disconnect, battery, BT audio via WirePlumber, rfkill soft/hard + unblock (arch-dev has no adapter) |


## Power profiles v1 (+ core battery, lid)

`power_profiles_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/power` (PPD, logind lid drop-in); `roles/quickshell/files/power/` (`PowerControl.qml`, `PowerPopup.qml`, loaded by `Bar.qml`) |
| Core (no flag) | `BatteryIndicator.qml` (hidden without battery; UPower `displayDevice`, percentage 0-1 -> %), `BatteryWatcher.qml` (one critical notification at <= 10 % per discharge cycle, re-armed when charging), lid: `HandleLidSwitch=suspend`, `...ExternalPower=suspend`, `...Docked=ignore` (logind drop-in, SIGHUP, no restart); hypridle locks before sleep |
| Packages | `power-profiles-daemon` |
| Lifecycle | `power-profiles-daemon.service` (systemd, enabled); UI in the existing Quickshell |
| API | Quickshell `PowerProfiles` (PPD D-Bus, event-driven): `profile` set = switch; `hasPerformanceProfile` decides whether Performance is offered; `degradationReason` shown |
| UI | bar widget `power`: battery icon + percent (laptop) or profile icon (no battery) opens the popup: battery state/time, available profiles |
| Privileges | PPD's own polkit policy: switching is allowed for the active local session (not from SSH) - no rule added |
| Secrets / Network | none / none |
| Disable | no popup/profile icon; PPD disabled + stopped; package stays |
| Persistent user data | none (PPD keeps its own last profile) |

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

## Connectivity Center v1

`connectivity_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/quickshell/files/connectivity/` (`ConnectivityControl.qml`, `ConnectivityPopup.qml` loaded by `Bar.qml`; `wifi-qr.py` -> `~/.local/libexec/workstation/wifi-qr`) |
| Packages | `qrencode`, `python-gobject` |
| Owner | NetworkManager (`roles/network`) is the only network owner; nothing else manages Wi-Fi/VPN |
| UI | click on the bar widget `connectivity` (core icon, details in the popup): Wi-Fi (radio on/off, hardware block note, current + available networks with signal/secured/known, connect/disconnect, two-click forget, password field for WPA/WPA2/WPA3-Personal), QR share, Bluetooth summary (on/off, connected; "More" opens the Bluetooth popup, `bluetooth_enabled` only), VPN list |
| Wi-Fi API | Quickshell `Networking` (NM D-Bus): `wifiEnabled`, `scannerEnabled` (only while the popup is open), `connect()`, `connectWithPsk()`, `disconnect()`, `forget()`; the client radio is preferred over a hotspot radio. Enterprise/WEP/hidden networks: `nmtui` |
| Wi-Fi password | typed into a password field, handed to NM (`connectWithPsk`), field cleared; never logged, never stored outside NM |
| QR | only on request, for the active network: `wifi-qr <iface>` reads the PSK via NM `GetSecrets` (NM/polkit decide), pipes the `WIFI:` payload to `qrencode` on stdin (never argv/log/disk), prints SVG; the SVG lives in popup memory and is dropped on network change/close. Exit 2 (enterprise/WEP/OWE/secret not readable, e.g. agent-owned) -> no QR |
| VPN | NM `vpn`/`wireguard` profiles: one `nmcli -t` listing on open and after each action; `nmcli connection up|down uuid <uuid>` (fixed argv). No monitor process: changes made elsewhere show on the next open. VPNs needing interactive secrets (no NM secret agent in this session) report the NM error; university VPN is out of scope for v1 |
| Privileges | NM's own polkit policy for the active session; no sudo |
| Network | none of its own |
| Disable | no popup; the core network label stays; files stay unreferenced |
| Persistent user data | NM connection profiles (created by NM on connect; `forget` deletes on request) |

## Clipboard history v1

`clipboard_history_enabled` (`group_vars/all.yml`, default `true`).

| Contract | |
|---|---|
| Scope | `roles/hyprland` (package, watcher in `session.lua`, mainMod+V bind, start/stop tasks); `roles/quickshell/files/clipboard/ClipboardHistory.qml` |
| Packages | `cliphist` (`wl-clipboard` is core) |
| Lifecycle owner | Hyprland session start: `wl-paste --type text --watch cliphist -max-items 100 store` (one process, event-driven, ~2 MB RSS, 0 % CPU idle); bootstrap in a running session starts it via that Hyprland and replaces it when its command changed |
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

## Hardware-only validation

What `arch-dev` (VirtualBox, no battery/Wi-Fi/Bluetooth adapter/GPU,
software rendering) cannot prove - to check once on `laptop` and
`workstation`:

| Area | Check |
|---|---|
| Monitors | laptop panel + external monitor (hotplug, `hyprland_monitors` explicit entry with scale), bar/wallpaper on every output |
| Lid | closed on battery -> locked, then suspended; on AC -> same; docked (external monitor) -> ignored; resume shows hyprlock, unlock works, displays on |
| Hardware keys | volume +/-/mute, mic mute (+ bar mic icon), brightness +/- (`brightnessctl`, laptop backlight), play/pause/next/prev with a real player; all also while locked |
| Battery | percentage/icon, charging state, time to empty/full in the popup, low-battery notification once at 10 % (and again after a charge cycle) |
| Power profiles | Performance offered only where PPD has it, switching from the popup, degradation note (lap/temperature) |
| Audio | real outputs/inputs (speakers, headset, HDMI, Bluetooth headset), default switching moves playing streams, mic mute LED |
| Wi-Fi | scan, connect to a new WPA2/WPA3 network via password, known network reconnect, wrong password -> re-asked, disconnect, forget, radio off/on, rfkill hardware switch note |
| Wi-Fi QR | phone scans the QR and joins; no QR for enterprise networks |
| VPN | real WireGuard profile up/down from the popup; Uni-VPN still out of scope |
| Bluetooth | (from Bluetooth v1) pairing dialogs, connect, battery, audio; plus the Connectivity Center summary and "More" |
| Clipboard | browser/terminal/password-manager copies (KeePassXC/Bitwarden must not appear), paste after selecting |
| Wallpaper | real 4K images, multi-monitor, GIF CPU cost with a real GPU (arch-dev: ~13 % of one core under llvmpipe) |
| Idle baseline | fresh login: process list, RSS/CPU of Quickshell, PPD, clipboard watcher, hypridle; no timers added |
