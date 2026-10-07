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

Personal configuration comes from a **separate private repository**
(`Peppeppa/dotfiles-provision`), reached only after a credential provider
(the Bitwarden desktop SSH agent) works - see "Private handover" below.
Its contents never come into this repository; only its name and clone
path are known here.

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
Laptop lid: lock, then suspend. Bar widgets can be rearranged by dragging them (also between left/center/right); the order is kept in `~/.config/workstation/bar-layout.json` (`qs ipc call bar resetLayout` restores the default). The bar background is `solid` or `transparent` - right click on free bar space flips it (or `qs ipc call bar setBackground transparent`), kept in the same file. Bar widgets show no hover tooltips. Login: Ly on tty2 (see below). Feature
freeze: next is visual polish (RICE v1). See
`AGENTS.md` for exactly what is real-VM-tested versus only structurally
verified so far.

Optional capabilities (screenshots + OCR, power menu, lock/idle, notifications, tray, bluetooth,
power profiles, audio popup, connectivity center, clipboard history, wallpaper) are toggleable
per host via a flat `<name>_enabled` variable in `group_vars/all.yml`
(overridable in `host_vars/<hostname>.yml`) - see
`docs/feature-architecture.md` for the full model. Disabling a feature
never deletes already-installed packages or personal data.

Note: the SSH server is opt-in per host (`ssh_server_enabled`, default
`false`; on the test laptop and arch-dev `true`) and always key-only -
see "Firewall and SSH". The SSH client works everywhere.

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

### Private handover

After a successful real run (not `--check`, `--syntax-check`, `--list-*`;
skip with `WORKSTATION_PRIVATE=0 ./bootstrap.sh`) `bootstrap.sh` runs
`scripts/private-handover.sh`:

1. **GitHub over SSH via Bitwarden**: the agent socket
   `~/.bitwarden-ssh-agent.sock` exists, the agent lists a key, and
   `ssh -T git@github.com` authenticates (github.com's host keys are
   pinned by `roles/base`, `StrictHostKeyChecking=yes`). If not, it
   prints **one ACTION REQUIRED**: by hand in the Bitwarden app,
   self-hosted server URL on the login screen, log in + unlock, Settings
   -> Enable SSH agent, "Ask for authorization" Never (or click
   Authorize in each "Confirm SSH key usage" dialog), your GitHub key as
   an SSH key item. In a terminal the bootstrap then **waits** and goes
   on by itself once GitHub accepts the key (the local agent is checked
   every 3 s without any dialog; GitHub is only asked once the agent
   offers a key, after a rejection again 15 s later; Ctrl+C or 30 min
   stop it - re-run `./bootstrap.sh`). Without a terminal it exits 3.
   Nothing here unlocks Bitwarden, asks for its master password, reads
   the vault or exports a key.
2. **Clone or fast-forward** `~/repos/peppeppa/dotfiles-provision`. An
   existing clone is only fast-forwarded when it is a git checkout with
   the expected origin, on a branch, with a clean working tree - local
   changes, a divergence, a detached HEAD or a foreign directory stop the
   run with nothing changed (never reset/stash/discard).
3. Runs the private repo's `bootstrap.sh` (its exit code is the
   bootstrap's).

