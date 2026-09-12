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

## Public repository, no secrets

This repository is the public source of truth for the desktop bootstrap.
It intentionally contains **no secrets**: no private SSH keys, no tokens,
no Wi-Fi/VPN credentials, no Bitwarden data. A freshly installed Arch
machine has no credential provider configured yet, so the base bootstrap
is designed to be cloned over plain HTTPS - no SSH key required.

Private, machine- or user-specific configuration (credentials, private
repositories, ...) is expected to come later from a **separate private
repository**, used only after a credential provider (for example a
Bitwarden SSH agent) has been set up. That is not part of phase 1 and not
a precondition for using this repository.

## Status: Phase 2 - graphics/Wayland foundation

Phase 1 (bootstrap framework + base packages) is done. Phase 2 adds the
graphics/Wayland foundation packages (Mesa, Wayland, XWayland). The
compositor and shell (Hyprland, Quickshell), audio/Bluetooth stack, and
themes are **not yet installed or configured** by this repository.

## Requirements

- a clean Arch Linux installation (`ID=arch` in `/etc/os-release`)
- `pacman` and `sudo` available
- a normal user account that can use `sudo`
- this repository cloned onto that machine

## Usage

```sh
sudo pacman -S --needed git
git clone https://github.com/Peppeppa/workstation-arch.git
cd workstation-arch
./bootstrap.sh
```

No SSH key or credential provider is required for this step - the
repository is public and cloned over HTTPS.

Run it as your normal user - **not** `sudo ./bootstrap.sh`. Individual
steps request `sudo` themselves only where privileged actions (installing
packages) are actually needed.

`./bootstrap.sh` is safe to run again. It checks the current state before
changing anything and skips whatever is already in place.

You will be asked for your sudo password **at most once** per run (via
`sudo -v` at the start); the bootstrap keeps those credentials alive in
the background for the rest of the run and cleans that up on exit, so
nothing prompts for it again mid-run. See "Sudo and unattended installs"
below.

## What the bootstrap currently does

1. Validates the environment:
   - not running as root
   - running on Arch Linux with `pacman` available
   - `sudo` is installed and the current user can authenticate with it
   - the expected repository files (`packages/base.txt`,
     `scripts/install/`) are present
2. Installs the packages listed in `packages/base.txt`, skipping any that
   are already installed.
3. Installs the packages listed in `packages/graphics.txt` (the Wayland
   foundation), the same way.

Nothing else. No compositor, no shell, no services are enabled, no
configs are deployed yet.

## Sudo and unattended installs

`bootstrap.sh` validates sudo once (`sudo -v`) and then keeps that
credential cache warm for the duration of the run instead of prompting
again - see `start_sudo_keepalive`/`stop_sudo_keepalive` in
`scripts/install/00-environment.sh`. It never touches `/etc/sudoers` and
never configures `NOPASSWD`; it only relies on sudo's normal, existing
credential cache, refreshed in the background and torn down on exit
(including on Ctrl+C or a failure) via a trap in `bootstrap.sh`.

Package installs use `pacman -Syu --needed --noconfirm <packages>` so a
validated run does not stop for a per-package "Proceed with
installation?" prompt. `--noconfirm` only skips that confirmation - it
does not relax signature checking, does not ignore package conflicts,
and does not touch `pacman.conf`. Any real pacman failure (conflicts, bad
signatures, corrupted packages, failed downloads) still aborts the
bootstrap with a non-zero exit code.

## Pacman / update policy

Arch Linux is a rolling release; syncing the package database without
upgrading the rest of the system (`pacman -Sy` without `-u`) risks a
partial upgrade. When `bootstrap.sh` needs to install missing packages
from a manifest, it does so with `pacman -Syu --needed --noconfirm
<packages>` - a full sync-and-upgrade together with the install - never a
bare `-Sy`.

If every package in a manifest is already installed, `bootstrap.sh` does
not touch pacman at all for that manifest. It is not a replacement for
routine system maintenance; running `sudo pacman -Syu` yourself remains
your responsibility.

## Graphics / Wayland foundation (phase 2)

`packages/graphics.txt` installs the layer between the kernel's DRM/KMS
and the future compositor: Mesa, the Wayland core protocol, and
XWayland. See `docs/ARCHITECTURE.md` for the full intended stack.

Deliberately out of scope for this phase:

- no compositor (Hyprland) or shell (Quickshell) yet
- no Wayland-related environment variables (`QT_QPA_PLATFORM`,
  `MOZ_ENABLE_WAYLAND`, `SDL_VIDEODRIVER`, `WLR_*`, ...) are set globally
  - only add one once it is concretely required, not by default
- no display manager (SDDM/GDM/LightDM) - login/session start is a
  later decision
- XWayland is installed as a compatibility fallback for X11-only
  applications; native Wayland stays the preferred path
- no Vulkan, lib32/multilib, or GPU-vendor-specific packages
  (`xf86-video-intel`, proprietary NVIDIA, ...) - driver choice is a
  hardware-specific decision, not part of the generic package list
- the current development VM is VirtualBox; VirtualBox Guest
  Additions/integration are a separate dev-VM concern and are not part
  of this repository's generic package list

## Repository structure

```
.
├── README.md
├── BOOTSTRAPPER.md
├── bootstrap.sh
├── docs/
├── packages/
│   ├── base.txt         # phase 1 base packages
│   └── graphics.txt     # phase 2 graphics/Wayland foundation packages
├── config/
├── systemd/
├── scripts/
│   ├── install/         # bootstrap modules, sourced by bootstrap.sh
│   └── helpers/         # shared shell helpers (logging, ...)
└── hardware/
```
