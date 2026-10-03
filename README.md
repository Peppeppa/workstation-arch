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

Ansible is now the primary provisioner (initial deployment only - runtime
changes such as theme switching go through user-level helpers, never
`bootstrap.sh`). `theme` (theme engine, `~/.local/bin/theme`), `base`,
`graphics`, `hyprland`,
`desktop` (polkit/portals/clipboard/screenshots/notifications/
brightness), `audio` (PipeWire/WirePlumber), `network` (NetworkManager +
WireGuard tooling), `quickshell` (Core Desktop v1 - top bar + app
launcher, see below), `apps` (end-user applications), `virtualization`
(VirtualBox), and `gaming` (Steam/Lutris) are implemented, aiming at a
minimal but genuinely usable daily-driver desktop. `quickshell` now owns
the app launcher, notifications and the system tray too (fuzzel and
mako are gone), plus a dark/light theme switcher next to the clock.
Bluetooth: BlueZ plus a bar icon whose popup powers the adapter, scans,
pairs (in-popup PIN/passkey dialogs), connects and forgets devices.
Clicking the network label opens the Connectivity Center (Wi-Fi with
password entry and QR sharing, Bluetooth, NetworkManager VPN/WireGuard);
right-clicking the volume opens device selection/volume/mute; the
battery (or, without one, a profile icon) opens power profiles.
`mainMod+V` shows the clipboard history (cliphist); wallpapers come from
the active theme's `backgrounds/` and are picked in the theme dialog.
Laptop lid: lock, then suspend. Bar widgets can be rearranged by dragging them (also between left/center/right); the order is kept in `~/.config/workstation/bar-layout.json` (`qs ipc call bar resetLayout` restores the default). There is no display manager. Feature
freeze: next is visual polish (RICE v1). See
`AGENTS.md` for exactly what is real-VM-tested versus only structurally
verified so far.

Optional capabilities (screenshots + OCR, power menu, lock/idle, notifications, tray, bluetooth,
power profiles, audio popup, connectivity center, clipboard history, wallpaper) are toggleable
per host via a flat `<name>_enabled` variable in `group_vars/all.yml`
(overridable in `host_vars/<hostname>.yml`) - see
`docs/feature-architecture.md` for the full model. Disabling a feature
never deletes already-installed packages or personal data.