Bitwarden must be running for its agent to exist; this session runs no
XDG autostart, so its "start on login" option has no effect - open it
from the launcher.

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
| `base`           | `base`          | Minimal Arch base packages (git, openssh, curl, rsync); key-only sshd policy, sshd only with `ssh_server_enabled`; German (`de-latin1`) virtual console keymap; `en_US.UTF-8`/`de_DE.UTF-8` locales generated; a system `LANG` (`en_US.UTF-8`) only if none is set |
| `graphics`       | `graphics`      | Wayland/Mesa/XWayland foundation - no compositor yet                   |
| `hyprland`       | `hyprland`      | Hyprland session: compositor, Ghostty (terminal)                       |
| `desktop`        | `desktop`       | Polkit agent, XDG portals, clipboard, screenshots, notifications, brightness |
| `audio`          | `audio`         | PipeWire + WirePlumber (no PulseAudio)                                 |
| `network`        | `network`       | NetworkManager (enabled service) + WireGuard tooling (VPN foundation), `nm-connection-editor`, `python-dbus` (eduroam CAT installer); VPN plugins (WireGuard native, OpenVPN, OpenConnect, IPsec/IKEv2) + THWS VPN (openfortivpn + pinned AUR NM plugin, `fortinet_vpn_enabled`) - see "VPN types" |
| `packages`       | `packages`      | fzf + the AUR helper yay (pinned build) for OS menu -> Packages (`workstation-pkg`) - see "Packages" |
| `firewall`       | `firewall`      | nftables inbound firewall (own table, no daemon), no ICMP redirects, the helper behind Settings -> Firewall - see "Firewall and SSH" |
| `bluetooth`      | `bluetooth`     | BlueZ (`bluetooth.service`, runs only with an adapter)                 |
| `power`          | `power`         | Lid switch -> suspend (logind drop-in); power-profiles-daemon (`power_profiles_enabled`) |
| `quickshell`     | `quickshell`    | Quickshell (official `extra` package): top bar, launcher, notifications, tray, popups (power, audio, connectivity, Bluetooth), clipboard history, wallpaper |
| `apps`           | `apps`          | End-user applications (browser, mail, Nautilus + yazi as file managers, editor, PDF, Loupe, Disks, Anki, Planify; LocalSend/WebCord/IntelliJ via Flathub; WhatsApp and Zoom as Chromium web apps); default handlers: folders -> Nautilus, PDF -> zathura, PNG -> imv |
| `development`    | `development`   | gh, lazygit, JDK 25, Python + uv, Docker Engine + Compose + lazydocker (Docker never starts at boot - see "Docker"), the MariaDB client `mariadb-clients` (no server) |
| `shell`          | `shell`         | Starship, zoxide, fzf, eza, bat, tldr (tealdeer), bash-completion + one sourced shell integration file - see "Shell and Neovim" |
| `virtualization` | `virtualization`| VirtualBox host (kernel modules via DKMS, `vboxusers` group)           |
| `gaming`         | `gaming`        | Steam, Lutris, gamemode - needs a host-specific GPU driver var first   |
| `recovery`       | `recovery`      | Btrfs snapshots (snapper), recovery boot slots, `system-update`/`-snapshot`/`-rollback` (`recovery_enabled`) |

Further roles (`session`, `hardware`, ...) will be added
the same way as the desktop is built out - see `docs/ARCHITECTURE.md`
for the intended stack.

## Login and Hyprland session

Boot ends in **Ly** (official `ly` package, minimal TUI login) on tty2:
user + password -> the Hyprland session (the hyprland package's
`hyprland.desktop`, i.e. `start-hyprland`). Logging out of Hyprland
(`Super + Shift + E` or the power menu) returns to Ly. No autologin, no
`.bash_profile`/`exec Hyprland` hack. Feature `display_manager_enabled`
(`roles/display_manager`).

Recovery: tty1 (`Ctrl+Alt+F1`) keeps a normal console login, ttys 3-6
get one on demand, sshd stays enabled where `ssh_server_enabled` - and from a console login
`start-hyprland` still starts the same session by hand. If Ly itself
misbehaves: `sudo systemctl disable --now ly@tty2` (or
`display_manager_enabled: false` + `./bootstrap.sh`).

Hyprland's own session
lifecycle (`hl.on("hyprland.start", ...)`) now also starts Quickshell
(`roles/quickshell`), which owns the top bar (workspaces/clock/network/
volume/battery) and the OS menu (`mainMod+Space` - see below);
Quickshell also shows notifications (toasts top-right; mako is
retired) - see `AGENTS.md`. After provisioning and a reboot:

```sh
reboot
# Ly appears on tty2 - log in. Manual fallback from a console login:
start-hyprland
```

The deployed config (`~/.config/hypr/hyprland.lua` - current Hyprland
reads Lua, not the older `hyprland.conf` format) disables animations/
blur/shadow (this project prioritizes responsiveness over decoration -
see `docs/ARCHITECTURE.md`), sets a German (`de`) keyboard layout for
the Wayland session (separate from the virtual console keymap and
system locale set by `base` - see `AGENTS.md`), and binds:

