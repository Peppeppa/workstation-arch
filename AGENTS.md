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
| Shell presentation / integration | Quickshell |
| Provisioning / desired state | Ansible |
| Service supervision | systemd |

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

**Implemented, structurally tested only** (syntax-check/YAML-valid in
this session; no evidence yet of a real provisioning run including this
role):
- `hyprland` role: installs `hyprland` + `foot`; deploys
  `~/.config/hypr/hyprland.lua` (current Hyprland reads Lua, not
  `hyprland.conf`) as the invoking user, with a monitor fallback,
  animations/blur/shadow disabled, and three temporary dev keybinds
  (`Super+Return` → terminal, `Super+Q` → close window,
  `Super+Shift+E` → exit). No bar, launcher, notifications, lock/idle,
  wallpaper, display manager, or Quickshell yet — Hyprland must remain
  fully usable standalone.

**Not started (no code yet):**
- Quickshell foundation and every later phase (shell UX, audio,
  network UI, Bluetooth, session/power/lock, hardware integration)
- `roles/network`, `roles/audio`, `roles/bluetooth`, `roles/quickshell`,
  `roles/session` don't exist yet — NetworkManager/PipeWire+WirePlumber/
  BlueZ are documented as future owners, not yet provisioned by this
  repository.

**Documentation gaps found during this audit:**
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
- `group_vars/all.yml` and both `host_vars/*.yml` are intentionally
  empty stubs (`{}`) — correct per the "no invented deltas" rule, but
  expect to give them real content the moment `laptop` and
  `workstation` actually diverge (e.g. GPU driver, power policy).
- `BOOTSTRAPPER.md` has been removed: its entire content (provisioner
  model, become rules, public-bootstrap/no-secrets policy) is now
  covered by this file and `docs/ARCHITECTURE.md`, and it had drifted
  into being a second, overlapping source of truth for agent behavior.

## Next Milestone

**Quickshell foundation (phase 04)** — but start by writing
`docs/DESIGN_SYSTEM.md` (colors, spacing, typography, motion rules
consistent with the "responsiveness over decoration" stance already set
in the `hyprland` role), then add a minimal `roles/quickshell` that only
installs the package and gets an empty/near-empty config loading under
Hyprland — no widgets, no bar content, no launcher yet. Do not start
audio, network UI, or Bluetooth before this lands; they all assume a
working shell foundation and, for network UI specifically, an existing
design system per `docs/wifi_applet.md` §33.
