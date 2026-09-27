# workstation-arch

A reproducible Arch Linux workstation, provisioned with Ansible instead
of hand-configured - built as a Git repository, not a custom
distribution. See `AGENTS.md` for agent/contributor workflow rules, and
`docs/ARCHITECTURE.md` for the full system architecture.

This project targets exactly two personal machines - `laptop` and
`workstation` - which share the same base system and eventually the same
Arch/Hyprland/Quickshell desktop, with real per-host differences (not
invented ones) isolated in `host_vars/`. It is not intended as a general
"install this on anyone's machine" community project.

```
Fresh Arch
    │
    ▼
working network (NetworkManager)
    │
    ▼
git clone (HTTPS)
    │
    ▼
./bootstrap.sh
    │
    ▼
Ansible provisions localhost
    │
    ▼
reboot
    │
    ▼
working workstation
```

## Public repository, no secrets

This repository is the public source of truth for the desired system
state. It intentionally contains **no secrets**: no private SSH keys, no
tokens, no Wi-Fi/VPN credentials, no Bitwarden data. A freshly installed
Arch machine has no credential provider configured yet, so this
repository is designed to be cloned over plain HTTPS - no SSH key
required.

Private, machine- or user-specific configuration (credentials, private
repositories, ...) is expected to come later from a **separate private
repository**, used only after a credential provider (for example a
Bitwarden SSH agent) has been set up. That is not part of this
repository.

## Status

Ansible is now the primary provisioner. `base` (Arch base packages),
`graphics` (Wayland/Mesa/XWayland foundation), and `hyprland` (a
minimal, manually-started Hyprland session) are implemented. There is
still no shell (Quickshell), no audio/Bluetooth stack, no display
manager, no lock/idle, and no theming - those will be added as further
roles under `roles/`.

## Requirements

- a clean, upstream Arch Linux installation (`ID=arch` in
  `/etc/os-release` - Arch derivatives are not supported targets)
- a normal user account that can use `sudo`
- working network access (NetworkManager)
- `git` and `ansible` already installed (`sudo pacman -Syu --needed git
  ansible`) - `bootstrap.sh` checks for both but does not install them

## Quickstart (fresh Arch)

```sh
sudo pacman -Syu --needed git ansible
git clone https://github.com/Peppeppa/workstation-arch.git
cd workstation-arch
./bootstrap.sh
```

No SSH key or credential provider is required - the repository is public
and cloned over HTTPS. The first line (installing `git` and `ansible`)
is a one-time prerequisite you run yourself; `bootstrap.sh` checks that
both are present but does not install them.

Run it as your normal user - **not** `sudo ./bootstrap.sh`. Ansible will
prompt once for `BECOME password:` (your normal sudo password) and use
it for whichever tasks in the run actually need root - the play itself
does not run entirely as root, and `bootstrap.sh` never sees or stores
that password itself.

`./bootstrap.sh` is safe to run again; so is `ansible-playbook local.yml`
directly. Both are idempotent - already-satisfied state is reported as
unchanged, nothing is reinstalled or reconfigured unnecessarily.

## Privilege escalation

Ansible owns privilege escalation, not `bootstrap.sh`. Individual tasks
that genuinely need root (installing packages, editing `/etc`, managing
system services) are marked `become: true`; the play itself runs
`become: false`, and later user-level configuration (`~/.config`, user
systemd services, ...) is never run as root just because some other task
in the same play needed `become`.