| Keybind | Action |
|---|---|
| `Super + Space` | OS menu - just type to search apps and menu entries (Appearance, Network, Firewall, System, ...), Enter runs the best match; Up/Down or Ctrl+J/Ctrl+K move; Escape clears the search, then closes |
| `Super + T` / `Super + Return` | terminal (Ghostty) |
| `Super + B` / `Super + Shift + B` | Chromium / Bitwarden |
| `Super + D` | Neovim in a terminal |
| `Super + E` / `Super + F` | Thunderbird / Nautilus |
| `Super + G` / `Super + W` | WhatsApp / Obsidian (focus if already open) |
| `Super + V` | clipboard history |
| `Super + N` | scratchpad: four quick notes (also the bar's note icon) |
| `Super + F1` | keybinding cheatsheet (`hypr-cheatsheet`) |
| `Super + H/J/K/L` (or arrows) | focus left/down/up/right |
| `Super + Shift + H/J/K/L` | move the window |
| `Super + Alt + H/J/K/L` | resize the window (100 px) |
| `Super + Q` | close the focused window |
| `Super + Shift + F` / `Shift + G` / `Shift + T` | fullscreen / floating toggle / split toggle |
| `Super + [1-9]` / `Super + Shift + [1-9]` | switch to / move the window to workspace 1-9 |
| `Super + S` / `Super + Shift + S` | toggle the scratchpad / move the window there |
| `Super` + left/right click drag | move / resize a floating window |
| `Super + X` | smart screenshot: drag a region or click a window -> PNG file + clipboard |
| `Super + Shift + X` | screenshot of the whole focused monitor |
| `Super + Ctrl + X` | OCR: select region/window -> recognized text (de+en) to clipboard, no PNG kept |
| `Super + Delete` | lock now (hyprlock) |
| `Super + Escape` | power menu: Lock (preselected) / Suspend / (Hibernate - only on a host with `hibernate_enabled` and logind `CanHibernate`, see `docs/feature-architecture.md` "Hibernate") / Logout / Reboot / Shutdown - runs immediately on Enter/click, no confirmation |
| `Super + Shift + E` | exit Hyprland (back to Ly / the TTY) |

Caps Lock is a second Ctrl (`hyprland_keyboard_options: ctrl:nocaps`). The
full, generated list is `Super + F1`.

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
session restart. Super+Delete, power menu Lock and lock-before-suspend keep
working while it's on.

Screenshots land in `~/Pictures/Screenshots/` (XDG Pictures dir). OCR
runs tesseract fully locally (no network), only on the keypress - zero
idle cost, like the screenshot feature itself.

These are not the final Quickshell UX - just a genuinely usable set of
defaults in the meantime.

## Troubleshooting

0. `repo-healthcheck` - PASS/WARN/FAIL for the system's invariants (one
   session, one Quickshell under Hyprland, session helpers, failed units,
   no timers of ours, one owner per responsibility, audio stack, network,
   bar layout / theme state / theme outputs valid, no coredumps or QML
   exceptions this session, Hyprland config). Ends with `HEALTHY` (exit 0)
   or `UNHEALTHY: N checks failed` (exit 1); WARN never fails. Read-only,
   about half a second - run it first, then `repo-diagnose` for the why.
1. `repo-diagnose` - a compact health snapshot (session, shell, network,
   Bluetooth, audio, power, desktop, failed units, duplicate processes,
   recent errors, coredumps). Problems are marked `!!` and summarized as
   `issues:` at the end; short enough to paste into a bug report.
2. Look at the component it flags.
3. `repo-diagnose --full` - more detail (unit states, allowlisted session
   environment, monitors, bounded journal excerpts per service, hardware
   capabilities). Still shareable: secrets are never collected and every
   line is redacted (PSKs/passwords/keys/tokens, command-line arguments).
4. Targeted logs (journald is the only log store):
   - `journalctl --user -t quickshell` - shell/QML: our own failures are
     one line each, `[network] ...`, `[bluetooth] ...`, `[theme] ...`,
     `[wallpaper] ...`, `[brightness] ...`, `[power] ...`, `[osmenu] ...`,
     `[appearance] ...`, `[bar] ...`
   - `journalctl --user -t hypridle` (errors only; hyprlock too),
     `journalctl --user -t app-launch -t systemd-run` (OS menu hand-offs)
   - `journalctl -u NetworkManager`, `-u bluetooth`, `-u power-profiles-daemon`,
     `journalctl --user -u pipewire -u wireplumber`
   - Hyprland: `~/.local/state/ly-session.log` (stdout of the session) and
     `$XDG_RUNTIME_DIR/hypr/<instance>/hyprland.log` (current session only)
   - bootstrap: the `fatal:` task (role, file:line) in its own output;
     rerun one role with `./bootstrap.sh --tags <role> -v`

