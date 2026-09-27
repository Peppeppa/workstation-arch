# Agent Instructions

Binding instructions for any coding agent working in this repository.
This file is the source of truth for *how* to work here. `README.md` is
the user-facing quickstart; `docs/ARCHITECTURE.md` and
`docs/system_architecture.md` are the technical architecture; this file
is process and scope for agents, not a rehash of chat history.

If anything below conflicts with the actual repository state, the
repository state wins — update this file, don't trust it blindly.

## Project

`workstation-arch`: a reproducible Arch Linux workstation definition,
provisioned with Ansible. This is a Git repository that describes
desired system state, not a custom distribution and not a general
"install this on anyone's machine" community project.

Public repository, no secrets, cloned over plain HTTPS onto a machine
that has no credential provider configured yet.

## Goals

Priority order (highest first) — trade-offs get resolved in this order,
not by instinct:

1. Responsiveness
2. Maintainability
3. Idempotency
4. Reliability
5. Low idle resource usage
6. Clear architecture
7. Consistent, good UX/design

"Minimal" means *no unnecessary complexity*, not *fewest packages*. A
proven daemon with a slightly higher footprint beats a fragile
custom reimplementation. Use proven upstream components and configure
them; do not reinvent problems Linux has already solved. See
`docs/system_architecture.md` §2–§3 for the full rationale.

## Target Hosts

Exactly two real, personal machines, used as daily drivers for
university, work, and personal use:

- `laptop`
- `workstation`

Plus any throwaway upstream-Arch test VM (e.g. `arch-dev`) used purely
to validate the common roles — never maintained as a third long-term
product host. `local.yml` runs against `localhost` unconditionally on
any upstream Arch host; an unrecognized hostname just has no
`host_vars/<hostname>.yml` to load, which is expected, not an error.

No automatic hardware-detection engine. Real per-host deltas go in
`host_vars/<hostname>.yml`; nothing invented ahead of actual need.

## Architecture

Two separate layers — do not blur them:

**Provisioning** (runs once per change, then exits):
`bootstrap.sh` → `ansible-playbook local.yml` → roles → Arch system
state.

**Runtime** (what runs day to day):
Arch Linux → Linux kernel → DRM/KMS → Mesa → Wayland → Hyprland →
Quickshell, with XWayland alongside Wayland (compatibility only, never
primary) and systemd supervising everything above the kernel.

Full detail lives in `docs/ARCHITECTURE.md` (short, authoritative
summary) and `docs/system_architecture.md` (75-section rationale, in
German). `docs/ARCHITECTURE.md` must never contradict
`docs/system_architecture.md`; if you change one, check the other.

Omarchy (Quattro) is a UX/visual/workflow *reference only* — never a
runtime dependency, package source, or base distribution. Anything
reused from it is vendored, adapted, and documented, or replaced by a
direct upstream dependency.

## Runtime Ownership (One Owner Per Responsibility)

| Responsibility | Owner |
|---|---|
| Networking | NetworkManager |
| Audio | PipeWire + WirePlumber |
| Bluetooth | BlueZ |
| Compositor / window manager | Hyprland |
| App launcher | fuzzel (**temporary until Quickshell replacement**) |
| Notifications | mako (**temporary until Quickshell replacement**) |
| Polkit authentication agent | hyprpolkitagent (session lifecycle, started once by Hyprland) |
| Screen sharing / screenshot portal | xdg-desktop-portal-hyprland |
| File chooser / settings portal | xdg-desktop-portal-gtk |
| Shell presentation / integration | Quickshell |
| Provisioning / desired state | Ansible |
| Service supervision | systemd |

The portal packages above are D-Bus-activated systemd `--user` services
shipped by their own packages - no exec-once, no manual enable. The
polkit agent and notification daemon are not D-Bus-activatable and are
started exactly once by Hyprland's own session lifecycle (`hl.on
("hyprland.start", ...)` in `roles/hyprland`'s template) - never also as
a systemd user service, per the rule below.

Quickshell displays and controls the above; it is never a second
source of truth for network/audio/bluetooth state. Never introduce a
second component for a responsibility that already has an owner (no
second network manager, no `systemd-networkd` running alongside
NetworkManager, no duplicate notification daemon, no duplicate
autostart mechanism for the same process — not simultaneously via
Hyprland `exec-once`, a systemd user service, *and* a shell startup
hook).

Service ownership defaults:
- machine-wide daemon → systemd system service
- long-lived user daemon → systemd user service
- session-specific process → session lifecycle / Hyprland
- temporary UI helper → started on demand only

## Provisioning Model

```
bootstrap.sh                    (thin launcher, no state of its own)
    ↓