`bootstrap.sh` calls `ansible-playbook --ask-become-pass`, so Ansible
asks for the become password once, up front, and manages it for the
rest of that run itself. `bootstrap.sh` does not run `sudo -v`, does not
cache or refresh any credential itself, and does not write a password
anywhere - there is exactly one privilege-escalation mechanism
(Ansible's `become`), not two competing ones.

## Provisioning commands

Normal run (via the bootstrap launcher, or directly):

```sh
./bootstrap.sh
# equivalent to:
ansible-playbook --ask-become-pass local.yml
```

Dry run (no changes made, just what *would* change):

```sh
./bootstrap.sh --check --diff
# or directly:
ansible-playbook --ask-become-pass local.yml --check --diff
```

Only run a specific part, by tag:

```sh
./bootstrap.sh --tags base
./bootstrap.sh --tags graphics
./bootstrap.sh --tags hyprland
```

`bootstrap.sh` forwards any extra arguments straight to
`ansible-playbook`, so both forms work the same way.

## Roles

| Role       | Tag        | What it does                                              |
|------------|------------|------------------------------------------------------------|
| `base`     | `base`     | Minimal Arch base packages (git, openssh, curl, rsync)     |
| `graphics` | `graphics` | Wayland/Mesa/XWayland foundation - no compositor yet       |
| `hyprland` | `hyprland` | Minimal, manually-started Hyprland session (no shell yet)  |

Further roles (`quickshell`, `network`, `audio`, `bluetooth`, `session`,
`hardware`, ...) will be added the same way as the desktop is built out
- see `docs/ARCHITECTURE.md` for the intended stack.

## Hyprland session (manual start, no display manager)

Phase 3 sets up Hyprland just enough to start and stop it by hand - it
deliberately does **not** install a display manager, does not add any
`.bash_profile`/`exec Hyprland` autostart hack, and does not install a
shell (Quickshell), bar, launcher, notification daemon, lock/idle
daemon, or wallpaper tool yet. After provisioning and a reboot:

```sh
reboot
# then, after logging in on a plain TTY:
Hyprland
```

The deployed config (`~/.config/hypr/hyprland.lua` - current Hyprland
reads Lua, not the older `hyprland.conf` format) only defines a monitor
fallback, disables animations/blur/shadow (this project prioritizes
responsiveness over decoration - see `docs/ARCHITECTURE.md`), and three
temporary development keybinds:

| Keybind            | Action                     |
|---------------------|----------------------------|
| `Super + Return`     | open a terminal (`foot`)   |
| `Super + Q`          | close the focused window   |
| `Super + Shift + E`  | exit Hyprland (back to TTY)|

These are not the final UX - just enough to confirm the session works.

## Pacman / update policy

Arch Linux is a rolling release; syncing the package database without
upgrading the rest of the system risks a partial upgrade. `local.yml`
therefore syncs and fully upgrades the system exactly **once** per
provisioning run, in a `pre_task` tagged `always` (so it runs regardless
of which `--tags` you select) - the Ansible equivalent of `pacman -Syu`,
never a bare sync. Individual roles (`base`, `graphics`, and future
ones) only ever install their own package list (`state: present`); none
of them repeats the sync/upgrade, so a run never does more than one full
system upgrade no matter how many package-installing roles it touches.
Package modules run non-interactively already; no manual `--noconfirm`
is needed, but errors (conflicts, bad signatures, corrupted packages)
still fail the play instead of being silently worked around.

Ansible is not a replacement for routine system maintenance; running
`sudo pacman -Syu` yourself between provisioning runs remains your
responsibility.

## Host model

Two real target machines, `laptop` and `workstation`, share almost
everything. `group_vars/all.yml` holds shared defaults; `host_vars/`
holds only genuine per-host deviations, added when they actually arise
- not invented ahead of time.

`local.yml` runs against the implicit `localhost` (this project never
manages a machine over SSH) and loads `host_vars/<real hostname>.yml`
explicitly, keyed by the machine's actual hostname - no automatic
hardware-detection engine. This means the common roles (`base`,
`graphics`, ...) apply unconditionally to **any** upstream Arch host,
including a throwaway test VM that isn't named `laptop` or
`workstation`: an unrecognized hostname simply has no `host_vars` file
to load, which is expected and not an error. `inventory/localhost.yml`
intentionally does *not* declare `laptop`/`workstation` as separate
inventory hosts - `local.yml` never targets them by name, so doing that
would be decorative at best and misleading at worst (e.g. `--limit
laptop` would silently match nothing).

## Arch guard

Both `bootstrap.sh` and `local.yml` independently verify `ID=arch` in
`/etc/os-release` before doing anything else (`local.yml` also checks
Ansible's own `ansible_distribution` fact). Arch derivatives that report
themselves as Arch-like (e.g. Omarchy, CachyOS) are deliberately not
accepted as provisioning targets - this project's development machine
happens to run one such derivative, which is exactly why both guards
exist and are not skippable via tags.

## Repository structure

```
.
├── README.md
├── AGENTS.md
├── bootstrap.sh          # launcher: validate env, check prerequisites, run Ansible
├── ansible.cfg
├── local.yml             # Ansible entry point
├── inventory/
│   └── localhost.yml
├── group_vars/
│   └── all.yml           # shared defaults (empty until needed)
├── host_vars/
│   ├── laptop.yml         # real per-host overrides (empty until needed)
│   └── workstation.yml
├── roles/
│   ├── base/              # Arch base packages
│   ├── graphics/          # Wayland/Mesa/XWayland foundation
│   └── hyprland/          # minimal, manually-started Hyprland session
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DESIGN_SYSTEM.md
│   └── system_architecture.md
├── config/
├── systemd/
├── scripts/
│   └── helpers/           # log.sh, used by bootstrap.sh
└── hardware/
```