Logout (power menu, `mainMod+SHIFT+E`) and the power menu's Reboot/Shutdown
end the session in order: Hyprland's shutdown hook stops its session
helpers and the portals while the display still exists (`session-stop`,
roles/hyprland) - no coredumps, no "failed" portal units. A session ended
from outside instead (`sudo reboot` from a TTY/SSH, `loginctl
terminate-session`) SIGTERMs everything at once: then the helpers may
still dump core, and `repo-diagnose` lists those as "before this session".
hyprlock logs ~100 debug lines per lock (`-t hypridle`): its `-q` also
drops real errors, so it stays verbose on purpose.

Checks of the repository itself (no live system needed): `tests/run.sh`.

## Updates, snapshots and rollback (hosts with `recovery_enabled`)

On a host with `recovery_enabled: true` (Btrfs + systemd-boot + UKI, see
`docs/recovery-design.md`) update with `system-update` instead of a bare
`sudo pacman -Syu`: it checks free space/ESP/battery and health first,
keeps the running system as the boot entry "Recovery: before the last
update", runs `pacman -Syu`, then checks the boot image and health again.
It never rolls back by itself.

```sh
system-update                               # the update transaction
sudo system-snapshot --known-good "label"   # after a verified good state (needs a fresh boot)
sudo system-snapshot --list                 # snapshots + recovery slots
sudo system-rollback before-update          # permanent, from the next boot; /home stays
```

Automatic snapshots: **every** package transaction (`pacman -S`, `-R`,
`-U`, a bare `pacman -Syu`, package tasks of a bootstrap) first takes ONE
snapshot of the system (a pacman hook), described `pacman: <packages>`.
`system-update` takes that snapshot itself (plus the boot entry) - still
one per update. Only the newest **3** automatic snapshots are kept; the
`known-good` snapshot (the protected baseline - a host without one gets a
single `baseline` snapshot after its first complete bootstrap) and your
`system-snapshot "label"` snapshots (snapper keeps the last 4) are never
touched by that cleanup. If a snapshot cannot be taken, pacman stops
instead of updating without one (once without:
`sudo sh -c 'echo manual > /run/workstation-recovery/skip-pre-snapshot'`).
A pre-transaction snapshot is a read-only recovery point: browse it under
`/.snapshots/<n>/snapshot`, or roll back to a boot slot as below.

If the system does not come up after an update: pick "Recovery: ..." in
the systemd-boot menu (it boots the saved system, `/home` is the normal
one), look around, then `sudo system-rollback <slot>` and reboot. The old
system is kept as `@broken-<date>` at the Btrfs top level until deleted
by hand.

## Packages (install / remove)

OS menu -> **Packages** -> Install / Remove -> Arch Packages | AUR Packages |
Flatpaks (or type e.g. `install aur`, `flatpak`) opens a terminal with an fzf
picker (`workstation-pkg`): type to search names and descriptions, Tab
selects several, Enter goes, Esc cancels (nothing happens). Then the normal
tool runs with its normal confirmation - nothing is `--noconfirm`:

| | Lists | Runs |
|---|---|---|
| Install Arch | the official repositories (`pacman -Ss`), installed ones hidden | `sudo pacman -S --needed` |
| Remove Arch | explicitly installed official packages (`pacman -Qqen`) | `sudo pacman -Rns` |
| Install AUR | the AUR, searched while you type (RPC, >= 2 characters) | `yay -S --aur` - shows the build files (PKGBUILD) first, builds as you, installs through sudo pacman |
| Remove AUR | explicitly installed foreign packages (`pacman -Qqem`; dependencies are not offered; ones this repository provisions are marked `[workstation baseline]`) | `sudo pacman -Rns` |
| Install Flatpak | applications of the configured remotes (Flathub), no runtimes, installed ones hidden | `flatpak install <remote> <id>` |
| Remove Flatpak | installed applications (no runtimes) | `flatpak uninstall` (unused runtimes stay) |