Note: `base` enables and starts `sshd` by default (needed for remote
access/administration on `laptop`/`workstation`, see `AGENTS.md` Runtime
Ownership) - every machine provisioned by this repository listens for
SSH after `./bootstrap.sh`, not just an opt-in subset.

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
./bootstrap.sh --tags desktop
./bootstrap.sh --tags audio
./bootstrap.sh --tags network
./bootstrap.sh --tags quickshell
./bootstrap.sh --tags apps
./bootstrap.sh --tags virtualization
./bootstrap.sh --tags gaming
```

`bootstrap.sh` forwards any extra arguments straight to
`ansible-playbook`, so both forms work the same way. `--tags gaming`
requires `gaming_gpu_vulkan_packages` to be set for the current host
first - see the `gaming` row below.

## Roles

| Role             | Tag             | What it does                                                          |
|------------------|-----------------|------------------------------------------------------------------------|
| `base`           | `base`          | Minimal Arch base packages (git, openssh, curl, rsync); enables/starts `sshd`; German (`de-latin1`) virtual console keymap; `en_US.UTF-8`/`de_DE.UTF-8` locales generated |
| `graphics`       | `graphics`      | Wayland/Mesa/XWayland foundation - no compositor yet                   |
| `hyprland`       | `hyprland`      | Hyprland session: compositor, Ghostty (terminal)                       |
| `desktop`        | `desktop`       | Polkit agent, XDG portals, clipboard, screenshots, notifications, brightness |
| `audio`          | `audio`         | PipeWire + WirePlumber (no PulseAudio)                                 |
| `network`        | `network`       | NetworkManager (enabled service) + WireGuard tooling (VPN foundation)  |
| `bluetooth`      | `bluetooth`     | BlueZ (`bluetooth.service`, runs only with an adapter)                 |
| `power`          | `power`         | Lid switch -> suspend (logind drop-in); power-profiles-daemon (`power_profiles_enabled`) |
| `quickshell`     | `quickshell`    | Quickshell (official `extra` package): top bar, launcher, notifications, tray, popups (power, audio, connectivity, Bluetooth), clipboard history, wallpaper |
| `apps`           | `apps`          | End-user applications (browser, mail, file managers, editor, PDF, ...); default PDF/PNG handlers set to zathura/imv |
| `virtualization` | `virtualization`| VirtualBox host (kernel modules via DKMS, `vboxusers` group)           |
| `gaming`         | `gaming`        | Steam, Lutris, gamemode - needs a host-specific GPU driver var first   |

Further roles (`session`, `hardware`, ...) will be added
the same way as the desktop is built out - see `docs/ARCHITECTURE.md`
for the intended stack.

## Hyprland session (manual start, no display manager)

Hyprland is set up to start and stop by hand - it deliberately does
**not** install a display manager and does not add any
`.bash_profile`/`exec Hyprland` autostart hack. Hyprland's own session
lifecycle (`hl.on("hyprland.start", ...)`) now also starts Quickshell
(`roles/quickshell`), which owns the top bar (workspaces/clock/network/
volume/battery) and the app launcher (`mainMod+Space` - see below);
Quickshell also shows notifications (toasts top-right; mako is
retired) - see `AGENTS.md`. After provisioning and a reboot:

```sh
reboot
# then, after logging in on a plain TTY:
Hyprland
```

The deployed config (`~/.config/hypr/hyprland.lua` - current Hyprland
reads Lua, not the older `hyprland.conf` format) disables animations/
blur/shadow (this project prioritizes responsiveness over decoration -
see `docs/ARCHITECTURE.md`), sets a German (`de`) keyboard layout for
the Wayland session (separate from the virtual console keymap and
system locale set by `base` - see `AGENTS.md`), and binds:

| Keybind                | Action                                      |
|-------------------------|---------------------------------------------|
| `Super + Return`         | open a terminal (Ghostty)                    |
| `Super + Space`          | toggle the Quickshell app launcher            |
| `Super + Q`              | close the focused window                     |
| `Super + [1-9]`          | switch to workspace 1-9                      |
| `Super + Shift + [1-9]`  | move the focused window to workspace 1-9     |
| `Super` + arrow keys     | move keyboard focus                          |
| `Super` + left/right click drag | move / resize a floating window       |
| `Super + X`              | smart screenshot: drag a region or click a window -> PNG file + clipboard |
| `Super + Shift + X`      | OCR: select region/window -> recognized text (de+en) to clipboard, no PNG kept |
| `Super + L`              | lock now (hyprlock)                          |
| `Super + Escape`         | power menu: Lock (preselected) / Suspend / (Hibernate) / Logout / Reboot / Shutdown - runs immediately on Enter/click, no confirmation |
| `Super + Shift + E`      | exit Hyprland (back to TTY)                  |

Notifications: toasts top-right (Quickshell). Click/x closes; normal
ones expire after ~5 s (or the sender's timeout, paused on hover),
critical ones stay until closed. No history, nothing stored.

System font: FiraCode Nerd Font (UI, monospace, terminal, lockscreen,
GTK; Qt via fontconfig) - names in `group_vars/all.yml`.

Idle (hypridle): 5 min -> lock, 10 min -> displays off, back on at any
input; the session is always locked before suspend/hibernate.

System tray: StatusNotifierItem/AppIndicator icons of running apps
appear at the left of the bar's status zone (left click activate, middle
click secondary action, right click menu, wheel scroll); hidden when
there are none.

Coffee icon left of the bar clock (hidden until hovered; click to
toggle): pauses the *automatic* idle lock/display-off while on (icon
stays visible). Not persistent - off again after any Quickshell or
session restart. Super+L, power menu Lock and lock-before-suspend keep
working while it's on.

Screenshots land in `~/Pictures/Screenshots/` (XDG Pictures dir). OCR
runs tesseract fully locally (no network), only on the keypress - zero
idle cost, like the screenshot feature itself.

These are not the final Quickshell UX - just a genuinely usable set of
defaults in the meantime.

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
│   ├── hyprland/          # Hyprland session, terminal, temporary launcher
│   ├── desktop/           # polkit, portals, clipboard, screenshots, notifications, brightness
│   ├── audio/             # PipeWire + WirePlumber
│   ├── network/           # NetworkManager + WireGuard tooling
│   ├── apps/              # end-user applications
│   ├── virtualization/    # VirtualBox host
│   └── gaming/            # Steam, Lutris, gamemode
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