ansible-playbook --ask-become-pass local.yml
    ↓
localhost (connection: local — this project never manages a machine over SSH)
    ↓
roles/*
```

`bootstrap.sh` only: verifies upstream Arch (`ID=arch` in
`/etc/os-release`, Arch derivatives like Omarchy/CachyOS rejected),
verifies it is not run as root, verifies `git` and `ansible-playbook`
are already installed, then hands off to
`ansible-playbook --ask-become-pass local.yml "$@"` and propagates its
exit code. It does not install packages, write files, manage services,
or manage a sudo credential lifecycle of its own (no `sudo -v`, no
keepalive loop, no NOPASSWD, no password file/env var) — Ansible's own
`become`, prompted once via `--ask-become-pass`, is the only
privilege-escalation mechanism. Do not reintroduce a second one; this
was deliberately removed (see commit `4d5ad7e`) after it raced against
Ansible's own become and broke a real run.

`local.yml` runs `pre_tasks` tagged `always`:
1. read `/etc/os-release` `ID`, assert `ansible_distribution == "Archlinux"` and `ID == "arch"` (Arch guard, not skippable via tags)
2. load `host_vars/{{ ansible_facts.nodename }}.yml` if present (optional, `skip: true`)
3. `pacman -Syu` (sync + full upgrade) — **exactly once per run**, regardless of `--tags`

Roles run after, gated by matching tags.

## Ansible Conventions

- Ansible describes **desired state** declaratively. Use idempotent
  modules (`community.general.pacman`, `ansible.builtin.file`,
  `ansible.builtin.template`, `ansible.builtin.systemd_service`, ...).
  Do not reimplement with `shell`/`command` what a module already does
  idempotently.
- **Arch partial upgrades are not allowed.** The full `pacman -Syu` in
  `local.yml`'s `pre_tasks` (tagged `always`) is the only sync+upgrade
  in the whole run. A role installs only its own package list with
  `state: present` and must never call `update_cache`/`upgrade` itself.
- Every role gets its own tag matching its directory name, applied to
  every task in that role (`tags: <rolename>`), so `--tags <rolename>`
  runs it in isolation.
- Package lists live in `roles/<role>/defaults/main.yml` as a variable
  (e.g. `base_packages`), not hardcoded in tasks. Comment *why* each
  package is there and, just as importantly, what was deliberately left
  out and why (see `roles/graphics/defaults/main.yml` for the pattern).

## User vs. System Configuration

- System-level changes (package installs, `/etc`, services) →
  `become: true` on that task.
- User-level changes (`~/.config`, user systemd units) → **no**
  `become` — they must run and be owned as the invoking user. Use
  `ansible_facts.user_id` / `ansible_facts.user_dir` / `user_gid`
  (gathered once at play start, before any escalation) to target the
  real user, and set `owner`/`group`/`mode` explicitly on every
  file/template/directory task.
- The play itself runs `become: false`; only individual tasks that
  genuinely need root set it. Never set `become: true` at the play
  level "for convenience".

## Package Source Policy

Binding priority order for where any application/package comes from:

1. **Official Arch Linux repositories** (`core`/`extra`/`multilib`). Try
   this first for everything, including system-near components.
2. **Official upstream distribution channel** - only if it is clean,
   updatable, and reproducibly manageable by Ansible (a plain package
   repo/registry, not a self-updating installer). A vendor's own
   "toolbox"/self-update-in-place app (e.g. JetBrains Toolbox) does not
   qualify - it manages itself outside package-manager and Ansible
   control, which breaks reproducibility and idempotency.
3. **Flatpak (Flathub)** - only once 1 and 2 are genuinely unsuitable,
   and only for isolated desktop applications. If Flatpak itself isn't
   installed yet, add it and configure the Flathub remote exactly once,
   declaratively (`community.general.flatpak_remote`); manage apps with
   `community.general.flatpak`, ensure-present, same as pacman lists.
   Do not add Flatpak at all while every desired app is cleanly solvable
   without it.
4. **AUR** - last resort only, and never by default. No AUR helper is
   installed as part of this repository's normal provisioning. Do not
   reach for the AUR just because a package happens to exist there -
   check 1-3 first and document why they don't work before considering
   it. If the AUR is ever genuinely necessary, that is a deliberate,
   documented exception, not a default path.

Rules that apply regardless of source:
- No arbitrary `curl | sh` installers.
- Before using a non-Arch source for something, state in the role/PR
  why the higher-priority sources are unsuitable (see `roles/apps` and
  `roles/gaming` for the pattern).
- Keep the install source explicit in Ansible (which module, which
  remote/repo) - never hide it behind a generic wrapper.
- Never silently change an existing app's install source; if a source
  changes, say so explicitly (commit message + doc update).
- No credentials, licenses, or account data of any kind in this
  repository (see Secrets and Public Repository).

## Package Management

- One full `pacman -Syu` per provisioning run, done centrally (see
  Provisioning Model above). Never repeat it in a role.
- Roles install only their own packages via `state: present`.
- `sudo pacman -Syu` between provisioning runs remains the user's own
  responsibility; Ansible is not a substitute for routine maintenance.

## Performance Rules

Applies equally to the older Intel-mobile laptop and the desktop
workstation — lean runtime on both, not just the constrained one.

- Event-driven first (D-Bus signals, etc.); polling only where no
  reasonable event interface exists, and bound to UI visibility (e.g.
  stop when a panel closes) rather than running permanently.
- No unnecessary background wakeups, no permanent diagnostic processes,
  no continuous animation, no unnecessary blur/shadow/transparency.
- Expensive/live data (traffic graphs, speedtest, sensor polling) is
  computed only while the relevant UI is open.
- Bar/panel surfaces status and entry points; it must not become a
  permanent system monitor (no high-frequency CPU/network graphs, no
  constant sensor polling) — that belongs in an applet, opened on
  demand.
- Optimize by measuring, not by assumption: measure → identify
  bottleneck → change → measure again.

Full detail: `docs/system_architecture.md` §30–§34, §74.

## Networking Rules (design constraints — not yet implemented)

NetworkManager remains the sole source of truth. CLI stays first-class
(`nmcli`, `nmtui`, `ip`, `systemctl`, `journalctl`) alongside any future
Quickshell UI — the UI is never the only way to operate the network.

Must support: normal WPA/WPA2/WPA3, WPA Enterprise/eduroam, public
Wi-Fi, and captive portals. Captive portal detection must use
NetworkManager's own connectivity state — never a custom curl-based
heuristic.

The full planned Quickshell network applet (header indicator, known vs.
other networks, forget/connect/disconnect flows, QR sharing of the
*currently connected* network only, info tab, DNS/static-IPv4 profiles,
VPN provider selection à la `omarchy-vpn` UX but with no runtime
dependency on it, live ping/traffic only while that view is open) is
fully specified in `docs/wifi_applet.md` (42 sections). Read it in full
before touching any network-UI work; do not re-derive these
requirements from scratch or narrow them without calling it out.

**VPN foundation** (`roles/network`, no UI yet): `wireguard-tools` is
installed so NetworkManager can import/manage a WireGuard profile
(`nmcli connection import type wireguard file ...`) once one exists.
No actual profile is created or committed here - a real profile has a
real endpoint and keys, which are secrets and belong only in the
separate private-config repository. **Uni-VPN is an open point**: the
institution's actual VPN protocol (possibly Fortinet/FortiGate/
FortiClient, possibly OpenConnect-compatible) is not yet confirmed - do
not guess it or install a proprietary client speculatively. If
NetworkManager/OpenConnect can natively speak the real protocol once
confirmed, prefer that over proprietary FortiClient.

## Secrets and Public Repository

This repository is intentionally public and must **never** contain:
SSH private keys, tokens/API keys, Wi-Fi/VPN passwords, Bitwarden
session data, private certificates, or any other personal credential.

The public bootstrap must never depend on private credentials. Private,
machine-specific configuration is expected to come later from a
separate private repository, and only after a credential provider (e.g.
a Bitwarden SSH agent) is already set up — never as a precondition for
the base bootstrap.

Before finishing any change: scan your diff for anything that looks
like a secret (`git grep` for `password`, `token`, `secret`,
`BEGIN ... PRIVATE KEY`, etc., and eyeball any file that plausibly holds
one) even if the filename looks innocuous.

## VM / Hardware Separation

A throwaway upstream-Arch test VM (`arch-dev` or similar) must pass the
exact same common roles as `laptop`/`workstation` — no VM-only
branches, no hypervisor-guest package added "just in case" to a common
role. If a role ever needs a real VM-specific accommodation, it belongs
in that host's `host_vars/`, added when the need is real, documented as
such — never invented preemptively, and never left as a permanent
manual fix applied by hand on the VM instead of in the repository.

This distinguishes *common roles* (must provision cleanly on any
upstream Arch host, including a disposable test VM) from *opt-in host
capabilities* like gaming (`gaming_enabled`, default `false` — see
`roles/gaming`): a capability that genuinely requires host-specific
hardware facts (a real GPU, in that case) must default to disabled and
be turned on explicitly per real host, never assumed present on a test
VM. Do not create a permanent `host_vars/arch-dev.yml` just to carry a
capability flag a VM should simply inherit as disabled by default.

## Testing

Before considering any Ansible/shell change done, run all of:

```sh
bash -n bootstrap.sh
ansible-playbook --syntax-check local.yml
ansible-inventory --list
```

Also validate every changed YAML file parses
(`python3 -c "import yaml,sys; yaml.safe_load(open(f))"` per file, or
equivalent), and run a secret scan (see Secrets section) before
committing. If the repository later gains a linter config
(`ansible-lint`, `yamllint`, `shellcheck`) or a CI workflow, run those
too and treat their config as authoritative over this list.

A `--check --diff` dry run against a real (or VM) Arch host is strong
evidence a role is correct, but is not a substitute for the commands
above during normal development — reserve real/VM runs for validating
a role that plausibly changes system state in a new way.

## Definition of Done

A feature is **not** done just because it worked once by hand on a VM.
Done means:

- dependencies are declared declaratively (Ansible packages/modules),
  not installed by hand
- all configuration lives in this repository
- services are managed correctly (correct owner, correct scope —
  system vs. user — no duplicate autostart path)
- Ansible reproduces the state from a clean upstream Arch install
- re-running is idempotent (a second run reports no changes)
- no secrets were introduced
- the commands in Testing above pass
- the change is documented (README for user-facing behavior,
  `docs/ARCHITECTURE.md`/`docs/system_architecture.md` for
  architecture-relevant decisions)
- functionality survives reboot/login where relevant
- tested on real hardware when hardware behavior is actually relevant

Distinguish, and state explicitly in any status report, three different
levels — never blend them:
- **implemented**: code/config exists in the repo
- **structurally tested**: syntax-check / check-mode / dry run passed,
  no real system was provisioned with it
- **real (VM or hardware) tested**: an actual `ansible-playbook local.yml`
  run against upstream Arch completed successfully for that
  code — say which host/VM and what the outcome was

## Agent Workflow

**Before changing anything:**
1. Read this file (`AGENTS.md`).
2. Read the relevant docs (`docs/ARCHITECTURE.md`,
   `docs/system_architecture.md`, `docs/wifi_applet.md` if it's
   network-related, `docs/DESIGN_SYSTEM.md` if it's UI-related).
3. Check `git status` — do not build on top of an unexpectedly dirty
   tree without understanding why it's dirty.
4. Understand the existing implementation for the area you're touching
   before writing new code.
5. Only then make the change.

**While changing:**
- Keep scope small and vertical (define requirement → choose backend →
  minimal integration → verify functionality → verify failure behavior
  → measure performance → apply shared design system → real/VM test —
  see `docs/system_architecture.md` §69). Don't build a large abstract
  platform up front.
- Respect existing architecture and the one-owner-per-responsibility
  rule. No new dependency without a concrete reason. No parallel
  ownership systems. No secrets. Build idempotently.
- A manual fix applied directly on a VM is a debugging step, never the
  final solution — it must land back in the repository as declarative
  config.

**After changing:**
1. Run the Testing commands above.
2. `git diff` and `git status` — confirm only intended files changed.
3. Secret scan.
4. Commit with a clear, specific message (imperative mood, explain
   *why* when it's not obvious from the diff — see existing commit
   messages for the expected level of detail).
5. Push only if the checks above are clean. Never force-push. If
   unexpected uncommitted changes exist that you didn't make, stop and
   report instead of overwriting or committing them.

## Current Status

Derived from the actual repository state (git history + code), not from
any external plan. Verify this section against `git log` and the roles
themselves before trusting it — update it whenever status changes.

**Implemented and real-VM-tested** (`arch-dev` VirtualBox VM, clean
upstream Arch, ended `failed=0`):
- Arch guard (`local.yml` pre_tasks + `bootstrap.sh`)
- Ansible startup via `bootstrap.sh` → `ansible-playbook --ask-become-pass local.yml`
- centralized `pacman -Syu` (once per run)
- `base` role: `git`, `openssh`, `curl`, `rsync`
- `graphics` role: `wayland`, `wayland-protocols`, `mesa`, `xorg-xwayland` (Wayland/Mesa/XWayland foundation, no compositor)

**Implemented, structurally tested only** (syntax-check, `--list-tasks`,
standalone Jinja2/Lua render+`luac -p` check, and a standalone
`ansible.builtin.replace` idempotency test all passed in this session;
no evidence yet of a real provisioning run including any of this —
the minimal-usable-daily-driver milestone as a whole is NOT yet
real-VM-tested):
- `hyprland` role: installs `hyprland`, `ghostty` (replaces the earlier
  `foot` placeholder as the default terminal), and `fuzzel` (temporary
  launcher, see Runtime Ownership). Deploys `~/.config/hypr/hyprland.lua`
  with animations/blur/shadow disabled, autostarts `hyprpolkitagent` +
  `mako` once via `hl.on("hyprland.start", ...)`, and binds:
  `Super+Return` (terminal), `Super+Q` (close), `Super+Space`
  (launcher), `Super+[1-9]` / `Super+Shift+[1-9]` (workspace
  switch/move), `Super`+arrows (focus), `Super`+LMB/RMB drag (move/
  resize floating windows), `Super+Shift+S` (region screenshot →
  clipboard), `Print` (fullscreen screenshot → clipboard),
  `Super+Shift+E` (exit). Still no bar, lock/idle, wallpaper, or display
  manager — Hyprland remains manually started from a TTY.
- `desktop` role (new): `hyprpolkitagent`, the
  `xdg-desktop-portal`/`-hyprland`/`-gtk` trio, `wl-clipboard`, `grim`+
  `slurp`, `mako`, `brightnessctl`; adds the invoking user to the
  `video` group for brightness control.
- `audio` role (new): `pipewire`, `wireplumber`, `pipewire-audio`,
  `pipewire-pulse`, `pipewire-alsa` — no PulseAudio in parallel
  (`pipewire-pulse` conflicts with `pulseaudio` at the pacman level).
  No service-enable tasks: these ship socket-/D-Bus-activated systemd
  `--user` units by default.
- `network` role (new): `networkmanager` (enabled+started as a system
  service) + `wireguard-tools` (VPN foundation only, no profile/UI —
  see Networking Rules).
- `virtualization` role (new): `linux-headers`, `virtualbox`,
  `virtualbox-host-dkms`; adds the invoking user to `vboxusers`.
- `gaming` role (new): `steam`, `lutris`, `gamemode`, `lib32-gamemode`.
  **Opt-in host capability** (`gaming_enabled`, default `false` in
  `group_vars/all.yml`) — a host that hasn't opted in gets a clean,
  self-explaining skip (`ansible.builtin.debug` reports status, the
  remaining tasks are `when: gaming_enabled`), not a crash, whether or
  not `--tags gaming` is explicitly requested. Once `gaming_enabled` is
  `true` for a host, it still refuses to install anything
  (`ansible.builtin.assert`) until `gaming_gpu_vulkan_packages` is also
  set — see Package Source Policy note in `roles/gaming` and the
  gaming-gated multilib pre_task in `local.yml` (tagged `gaming`, runs
  before the one central `pacman -Syu`). **Not yet enabled for either
  real host** — see Next Milestone / open points. This was a real,
  arch-dev-discovered bug: the role originally ran unconditionally on
  every host and crashed on arch-dev's empty GPU driver list instead of
  skipping a VM that never asked for gaming.
- `apps` role (new), ensure-present list in
  `roles/apps/defaults/main.yml`: `chromium`, `thunderbird`, `thunar` (+
  `thunar-archive-plugin`, `xarchiver`, `gvfs`, `zip`, `unzip`, `7zip`),
  `yazi`, `neovim` (+ `ripgrep`, `fd`, `ttf-jetbrains-mono-nerd` for
  LazyVim's own requirements — LazyVim itself is not bootstrapped, see
  below), `obsidian`, `bitwarden`, `zathura`+`zathura-pdf-mupdf`,
  `qpdf`, `imv`, `mpv`, `github-cli`; plus Flatpak/Flathub infrastructure
  and `com.jetbrains.IntelliJ-IDEA-Ultimate` (IntelliJ IDEA *Ultimate* -
  Community is available in official Arch but is a different product).

**Not started (no code yet):** Quickshell foundation, Bluetooth,
session/lock/idle, hardware-specific optimization.

**Deliberately deferred this run — open points, not oversights:**
- **LazyVim bootstrap**: Neovim is installed; LazyVim itself is user
  *configuration*, not a package, and was not auto-bootstrapped into
  `~/.config/nvim`. This machine's own Hyprland config already sources
  personal settings (`bindings.lua`, `input.lua`, `monitors.lua`) from a
  separate `dotfiles-stow`-managed repository rather than this one —
  before writing `~/.config/nvim` here, decide whether Neovim config
  should live in this repo or follow that same dotfiles-stow pattern,
  to avoid silently conflicting with however the real hosts already
  handle it.
- **WebCord**: not in official Arch repos; its own Flathub packaging
  was marked EOL/archived by WebCord's maintainer (fails the "clean,
  updatable" bar); the AUR package would require installing an AUR
  helper, which the Package Source Policy forbids by default. Use
  Discord's web app via Chromium until this is resolved.
- **`gaming_enabled` / `gaming_gpu_vulkan_packages`**: neither is set
  for `laptop` or `workstation` — real GPU hardware was not provided
  and must not be guessed. Gaming stays disabled on both real hosts
  until their real GPU is documented and both variables are set
  together in the relevant `host_vars/<hostname>.yml` (see
  `group_vars/all.yml` and the comments in both `host_vars/*.yml`).
- **Uni-VPN**: protocol not confirmed — see Networking Rules.
- **Webapp management** (GeForce NOW, WhatsApp, Overleaf, draw.io): all
  via Chromium as plain web pages for now. A declarative webapp list
  generating `.desktop` entries (so Quickshell's launcher can later show
  them like native apps) is a documented future idea, not built.

**Documentation gaps found during the prior audit, still open:**
- `docs/DESIGN_SYSTEM.md` exists but is **empty (0 bytes)**.
  `docs/system_architecture.md` §18/§33 and `docs/wifi_applet.md` §33
  both require a shared design system before shell UI work — this is a
  real blocker for starting Quickshell cleanly, not just a nice-to-have.
- `config/`, `systemd/`, `hardware/`, and `scripts/diagnostics/` appear
  in `README.md`'s repository-structure diagram but hold no tracked
  files (git does not track empty directories) — a fresh clone will not
  have them. Don't assume they exist; create them with real content
  when the corresponding role is actually built, or fix the README
  diagram if they turn out unnecessary.

## Next Milestone

**Real (VM) validation of this session's minimal-usable-daily-driver
work on `arch-dev`, THEN Quickshell foundation.** Per this file's own
Definition of Done, none of the roles added/changed in this session
(`hyprland` changes, `desktop`, `audio`, `network`, `virtualization`,
`apps`, and `gaming` once a real host opts in via `gaming_enabled`)
count as done until a real `ansible-playbook local.yml` run completes
successfully against clean upstream Arch and the manual checks in the
exact `arch-dev` test commands (see the report accompanying this
change, or ask for them again) all pass — TTY login → `Hyprland` →
Ghostty/fuzzel/Chromium/Thunar/audio/clipboard/region-screenshot/
notifications/workspaces/clean exit. `gaming` stays disabled
(`gaming_enabled: false`) on `arch-dev` for this validation - that is
the correct, expected outcome, not a gap to fix there.

Once that passes: start Quickshell foundation by writing
`docs/DESIGN_SYSTEM.md` (colors, spacing, typography, motion rules
consistent with the "responsiveness over decoration" stance already set
in the `hyprland` role), then add a minimal `roles/quickshell` that only
installs the package and gets an empty/near-empty config loading under
Hyprland — no widgets, no bar content yet, and no need to keep fuzzel/
mako once Quickshell can replace them (see Runtime Ownership). Do not
start Bluetooth or session/lock/idle before this lands.