Every pacman transaction takes the automatic recovery snapshot first (see
"Updates, snapshots and rollback"). What you install here is yours, not part
of the provisioned baseline; a baseline package you remove comes back with
the next `./bootstrap.sh`. The AUR helper (`yay`) is built once by bootstrap
from a pinned AUR commit and never runs by itself (no update timer).

## Scratchpad

`Super + N` (or the note icon in the bar) opens a small note window at the
top right: four fixed plain-text notes, Enter = new line, no wrapping (long
lines scroll sideways). The dots at the bottom or `Alt + 1..4` switch notes;
`-`/`+` (or `Ctrl + -`/`Ctrl + +`) change only the notes' font size (the
desktop text size is the default; kept). Escape, `Super + N`, `Super + Q`
or a click elsewhere close it. Text saves itself (shortly after typing and
on every switch/close) to plain files:
`~/.local/share/workstation/scratchpad/1.txt` ... `4.txt` (last note + font
size: `~/.config/workstation/scratchpad.json`). Edits made to those files
from outside while the desktop runs are not picked up until the next
Quickshell start.

## Docker (on demand)

Docker is installed (`roles/development`) but never runs by itself - no
daemon, no socket, no containerd at boot. Your user is in the `docker`
group (after the next login), so `docker` works without sudo while the
daemon runs.

```sh
sudo systemctl start docker                                        # start (socket, daemon, containerd)
docker compose up -d                                               # ... work ...
sudo systemctl stop docker.socket docker.service containerd.service   # stop everything again
systemctl is-active docker docker.socket containerd                 # check: inactive x3
```

Stop the socket too: while `docker.socket` listens, the next `docker`
call (or an IDE probing it) starts the daemon again. Containers, images,
volumes and databases (e.g. a MySQL container for a course) are yours -
the repository creates none.

## Firewall and SSH

Inbound traffic is dropped unless it answers something this machine
started, or is one of: LocalSend (discovery + transfers), DHCP, the ICMP
IPv4/IPv6 need, SSH (only on a host with `ssh_server_enabled`), or one of
**your sharing rules**. Outbound is not filtered - browsing, VPN clients
(WireGuard/OpenVPN via NetworkManager), Docker pulls need no rule.
Mechanism: one nftables table (`inet workstation`) loaded at boot by
`workstation-firewall.service`; nothing keeps running.

**Share a service with colleagues on the LAN**: OS menu -> Settings ->
Firewall -> **Hinzufügen** (e.g. `Test Database` / `1234` / `TCP`). A new
rule starts **disabled** - nothing opens until you click **Aktivieren**;
then colleagues can connect to `<your-ip>:1234`. **Deaktivieren** closes it again
immediately (the row stays), **Aktivieren** reopens it, **×** closes and
deletes the rule. Rules survive reboots.

- A rule opens the port in the firewall - it does not start or stop your
  service. Rule on + nothing listening = connection refused; rule off +
  service running = it works on this machine, the LAN is blocked.
- Docker: `docker run -p 1234:5432 ...` is LAN-blocked until a rule for
  the **host** port (1234) exists; `-p 127.0.0.1:1234:5432` stays local
  regardless. Container networking and outbound traffic are not affected.
- Bind dev servers to `127.0.0.1` anyway when the LAN never needs them.

CLI (what the window runs):
`pkexec /usr/local/libexec/workstation/firewall-rules list` (also `add
<label> <port> <tcp|udp>`, `enable|disable|remove <port> <tcp|udp>`);
the full ruleset: `sudo nft list table inet workstation`.

SSH: inbound logins are public-key only on every host (no passwords, no
keyboard-interactive). The server itself runs only where a host sets
`ssh_server_enabled: true` (`host_vars/<host>.yml`).

## VPN types

All VPNs are NetworkManager connections - create or import them in OS menu
-> Settings -> Network (`+`, or "Import a saved VPN configuration"), switch
them in the bar's network popup. None connects on its own.

| Type | Plugin (official repos unless noted) |
|---|---|
| WireGuard | native in NetworkManager (`wireguard-tools`) |
| OpenVPN | `networkmanager-openvpn` |
| OpenConnect (Cisco AnyConnect, GlobalProtect, Pulse, ...) | `networkmanager-openconnect` |
| IPsec/IKEv2 | `networkmanager-strongswan` (NM starts `charon-nm` per connection) |
| Fortinet SSL-VPN | `networkmanager-fortisslvpn` (pinned AUR build) - THWS, see below |

