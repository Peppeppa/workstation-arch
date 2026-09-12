# workstation-arch

A reproducible, minimal Arch Linux desktop, built as a Git repository
instead of a custom distribution. See `BOOTSTRAPPER.md` for the project's
architecture and workflow rules.

```
Clean Arch
    │
    ▼
git clone
    │
    ▼
./bootstrap.sh
    │
    ▼
reboot
    │
    ▼
working workstation
```

## Status: Phase 1 - bootstrap framework

Only the bootstrap framework and a minimal set of base packages are
implemented so far. The desktop itself (Hyprland, Quickshell, audio/
Bluetooth stack, themes, ...) is **not yet installed or configured** by
this repository.

## Requirements

- a clean Arch Linux installation (`ID=arch` in `/etc/os-release`)
- `pacman` and `sudo` available
- a normal user account that can use `sudo`
- this repository cloned onto that machine

## Usage

```sh
git clone <this-repo-url> workstation-arch
cd workstation-arch
./bootstrap.sh
```

Run it as your normal user - **not** `sudo ./bootstrap.sh`. Individual
steps request `sudo` themselves only where privileged actions (installing
packages) are actually needed.

`./bootstrap.sh` is safe to run again. It checks the current state before
changing anything and skips whatever is already in place.

## What phase 1 currently does

1. Validates the environment:
   - not running as root
   - running on Arch Linux with `pacman` available
   - `sudo` is installed and the current user can authenticate with it
   - the expected repository files (`packages/base.txt`,
     `scripts/install/`) are present
2. Installs the packages listed in `packages/base.txt`, skipping any that
   are already installed.

Nothing else. No desktop components, no services are enabled, no configs
are deployed yet.

## Pacman / update policy

Arch Linux is a rolling release; syncing the package database without
upgrading the rest of the system (`pacman -Sy` without `-u`) risks a
partial upgrade. When `bootstrap.sh` needs to install missing base
packages, it does so with `pacman -Syu --needed <packages>` - a full
sync-and-upgrade together with the install - never a bare `-Sy`.

If every base package is already installed, `bootstrap.sh` does not touch
pacman at all. It is not a replacement for routine system maintenance;
running `sudo pacman -Syu` yourself remains your responsibility.

## Repository structure

```
.
├── README.md
├── BOOTSTRAPPER.md
├── bootstrap.sh
├── docs/
├── packages/
│   └── base.txt        # phase 1 base packages
├── config/
├── systemd/
├── scripts/
│   ├── install/         # bootstrap modules, sourced by bootstrap.sh
│   └── helpers/         # shared shell helpers (logging, ...)
└── hardware/
```
