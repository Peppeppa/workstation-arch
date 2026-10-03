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

Today: one feature (screenshots), two binds, one `{% if %}` block in
`hyprland.lua.j2` - proportionate, no extra structure needed.

If/when several features each need their own binds and the file starts
accumulating many such blocks, the natural next step - still
Jinja/Ansible-native, no custom DSL - is to split feature binds into
their own template(s) and pull them in with Jinja's own `{% include %}`
(or a small `{% for %}` over an explicit list of enabled features' bind
templates), keeping `hyprland.lua.j2` itself to core binds plus one
include line. Do not build this before there is a second or third
feature bind that actually needs it.

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

Not implemented now: no Quickshell feature is being added this
milestone (screenshots has no UI component). This section documents
the pattern for when one is.

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
  screenshot.sh` -> `~/.local/bin/screenshot`, modes `region`/
  `monitor` - `roles/desktop/tasks/main.yml`), which owns file naming
  (`~/Pictures/Screenshots/Screenshot_<timestamp>.png`, collision-safe,
  respects a custom XDG Pictures dir via `xdg-user-dir`), the
  `wl-copy` clipboard write, and the `notify-send` confirmation
- the two Hyprland binds that start it (`Print` -> region, `mainMod +
  SHIFT + S` -> current monitor -
  `roles/hyprland/templates/hyprland.lua.j2`)

No Quickshell component, no persistent process - the script is started
on demand by the bind and exits on its own once done (see `AGENTS.md`
Runtime Ownership "temporary UI helper -> started on demand only"), no
new privileges. Feature Category A (provisioning-only) plus Category B
(Hyprland binds).