Mullvad (or another provider) needs no app: download its WireGuard
configuration, then `nmcli connection import type wireguard file
<file>.conf` and `nmcli connection modify <name> connection.autoconnect
no` (NetworkManager imports WireGuard files with autoconnect on).

## Uni VPN (THWS)

The THWS student VPN is a FortiGate SSL-VPN (`vpn.thws.de`, K-number +
password; the access must be requested once in the Studierendenportal).
On hosts with `fortinet_vpn_enabled` (laptop, workstation) bootstrap
installs openfortivpn and its NetworkManager plugin; you then **switch
it on/off only in the bar's network popup** (VPN section) like any other
VPN.

Create the profile once: OS menu -> Settings -> Network -> `+` ->
**Fortinet SSLVPN**:
- Gateway `vpn.thws.de`, user name = your K-number
- password: the small icon in the field -> **Store the password for all
  users** (this desktop has no secret agent - "only for this user" or "ask
  every time" can never connect from the popup)
- IPv4 Settings -> Routes -> **Use this connection only for resources on
  its network** (split tunnel: the university pushes the routes of its
  services; without this NetworkManager also sends all internet traffic
  into the tunnel, which the VPN does not forward - no internet while
  connected)

**Library / licensed resources**: the VPN carries only what the THWS
gateway routes - its services and some licensed ones (e.g. DBIS,
beck-online: recognized as THWS). The big publisher platforms (SpringerLink,
IEEE Xplore, ScienceDirect, Wiley) are NOT routed by the gateway (measured:
it drops anything outside its route list, so a full tunnel cannot work
either); the library's own way for them is its **proxy** - "Externer
Zugang" on bibliothek.thws.de (separate proxy credentials). Chromium is
provisioned with the library's PAC (`https://www.bibliothek.thws.de/proxy.pac`,
managed policy - THWS keeps the domain list): only those publisher domains
go through the library proxy, everything else stays direct, with or
without the VPN. On the first proxied page Chromium asks for the proxy
login - type it there; if you let Chromium save it, its password store is
encrypted with a key in gnome-keyring (Secret Service).

## Chromium

Managed policy `/etc/chromium/policies/managed/workstation.json`
(`roles/apps`, see `chrome://policy`): the library PAC above and six
extensions Chromium installs and updates from the Chrome Web Store itself -
AdBlock, Bitwarden, Custom New Tab, Dark Reader, Vimium, uBlock Origin
Lite (installed automatically; can be disabled, not removed).

While a VPN is up the bar's network icon is in the accent color and the
popup shows "via VPN" top right.

Your credentials stay in NetworkManager's root-only system profile -
never in this repository. The plugin (`networkmanager-fortisslvpn`) is the
one AUR package here, built from a pinned commit (`roles/network`).

## Themes from repositories

Settings -> Appearance -> Theme -> **Import**: paste an Omarchy theme
repository URL, choose Dark or Light, Add. The theme is cloned (pinned to
its current commit), converted to a workstation theme - only colors,
Neovim colorscheme, btop theme and wallpapers are taken, nothing from the
repository runs - and appears in the theme lists. It is also added to
`themes/sources.yml`; commit that file to get the theme on the next
installation (bootstrap installs exactly the pinned commits). Wallpapers
stay in `~/.local/share/workstation/themes/sources/`, not in this
repository. Remove works for imported themes that are not selected. Details:
`docs/DESIGN_SYSTEM.md` "Theme sources".

## Shell and Neovim

`roles/shell` installs the tools and deploys
`~/.local/share/workstation/shell/{bashrc,starship.toml}`; one line in
`~/.bashrc` sources the first (added only while `~/.bashrc` is a plain
file - a dotfiles symlink is left alone; add the line there yourself:
`[[ -r ~/.local/share/workstation/shell/bashrc ]] && . ~/.local/share/workstation/shell/bashrc`).
It only wires the tools: Starship prompt (your `~/.config/starship.toml`
wins over the default), `z`/`zi` (zoxide - or another name via zoxide's
own `--cmd`: set `WORKSTATION_ZOXIDE_CMD=cd` before that line, as the
private dotfiles do), Ctrl+R / Ctrl+T / Alt+C (fzf), `BAT_THEME=ansi`
unless you set one; bash-completion is installed (Arch's
`/etc/bash.bashrc` loads it). Aliases and the rest of your shell
config are yours (dotfiles). `tldr --update` once fetches the pages.

