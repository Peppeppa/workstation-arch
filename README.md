# workstation-arch

A reproducible Arch Linux workstation, provisioned with Ansible instead
of hand-configured - built as a Git repository, not a custom
distribution. See `BOOTSTRAPPER.md` for the project's architecture and
workflow rules, and `docs/ARCHITECTURE.md` for the full system
architecture.

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

Ansible is now the primary provisioner. The `base` role (Arch base
packages) is implemented. The rest of the desktop - graphics/Wayland
foundation, Hyprland, Quickshell, audio, Bluetooth, session, hardware
specifics - is **not yet implemented**; those will be added as further
roles under `roles/`.

## Requirements

- a clean, upstream Arch Linux installation (`ID=arch` in
  `/etc/os-release` - Arch derivatives are not supported targets)
- `pacman` and `sudo` available
- a normal user account that can use `sudo`
- working network access (NetworkManager)

## Quickstart (fresh Arch)

```sh
sudo pacman -Syu --needed git ansible
git clone https://github.com/Peppeppa/workstation-arch.git
cd workstation-arch
./bootstrap.sh
```

No SSH key or credential provider is required - the repository is public
and cloned over HTTPS. `bootstrap.sh` also installs `git`/`ansible`
itself if they are missing, so the `pacman` line above is optional but
recommended for a first, explicit run.

Run it as your normal user - **not** `sudo ./bootstrap.sh`. You will be
asked for your sudo password **at most once**; `bootstrap.sh` validates
it up front and keeps the credential cache alive in the background for
the rest of the run (cleaned up on exit, including Ctrl+C or a failure),
so nothing prompts for it again mid-run. Ansible itself escalates
per-task with `become: true` only where actually needed - the play does
not run entirely as root.

`./bootstrap.sh` is safe to run again; so is `ansible-playbook local.yml`
directly. Both are idempotent - already-satisfied state is reported as
unchanged, nothing is reinstalled or reconfigured unnecessarily.

## Provisioning commands

Normal run (via the bootstrap wrapper, or directly):

```sh
./bootstrap.sh
# equivalent to, once git/ansible are installed:
ansible-playbook local.yml
```

Dry run (no changes made, just what *would* change):

```sh
./bootstrap.sh --check --diff
# or directly:
ansible-playbook local.yml --check --diff
```

Only run a specific part, by tag:

```sh
./bootstrap.sh --tags base
```

`bootstrap.sh` forwards any extra arguments straight to
`ansible-playbook`, so both forms work the same way.

## Roles

| Role   | Tag    | What it does                                    |
|--------|--------|--------------------------------------------------|
| `base` | `base` | Minimal Arch base packages (git, openssh, curl, rsync) |

Further roles (`graphics`, `hyprland`, `quickshell`, `network`, `audio`,
`bluetooth`, `session`, `hardware`, ...) will be added the same way as
the desktop is built out - see `docs/ARCHITECTURE.md` for the intended
stack.

## Pacman / update policy

Arch Linux is a rolling release; syncing the package database without
upgrading the rest of the system risks a partial upgrade. The `base`
role's `community.general.pacman` task therefore always runs with
`update_cache: true` and `upgrade: true` together with installing the
package list - a full sync-and-upgrade together with the install, the
Ansible equivalent of `pacman -Syu --needed`, never a bare sync. Package
modules run non-interactively already; no manual `--noconfirm` is
needed, but errors (conflicts, bad signatures, corrupted packages) still
fail the play instead of being silently worked around.

Ansible is not a replacement for routine system maintenance; running
`sudo pacman -Syu` yourself between provisioning runs remains your
responsibility.

## Host model

Two real target machines, `laptop` and `workstation`, share almost
everything. `group_vars/all.yml` holds shared defaults; `host_vars/`
holds only genuine per-host deviations, added when they actually arise
- not invented ahead of time. `local.yml` runs against the implicit
`localhost` (this project never manages a machine over SSH) and loads
`host_vars/<real hostname>.yml` explicitly, keyed by the machine's actual
hostname - no automatic hardware-detection engine.

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
├── BOOTSTRAPPER.md
├── bootstrap.sh          # thin wrapper: validate env, install git+ansible, run Ansible
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
│   └── base/              # Arch base packages
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
