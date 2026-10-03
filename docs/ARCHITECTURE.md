# Architecture

Short, authoritative summary of the system-wide rules. Detailed
per-subsystem rationale lives in `docs/system_architecture.md`; this file
must not contradict it.

## Two layers: provisioning vs. runtime

These are deliberately separate concerns.

**Provisioning layer** - runs once per change, then exits:

```
bootstrap.sh
    ↓
Ansible (local.yml)
    ↓
localhost roles (roles/*)
    ↓
Arch system state
```

**Runtime layer** - what actually runs on the machine day to day:

```
Arch Linux
    ↓
Linux kernel
    ↓
DRM / KMS
    ↓
Mesa
    ↓
Wayland
    ↓
Hyprland
    ↓
Quickshell
```

XWayland sits alongside Wayland as a compatibility layer for X11-only
applications - it is not the primary display stack, native Wayland is.

Phase 3 (current) implements Hyprland itself: the compositor, window
manager, and Wayland session owner, started manually from a TTY (no
display manager, no autostart hook, no systemd unit). Quickshell is a
later, separate presentation layer on top of Hyprland - Hyprland has no
dependency on it and must be fully usable (start, open a terminal,
close windows, exit cleanly) without it.

`systemd` supervises everything above the kernel (services,
`NetworkManager`, `PipeWire`/`WirePlumber`, `BlueZ`, ...); it isn't a
step in the graphics stack itself but the process supervisor underneath
all of it.

Ansible is provisioning only. It is not a runtime service: it is not
installed as a daemon, does not run continuously, and leaves no
permanent resource usage behind once a run finishes. `bootstrap.sh` is a
thin launcher around it - see `AGENTS.md` and `README.md` for how it is
invoked and what it does.

Responsibility split within the provisioning layer:

- `bootstrap.sh` = prerequisite/environment validation (upstream Arch,
  not root, `git`/`ansible` present) and launching Ansible. It holds no
  system state and manages no credentials of its own.
- Ansible (`local.yml` + roles) = provisioning / desired state.
- Ansible `become` = privilege escalation for the individual system
  tasks that need it (`--ask-become-pass` prompts for it once per run).
  There is no separate sudo credential lifecycle (no keepalive, no
  cached timestamp management) outside of Ansible's own `become`.

## One owner per responsibility

- NetworkManager owns networking state.
- PipeWire/WirePlumber own audio state.
- BlueZ owns Bluetooth state.
- hyprpolkitagent owns polkit authentication; xdg-desktop-portal-hyprland
  owns screen sharing/screenshot portals; xdg-desktop-portal-gtk owns
  the file-chooser portal. All are started exactly once - the portals by
  their own D-Bus-activated systemd `--user` units, the polkit agent by
  Hyprland's session lifecycle.
- Quickshell owns the app launcher (fuzzel retired as of Core Desktop
  v1) and notifications (mako retired as of Notifications v1) - see
  AGENTS.md.
- Quickshell owns presentation - it displays and controls the above, it
  never becomes a second source of truth for them.

No two components compete for the same responsibility (e.g. no second
network manager, no second notification daemon, no duplicate autostart
mechanism for the same process).

## Ansible is the state description, not a second script layer

Ansible roles describe desired state declaratively (packages, files,
services, ...) using built-in/collection modules
(`ansible.builtin.package`, `community.general.pacman`,
`ansible.builtin.file`, `ansible.builtin.template`,
`ansible.builtin.systemd_service`, ...). Bash is only a thin bootstrap
wrapper around Ansible, never a second, parallel configuration-management
system re-implementing "is this installed / does this file exist / is
this service enabled" checks that an Ansible module already does
idempotently.

## Event-driven, not polling

Backends emit events (D-Bus signals where available); Quickshell reacts.
Polling is allowed only where no reasonable event interface exists, and
should be bound to UI visibility (e.g. stop when a panel closes) rather
than running permanently.

## Idle stays quiet

No unnecessary background wakeups, no permanent diagnostic processes, no
continuous animation. Minimal permanent polling is a hard requirement,
not an optimization to get to later. This applies equally to an older
Intel-mobile laptop and to the desktop workstation - the runtime stays
lean on both, not just the constrained one.

## Omarchy Quattro is a reference, not a dependency

Omarchy Quattro is used as a UX, design, and workflow reference where it
already solves a problem well. It is never a runtime dependency, package
source, or base distribution. The finished system stays upstream Arch
Linux; anything reused from Omarchy is vendored, adapted, and documented,
or replaced by a direct upstream dependency.

## Responsiveness is a primary design constraint

Instant interaction takes priority over decorative animation: minimal
blur/shadows/transparency, minimal animation, proven upstream components
over clever custom replacements. See `docs/system_architecture.md` §74
for the full trade-off ordering.

## Public bootstrap, private secrets

See `AGENTS.md`. This repository is public and contains no secrets;
private, machine-specific credentials come from a separate private
repository, only once a credential provider is configured.