Neovim: where no `~/.config/nvim` exists, provisioning creates the
LazyVim starter once (then never touches it); plugins install at the
first `nvim` start. Its `lua/plugins/workstation-theme.lua` makes Neovim
use the active workstation theme's own Neovim port (exact theme, not just
dark/light - table in `docs/DESIGN_SYSTEM.md`), and a theme switch
recolors running Neovims too. Bring your own config (dotfiles) any time -
keep that one file to stay themed. `lua/config/keymaps.lua` is the one
file workstation-arch keeps managed (deployed on every bootstrap): Space as
leader, `<leader>pv` explorer, visual `J`/`K` move lines, centered
`<C-d>`/`<C-u>`/`n`/`N`, `<leader>p` paste keeping the yank, `<leader>y`/`Y`
system clipboard, `jk` leaves insert, `<Esc>` saves, `<leader>x` chmod +x,
visual `<leader>c` comments with `#`, `<C-h/j/k/l>` windows, `<C-c>`/`<C-v>`
system clipboard. Personal additions go into another file under `lua/`.

SSH client: `~/.ssh/config` gets one managed block (at its end - your own
entries above it win) that points every host at the Bitwarden SSH agent:
`Host *` / `IdentityAgent ~/.bitwarden-ssh-agent.sock`. Enable the agent in
Bitwarden desktop (Settings -> SSH agent) and keep it unlocked; without it
ssh just finds no agent. No key is ever stored here.

## Zoom and screen sharing

Zoom is its **web client** in its own Chromium window (launcher entry
"Zoom", `app.zoom.us`). The native Zoom app is not installed: on Hyprland
its share toolbar ignores the mouse (XWayland override-redirect windows -
Stop share and mute stop reacting from the second share on), while the
web client shares reliably and is faster. Screen sharing in Zoom (web),
Chromium and WebCord goes through the portal: choose a monitor, a window
or a region in Hyprland's picker. Stop sharing in the app; the capture
ends with it. Remote control is not available on Hyprland (no
RemoteDesktop portal).

WebCord asks once per permission (microphone, camera) and remembers the
answer in its own settings (`~/.var/app/io.github.spacingbat3.webcord/
config/WebCord/config.json`, `privacy.permissions`; `false` = denied):
change it in WebCord's settings (Privacy -> Permissions).

## eduroam

Enrollment uses the university's official CAT installer (THWS: download
`eduroam-linux-THW.py` from cat.eduroam.org), never stored in this
repository:

```sh
python3 ~/Downloads/eduroam-linux-THW.py   # in a terminal: username + password are asked there
```

It creates the NetworkManager profiles `eduroam` and `THWS` (CA bundle in
`~/.config/cat_installer/ca.pem`, the RADIUS server names checked via
`domain-match`, anonymous outer identity). It marks the password
"agent-owned" - kept by a secret agent such as nm-applet, which this
desktop deliberately does not run - so NetworkManager drops it. Store it
once, system-owned (root-only keyfile, like every Wi-Fi password here):

```sh
sudo nmcli connection modify eduroam 802-1x.password-flags 0
sudo nmcli connection modify THWS 802-1x.password-flags 0
```

then Network popup -> Connections... -> `eduroam` -> Wi-Fi Security ->
type the password -> Save; the same for `THWS`. Never put the password on
a command line.

## Text size and display scale

Main menu -> Appearance. **Text size** (9-18 px, default 11) is one
preference for the whole desktop: the shell, Ghostty (and Neovim in it)
and GTK apps follow at once (`theme text-size 14` does the same from a
terminal). **Display** scale (1x 1.25x 1.6x 2x 4x per output) applies
at once and is remembered in `~/.config/workstation/display-scale.lua`;
"Use the host default" returns to `hyprland_monitors`. **Change** opens
this host's `host_vars/<host>.yml` in Neovim for resolution/position -
run `./bootstrap.sh` after editing.

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
