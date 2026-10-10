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
| Remote access (SSH) | sshd (system service, `roles/base`) - only with host capability `ssh_server_enabled` (default false; laptop + arch-dev true), always key-only (`sshd_config.d/10-workstation-key-only.conf`) |
| Inbound packet filter | kernel nftables, table `inet workstation` only (`roles/firewall`), loaded once at boot by `workstation-firewall.service` (oneshot, no daemon) together with the port rules in one transaction; never `flush ruleset`, never Docker's tables |
| Firewall port rules (Settings -> Firewall: the five standard rules DHCP/DHCPv6/LocalSend x2/SSH + the user's) | the root helper `firewall-rules` (`/usr/local/libexec/workstation/`, via `pkexec` + polkit action `org.workstation.firewall.manage`); state `/var/lib/workstation/firewall/rules.json` (v2, the user's list; factory list when absent), kernel chain `repo_rules` + sets `share_tcp`/`share_udp`, written in one nft transaction - never Ansible, never reset by a bootstrap |
| Audio | PipeWire + WirePlumber |
| Bluetooth | BlueZ - `bluetoothd`, systemd system service (`roles/bluetooth`); UI via Quickshell's native Bluetooth module |
| Bluetooth pairing agent (`org.bluez.Agent1`) | `bluetooth-agent`, child of Quickshell, only while the user pairs (feature `bluetooth`) |
| Login (display manager) | Ly - `ly@tty2.service` (package unit + PAM), `roles/display_manager`, feature `display_manager_enabled`; starts the hyprland package's `hyprland.desktop` (`start-hyprland`); tty1 keeps its getty for recovery/manual start |
| Compositor / window manager | Hyprland |
| OS menu / app launcher | Quickshell (`osmenu/`, `qs ipc call osmenu toggle` on `mainMod+Space`; type-to-search over its own entries + apps; Applications = the former launcher - fuzzel retired as of Core Desktop v1). Navigation only: Appearance/Network/Firewall and System (Update, Create Snapshot, Power) hand over to their owners |
| Hyprland keybindings, input, cheatsheet documents | `roles/hyprland` (`conf/binds.lua`, `conf/input.lua`, generated `~/.local/share/workstation/cheatsheets/hyprland.md`; the Neovim document `neovim.md` = `roles/apps`) - migrated once from the former dotfiles, no runtime link to them |
| Cheatsheet viewer | Quickshell `cheatsheet/` (top-level window, only while open; mainMod+T, IPC `cheatsheet`): Qt's Markdown rendering, Tab / j / k / search |
| Neovim keymaps + VimTeX spec + languages | `roles/apps` (`~/.config/nvim/lua/config/keymaps.lua`, `lua/plugins/vimtex.lua`, `lua/plugins/workstation-languages.lua` - the managed Neovim files - plus the language extras ADDED to `lazyvim.json`; servers/tools = Mason's, installed headless by the bootstrap (`nvim-install.lua`, missing only); plugins = lazy.nvim's, the rest of the config stays the user's) |
| SSH client agent | `~/.ssh/config` managed block (`roles/base`): `IdentityAgent ~/.bitwarden-ssh-agent.sock` - Bitwarden desktop's agent; no keys here |
| Appearance (theme/wallpaper/bar background/brightness/text size/display) | Quickshell `appearance/` window + shared `services/` models; theme state stays the `theme` helper's, bar background = BarLayout's setting, brightness = `brightnessctl` (backlight only) |
| Desktop text size (one preference: shell, Ghostty, GTK `text-scaling-factor`) | the `theme` helper (state `text-size`, `theme text-size <px>`); Quickshell derives sizes via `Fonts.px` |
| Display scale picked at runtime | `~/.config/workstation/display-scale.lua`, written only by Appearance (`services/DisplayModel.qml`), read by `monitors.lua`; mode/position/default scale stay `hyprland_monitors` (host_vars) |
| Night light (Day/Night) | `hyprsunset`, child of Quickshell only while Night is on (`NightLight.qml`, Visuals widget) |
| Timer / reminder | Quickshell `Countdown.qml` (Visuals widget) - a deadline + tick only while a timer runs |
| AC/battery power-profile policy (laptops) | Quickshell `PowerPolicy.qml` (feature `power_profiles`): AC = Performance, battery = remembered battery choice (`~/.config/workstation/power-battery-profile`) |
| Shell tool integration (prompt, zoxide, fzf hooks) | `~/.local/share/workstation/shell/bashrc` (`roles/shell`), sourced by one line in `~/.bashrc`; personal shell config (aliases, `~/.config/starship.toml`, ...) = dotfiles |
| Theme sources (Omarchy theme repositories) | manifest `themes/sources.yml` (repo); sources + compiled themes under `~/.local/share/workstation/themes/` written only by the `theme` helper (`import`/`remove` at runtime, `sync-sources` in provisioning); repositories are data, never executed |
| Neovim colorscheme | the active workstation theme (`theme` helper: `neovim.lua` + `neovim-current.lua`, `doautocmd User WorkstationTheme` to running Neovims); Neovim config itself = the user's (LazyVim starter created once) |
| NetworkManager secret agent | none on purpose (no nm-applet): secrets are system-owned (Quickshell popup, nm-connection-editor "for all users"); agent-owned profiles (eduroam CAT) get their password stored once - README "eduroam" |
| eduroam enrollment | the institution's GÉANT CAT installer (one-time, run by the user, needs `python-dbus`), result = NetworkManager profiles; never in this repo |
| Docker daemon | `docker.service`/`docker.socket`/`containerd.service` (systemd system units, `roles/development`) - never enabled; started/stopped by the user on demand |
| Browser extensions + THWS library proxy | Chromium managed policy `/etc/chromium/policies/managed/workstation.json` (`roles/apps`): ExtensionSettings (6 store extensions, Chromium installs/updates them) + ProxySettings `pac_script` = the library's own PAC (THWS owns the domain list); proxy login only in Chromium's dialog, never here |
| Other VPN protocols (WireGuard, OpenVPN, OpenConnect, IPsec/IKEv2) | NetworkManager natively / its official plugins (`roles/network`); each helper (openvpn, openconnect, charon-nm) is NM's child only while a connection is up; strongswan's own daemons stay disabled; no provider apps (Mullvad = a WireGuard config) |
| THWS VPN (FortiGate SSL-VPN) | NetworkManager + `networkmanager-fortisslvpn` (openfortivpn/pppd as the plugin's child, only while connected); switched only in the network popup's VPN section |
| Network administration (VPN profiles, static IP, DNS, 802.1X) | `nm-connection-editor` (roles/network), on demand from the OS menu - the bar's network popup is quick control only; no nm-applet |
| Notifications (`org.freedesktop.Notifications`) | Quickshell `NotificationServer` (`Notifications.qml`, feature `notifications`) - mako retired and uninstalled (its D-Bus activation file would otherwise start a second daemon) |
| Polkit authentication agent | hyprpolkitagent (session lifecycle, started once by Hyprland) |
| Screen sharing / screenshot portal | xdg-desktop-portal-hyprland |
| File chooser / settings portal | xdg-desktop-portal-gtk |
| Idle handling, lock-on-sleep (logind Lock/PrepareForSleep) | hypridle (session lifecycle, started once by Hyprland; feature `lock_idle`) |
| Screen locker | hyprlock (on demand only - spawned by hypridle on logind Lock, exits on unlock) |
| System tray host (`org.kde.StatusNotifierWatcher`) | Quickshell `SystemTray` (feature `tray`) |
| Shell presentation / integration | Quickshell (top bar, OS menu, Appearance - session lifecycle, started once by Hyprland, see `roles/quickshell`) |
| Power profiles | power-profiles-daemon (systemd system service, `roles/power`, feature `power_profiles`); switched over its D-Bus API from Quickshell |
| Lid switch -> suspend | systemd-logind (`roles/power` drop-in); lock before sleep: hypridle |
| Clipboard history watcher | `wl-paste --type text --watch cliphist store` (session lifecycle, started once by Hyprland; feature `clipboard_history`) |
| Bar layout (widget order/zones) + bar settings (background solid/transparent) | user runtime state `~/.config/workstation/bar-layout.json`, written only by the bar (drag & drop / `qs ipc call bar resetLayout` / `qs ipc call bar setBackground`); Ansible creates it once if missing |
| File manager (`org.freedesktop.FileManager1`, `inode/directory`) | Nautilus (`roles/apps`; D-Bus-activated, it activates localsearch on demand) - Thunar retired and uninstalled (its own FileManager1 activation file would compete) |
| Wallpaper | Quickshell background-layer surface (`Wallpaper.qml`, feature `wallpaper`); Hyprland's own default wallpaper off - no separate wallpaper daemon |
| Wi-Fi QR helper | `wifi-qr`, one-shot child of Quickshell, only when the user asks for a QR code (feature `connectivity`) |
| Captive portal login page | detection = NetworkManager's connectivity check; `PortalWatcher.qml` (Quickshell, on NM's `portal` once per portal) and the popup's Log in start `portal-login` (`~/.local/libexec/workstation/`): a Chromium window of its own profile, gone when closed (feature `connectivity`) |
| Session end (stop of the session helpers + Wayland-bound portal units before the compositor goes) | Hyprland's own lifecycle: `hl.on("hyprland.shutdown")` -> `~/.local/libexec/workstation/session-stop` (roles/hyprland) - the same owner that started them; the power menu's reboot/shutdown end the session through it first (`workstation_end_session`) |
| Health invariants (PASS/FAIL) | `repo-healthcheck` (`roles/diagnostics`, /usr/local/bin) - on demand only, read-only; details stay `repo-diagnose`'s |
| Diagnostics | `repo-diagnose [--full]` (`roles/diagnostics`, /usr/local/bin) - on demand only; logs stay in journald (Quickshell/hypridle output via `systemd-cat`, QML failures as `[component] ...` through `Log.qml`) - no log daemon, follower or timer |
| Pre-transaction snapshots (one per pacman transaction, newest 3 kept) | pacman hook `/etc/pacman.d/hooks/00-workstation-pre-snapshot.hook` -> `pre-transaction-snapshot` (`roles/recovery`, class `auto=pre-transaction`; system-update takes its own update's and makes the hook skip); baseline = the `known-good` slot (or one `baseline=yes` snapshot after a first complete bootstrap) |
| Package install/remove UI | OS menu -> Packages -> `workstation-pkg` (fzf in the terminal, `roles/packages`); pacman / yay (pinned AUR build) / flatpak do the work with their own confirmations |
| Network popup live metrics + speedtest | the popup itself, only while open: /sys counters (1 s), one `ping` run per 5 s to 1.1.1.1, `speedtest-cli` only on its icon's click |
| Scratchpad notes | Quickshell `scratchpad/` (top-level window, mainMod+S, bar icon); ONE file `~/Documents/.system/scratchpad.md` (watched, conflict copy on external change during typing); syncing = the Nextcloud client's `~/Documents` folder only, nothing of ours |
| System snapshots (snapper config `root`, cleanup) | snapper + `snapper-cleanup.timer` (the one allowed timer; `roles/recovery`, host capability `recovery_enabled`) - no timeline, no snap-pac |
| Update transaction / recovery slots / rollback | `system-update`, `system-snapshot`, `system-rollback` (`roles/recovery`, on demand, never run by Ansible); boot entries "Recovery: ..." in `/boot/loader/entries/workstation-recovery-*.conf` are written only by them |
| Pending-update check + bar update icon | `workstation-checkupdates` (`roles/recovery`, checkupdates on a private DB copy, as the user) run by Quickshell's `updates/Updates.qml` (bar start + 60-min Timer + dialog/after an update; host capability `recovery_enabled`) - official repositories only, never the system's sync DB |
| Updater dialog / Create Snapshot (OS menu -> System, bar icon) | Quickshell `updates/UpdaterDialog.qml` + `SnapshotDialog.qml`: ask only; the transaction stays `system-update` (terminal, transient unit `workstation-system-update`, `--ui`, `--no-snapshot` only after a failed snapshot + explicit Ja); a manual snapshot = `pkexec snapshot-create <label>` (polkit `org.workstation.snapshot.create`) -> `system-snapshot` |
| Public -> private handover (GitHub SSH checkpoint, private repo clone/update) | `./bootstrap-personal.sh` (phase 2, started by hand in the graphical session; never by `bootstrap.sh`, no autostart): preflight (git, stow, phase 1's Bitwarden SSH config + pinned github.com keys), then its helper `scripts/private-handover.sh`: Bitwarden agent socket + key + `ssh -T git@github.com` (host keys pinned by `roles/base`) or ONE ACTION REQUIRED (Bitwarden set up by hand) and exit 3 - no waiting; clone / fast-forward-only update of `~/repos/peppeppa/dotfiles-provision` through `scripts/git-sync.sh` (stops on local changes/divergence/detached/foreign - never reset); then its `bootstrap.sh`, which syncs its own list of further checkouts through the same helper (`WORKSTATION_GIT_SYNC`). Private contents never come into this repository |
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

## Colors / Design System

Binding for every Quickshell component (see `docs/DESIGN_SYSTEM.md`):

- Use the semantic roles of the `Colors` singleton (`Colors.background`,
  `Colors.foreground`, `Colors.accent`, ...). Never hardcode a color in
  a component or an app config - no hex literals, `Qt.rgba`, `Qt.darker`
  of a theme color, or `opacity` used to fake a muted color. Missing
  role -> add it to the contract (`roles/theme/defaults/main.yml`) and
  every `themes/*.yml`, never to one consumer.
- All desktop colors come from the active theme. A new theme is added
  ONLY as a new valid theme directory `themes/<id>/` (marker `dark` or
  `light`, `theme.yml`, `backgrounds/`) - never by listing theme ids or
  names in QML, Ansible or anywhere else. Theme directories contain data
  and assets only, no executable code.
- The `theme` helper (`roles/theme/templates/theme.j2`) is the only code
  that discovers, validates or renders themes; consumers include its
  output files (`colors.json`, `hyprland.lua`, `hyprlock.conf`) and
  reference roles only - nothing branches on dark/light or a theme name.
  The user's state (`~/.config/workstation/theme-state`) is never
  overwritten by provisioning.
- Ansible = initial deployment / provisioning only. Runtime state and
  runtime switching (themes now, and any future interactive feature)
  belong to user-level helpers and native runtime interfaces (IPC,
  `hyprctl`, GSettings, signals) - never `bootstrap.sh`, a playbook,
  sudo or re-provisioning. Ansible may initialise a missing runtime
  state but must not manage or reset it.
- Theming stays declarative: no daemon, timer, polling, or file watcher.
- Fonts likewise: `font.family: Fonts.family` (icons: `Fonts.icons`),
  never a font name in a component. Font names live only in
  `group_vars/all.yml` `desktop_*_font_family` (roles: ui, shell,
  monospace, icon - see `docs/DESIGN_SYSTEM.md`).

## Feature Architecture

Everything above this point (Hyprland, the Quickshell process/core bar/
launcher, NetworkManager, PipeWire/WirePlumber, UPower, hyprpolkitagent,
the portal stack, base provisioning) is **Core** - never optional, never
behind a flag.

Optional capabilities layered on top (screenshots, gaming, and - later -
things like clipboard history, power menu, lock/idle, tray, Bluetooth
UI) are **Features**: one flat `<name>_enabled` boolean in
`group_vars/all.yml` (optionally overridden per host in
`host_vars/<hostname>.yml`) is the single source of truth for whether
each is on, gating that feature's own packages/config/binds wherever
they already live via `when:`/`{% if %}` - generalizing the pattern
`gaming_enabled` already established. `<name>_enabled: false` is always
safe: it stops the feature from being used but never removes already-
installed packages or deletes user data (see "Disable vs. Purge").

The central color system (Quickshell `Colors` singleton) is Core
presentation architecture, not a Feature - never put it behind a flag.
A later theme switcher may be a Feature on top of it.

This is deliberately *not* a plugin framework or a generic feature
engine - no dynamic loading, no new config DSL, no metadata schema. See
`docs/feature-architecture.md` for the full model: Core vs. Feature,
the Feature Contract, feature categories (provisioning-only / Hyprland
integration / Quickshell UI / background service / privileged), the
security rules every feature must follow, Disable-vs-Purge semantics,
and the step-by-step for adding a new one. Read it before adding any
new optional capability - don't re-derive this from scratch or build a
parallel mechanism.

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
exit code; after a successful real run it prints the phase-2 next steps.
It never touches anything private (no GitHub SSH, no Bitwarden, no
private repo) - phase 1 runs from a plain TTY; phase 2 is
`./bootstrap-personal.sh` (see the Runtime Ownership row). It does not install packages, write files, manage services,
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
4. **AUR** - last resort only for the BASELINE, never by default. Runtime
   exception (2026-10-07, the user's explicit wish): the AUR helper `yay`
   is provisioned (`roles/packages`, pinned build) so the user can install
   and remove AUR packages themselves from OS menu -> Packages; those stay the
   user's runtime choices, never part of the provisioned baseline. Do not
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
- Known, accepted cosmetic: that central task can report `changed=1` on
  an otherwise unchanged re-run when the mirror's package databases
  changed since the last sync (`community.general.pacman` counts the
  refresh itself; `pacman.log` then shows only "synchronizing package
  lists", nothing upgraded). Idempotency means every *role* reports 0
  changes - don't restructure the sync to hide this.
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

**VPN foundation** (`roles/network`): `wireguard-tools` is installed so
NetworkManager can import/manage a WireGuard profile
(`nmcli connection import type wireguard file ...`) once one exists.
No actual profile is created or committed here - a real profile has a
real endpoint and keys, which are secrets and belong only in the
separate private-config repository. **Uni-VPN resolved (2026-10-07)**:
THWS = FortiGate SSL-VPN (`vpn.thws.de`, K-number + password). Feature
`fortinet_vpn_enabled` (laptop, workstation): openfortivpn (official) +
`networkmanager-fortisslvpn` - the ONE AUR package, built from a pinned,
reviewed AUR commit with makepkg + pacman -U (not through yay). Chosen over
the official openconnect NM plugin because that one needs a secret agent
for its per-connect auth dialog (none here), so the network popup's
toggle could not connect. The profile is the user's (password stored
"for all users", split tunnel `ipv4.never-default yes`) - README "Uni
VPN (THWS)". Real-hardware-tested on the laptop: connect from the session
like the popup, ~120 pushed uni routes via `ppp0`, internet direct, DNS.

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

That is not a blanket ban on `host_vars/arch-dev.yml` itself, though: a
disposable VM is still a host like any other, and can get a `host_vars`
file for a *genuine, real* deviation the same way `laptop`/`workstation`
would — e.g. `hyprland_main_modifier: ALT` (see
`host_vars/arch-dev.yml`), needed only because testing arch-dev's guest
Hyprland session happens under a host machine that also runs a
SUPER-based Hyprland session, so SUPER keybinds never reach the guest,
and the host has no normal Alt-based keybindings of its own. The rule
is "no invented deltas", not "no VM host_vars file at all".

## Testing

Before considering any Ansible/shell change done, run all of:

```sh
bash -n bootstrap.sh
ansible-playbook --syntax-check local.yml
ansible-inventory --list
```

`tests/run.sh` runs these plus `sh -n` of the shell helpers, a YAML parse
of every tracked YAML file, `tests/theme-helper.sh` (the `theme` helper
against a temporary copy of `themes/`, stubbed session tools) and
`tests/qml-logic.qml` (pure logic cut out of the shipped QML, via `qml6`) -
all safe on a live desktop, ~10 s. On a provisioned machine,
`repo-healthcheck` is the live counterpart (exit 0 = invariants hold).

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
- `base` role (package install only — see "Structurally tested only"
  below for this session's sshd/locale/vconsole additions to this same
  role): `git`, `openssh`, `curl`, `rsync`
- `graphics` role: `wayland`, `wayland-protocols`, `mesa`, `xorg-xwayland` (Wayland/Mesa/XWayland foundation, no compositor)

**Implemented, structurally tested only** unless noted otherwise
(syntax-check, `--list-tasks`, standalone Jinja2/Lua render+`luac -p`
check, and a standalone `ansible.builtin.replace` idempotency test all
passed in this session):
- `hyprland` role: installs `hyprland`, `ghostty` (replaces the earlier
  `foot` placeholder as the default terminal), and `fuzzel` (temporary
  launcher, see Runtime Ownership). Deploys `~/.config/hypr/hyprland.lua`
  with animations/blur/shadow disabled, autostarts `hyprpolkitagent` +
  `mako` once via `hl.on("hyprland.start", ...)`, and binds (on
  `hyprland_main_modifier`, default `SUPER` — see below):
  `mainMod+Return` (terminal), `mainMod+Q` (close), `mainMod+Space`
  (launcher), `mainMod+[1-9]` / `mainMod+Shift+[1-9]` (workspace
  switch/move), `mainMod`+arrows (focus), `mainMod`+LMB/RMB drag (move/
  resize floating windows), `mainMod+Shift+S` (region screenshot →
  clipboard), `Print` (fullscreen screenshot → clipboard),
  `mainMod+Shift+E` (exit). Still no bar, lock/idle, wallpaper, or
  display manager — Hyprland remains manually started from a TTY.
  **Real-VM-tested**: Hyprland now starts successfully on `arch-dev`
  (root cause of the earlier crash was a VirtualBox setting — 3D
  Acceleration was off — not this repository's config; no
  graphics/Hyprland workaround was added for it). `hyprland_main_modifier`
  is configurable per host precisely because `arch-dev`'s nested guest
  session needs `ALT` instead of `SUPER` (host input capture, not a
  graphics issue) — see `host_vars/arch-dev.yml` and VM / Hardware
  Separation. A left/right-specific keysym (`Alt_R`) was tried first and
  real testing showed Hyprland rejects it in this project's combined
  binds ("Modifiers must come first in the list" / "Cannot combine
  special syms") - `hyprland_main_modifier` must be one of Hyprland's
  classic modifier names (SUPER, ALT, SHIFT, CTRL/CONTROL, ...), never a
  keysym name. Not yet confirmed: every item on the full daily-driver
  manual checklist (audio/clipboard/notifications/etc.) individually.
  **Real-VM-tested (follow-up session on `arch-dev`)**: two further
  genuine VM-only deviations found and fixed, both via `host_vars/
  arch-dev.yml`, neither touching `laptop`/`workstation` defaults.
  (1) `hyprctl monitors -j` showed `physicalWidth`/`physicalHeight: 0`
  for VirtualBox's virtual display, which made the default
  `scale = "auto"` mis-detect scale 2 for a 1280x800 output instead of
  1 — the whole session (incl. Thunar windows) rendered far too large
  for the visible VM area. Fixed via the new `hyprland_monitor_scale`
  variable (default `"auto"`), overridden to `1` for `arch-dev`.
  (2) Ghostty failed to start (`Gdk: Error flushing display: Broken
  pipe`); `GSK_RENDERER=cairo ghostty` isolated the cause as
  `OpenGL version is too old. Ghostty requires OpenGL 4.3` against
  VirtualBox's 3D-accelerated OpenGL 4.1. `LIBGL_ALWAYS_SOFTWARE=1`
  (Mesa software rasterizer, OpenGL 4.6) fixed it — `hyprland_terminal`
  is overridden to `env LIBGL_ALWAYS_SOFTWARE=1 ghostty` for `arch-dev`
  only (`laptop`/`workstation` have real GPUs meeting the 4.3
  requirement and keep the plain `ghostty` default). Confirmed working
  via the real `mainMod+Return` keybind after a VM restart, not just
  manually. Known accepted gap: fuzzel still launches Ghostty via its
  own unmodified `.desktop` entry, so fuzzel→Ghostty still fails the
  same way on `arch-dev` — not fixed, since `hyprland_terminal` only
  covers the `mainMod+Return` keybind path. The "only `mainMod+Space`
  responds, other `mainMod` binds seem dead" symptom that triggered
  this investigation was *not* a binds/config bug (`hyprctl binds`
  showed every bind correctly registered as an ALT combo throughout):
  after a VM restart, `mainMod+Return`, `mainMod+Q`, and
  `mainMod+[1-9]` workspace switching were all confirmed working
  normally — the earlier failures were a transient host-side keyboard-
  capture issue (VirtualBox running under a Wayland host compositor),
  not this repository's config, and needed no repository change.
- `desktop` role (new): `hyprpolkitagent`, the
  `xdg-desktop-portal`/`-hyprland`/`-gtk` trio, `wl-clipboard`, `grim`+
  `slurp`, `mako`, `brightnessctl`; adds the invoking user to the
  `video` group for brightness control. **Real-VM-tested (this
  session)**: region screenshot (`mainMod+Shift+S`) confirmed working
  end-to-end on `arch-dev` — `slurp` selection appears, `wl-paste
  --list-types` confirms `image/png` actually lands in the clipboard;
  `mako` confirmed running and delivering notifications; all three
  portal units confirmed `active (running)` with `-hyprland`'s own log
  showing successful PipeWire/screencopy init (see the portal-warnings
  entry above for the one, confirmed-harmless, non-fatal warning from
  `xdg-desktop-portal` itself). `hyprpolkitagent` was confirmed **not**
  running before this session's path fix (see above) — not yet
  re-confirmed running after the fix.
- `audio` role (new): `pipewire`, `wireplumber`, `pipewire-audio`,
  `pipewire-pulse`, `pipewire-alsa` — no PulseAudio in parallel
  (`pipewire-pulse` conflicts with `pulseaudio` at the pacman level).
  No service-enable tasks: these ship socket-/D-Bus-activated systemd
  `--user` units by default. **Real-VM-tested (this session)**: `wpctl
  status` on `arch-dev` confirms PipeWire 1.6.9 + WirePlumber running,
  with VirtualBox's `Built-in Audio [alsa]` correctly detected as both
  sink and source ("Built-in Audio Analog Stereo"). This confirms
  PipeWire/WirePlumber + basic VirtualBox device detection specifically
  — **not** bare-metal `laptop`/`workstation` audio hardware, which
  remains unconfirmed.
- `network` role (new): `networkmanager` (enabled+started as a system
  service) + `wireguard-tools` (VPN foundation only, no profile/UI —
  see Networking Rules). **Real-VM-tested (this session)**:
  `systemctl` confirms `NetworkManager.service` `enabled`+`active
  (running)` on `arch-dev`; `nmcli general status` reports `connected`/
  `connectivity full`, with `enp0s3` (VirtualBox NAT Ethernet) connected.
  Confirms NetworkManager as the working network owner on this VM's
  virtual NIC — not yet confirmed against `laptop`/`workstation`'s real
  Wi-Fi hardware (WPA Enterprise/eduroam, captive portals — see
  Networking Rules — remain untested).
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
  **Real-VM-tested (this session)**: `yazi`, `qpdf`, `7z` present and
  runnable on `arch-dev`; versions confirmed (`neovim` 0.12.5, `gh`
  2.101.0, `git` 2.55.0, `ghostty` 1.3.1-arch2); IntelliJ IDEA Ultimate
  confirmed installed as a system Flatpak (`com.jetbrains.IntelliJ-IDEA-
  Ultimate` 2026.2.3). `zathura`/`imv`/`mpv` real-file-open results are
  documented separately below (structurally tested / open points), not
  blanket "real-VM-tested" — see that entry for the exact, non-uniform
  outcome per app.

**Structurally tested only, pending real-VM re-test on `arch-dev`**
(daily-driver foundation stabilization session, `bash -n`/
`--syntax-check`/`ansible-inventory --list`/`--list-tasks`/YAML-parse/
Jinja2-render all passed; every fix below is grounded in real command
output from `arch-dev` via SSH, not guessed):
- **`base` role additions**: (1) `sshd.service` enabled+started
  (`ansible.builtin.systemd_service`) — real bug: `openssh` was already
  installed, but the service was never enabled, so host→arch-dev SSH
  needed a manual `systemctl enable --now sshd` first; now declarative,
  wanted on `laptop`/`workstation` too, not arch-dev-only (see Runtime
  Ownership: sshd is a system service). (2) `en_US.UTF-8` and
  `de_DE.UTF-8` locales generated (`community.general.locale_gen`) —
  conservative: does not touch `/etc/locale.conf`'s `LANG`, only makes
  `de_DE.UTF-8` available. (3) `/etc/vconsole.conf` `KEYMAP=de-latin1`
  (Arch-documented German console keymap) for the pre-login virtual
  console, separate from Hyprland's own Wayland keyboard layout below.
- **`hyprland` role**: (1) `hyprland_keyboard_layout` (default `de`)
  now sets `hl.config({ input = { kb_layout = ... } })` — this machine
  is primarily used with a German keyboard. (2) **Root cause found and
  fixed for hyprpolkitagent never starting**: `pgrep -af hyprpolkitagent`
  found no process while `mako` (started the same way) was running fine.
  `pacman -Ql hyprpolkitagent` showed the binary at
  `/usr/lib/hyprpolkitagent/hyprpolkitagent`, not on `$PATH` (unlike
  `mako`) — `hl.exec_cmd("hyprpolkitagent")` was silently failing a PATH
  lookup, no crash, no log. Fixed by using the absolute path. The
  package also ships a D-Bus service activation file
  (`org.hyprland.hyprpolkitagent.service`) and a systemd `--user` unit —
  this file's earlier claim that the polkit agent "is not
  D-Bus-activatable" was **wrong**; Hyprland session lifecycle is kept
  as the sole owner anyway, deliberately, not because D-Bus activation
  is unavailable (see Runtime Ownership; no second autostart path).
- **`apps` role**: `~/.config/mimeapps.list` now sets `application/pdf`
  → `org.pwmt.zathura.desktop` and `image/png` → `imv.desktop`. Real-VM
  finding: with no default set, `xdg-mime query default` resolved both
  to `chromium.desktop` (Chromium self-registers for both), not the
  readers this role actually installs zathura/imv for. Only these two
  confirmed-wrong associations are set — not a speculative full
  `image/*` mapping (other image MIME types were not tested).
- **Portal warnings investigated, confirmed harmless, no fix applied**:
  `journalctl --user -u xdg-desktop-portal.service` showed repeated
  `Failed to load RealtimeKit property: ... The name is not
  activatable`. Root cause: the optional `rtkit` (realtime scheduling
  for PipeWire audio threads) is not installed — unrelated to portal
  configuration. `xdg-desktop-portal-hyprland`'s and `-gtk`'s own logs
  are clean, and the portal's actual job (screencopy/PipeWire init) is
  confirmed working (matches the already-real-VM-tested region
  screenshot feature). Not fixed: `rtkit` would be a new package for an
  already-non-broken warning, out of this run's "no new features" scope
  — flagged as an open point, not silently added.
- **zathura/imv real-file test — real bug found, confirmed workaround,
  deliberately NOT wired into the repository**: opening a real (freshly
  generated, structurally valid) test PDF/PNG failed for both with a
  Wayland protocol error (`wl_surface#N.attach: invalid arguments`) —
  same failure class as the already-fixed Ghostty OpenGL-version issue,
  different mechanism. `LIBGL_ALWAYS_SOFTWARE=1 zathura|imv <file>`
  confirmed working (visually verified: real PDF content and the test
  PNG both rendered in the VM window). Not applied as a repository fix:
  unlike `hyprland_terminal` for Ghostty, there is no existing per-app
  launch-command variable covering zathura/imv's actual launch paths
  (Thunar "Open with" / fuzzel / MIME double-click), and inventing a
  session-wide env-var mechanism would mean guessing an unconfirmed
  `hl.*` API — deliberately deferred rather than guessed. Manual
  workaround on `arch-dev` in the meantime:
  `LIBGL_ALWAYS_SOFTWARE=1 zathura|imv <file>`.
- **mpv real-file test — confirmed correct as-is, explicitly not
  "fixed"**: default `mpv <file>` on a real WAV test file selected the
  audio track and played correctly; the optional cover-art *video*
  display hit the same `wl_surface.attach` error as zathura/imv above,
  but mpv handled it gracefully (clean exit 0) — core function (audio
  playback) intact. `LIBGL_ALWAYS_SOFTWARE=1` was also tested against
  mpv and made things **worse**: mpv's `gpu-next` VO detected the forced
  software renderer, wrongly attempted an X11 fallback in this
  Wayland-only session, and crashed
  (`Assertion '!vo->x11' failed`, coredump). mpv is therefore left
  completely untouched — no wrapper, no env override — per this run's
  explicit instruction not to "fix" mpv behavior that is already
  correct. Real video-file (not just audio-with-cover-art) playback was
  not tested this session — open point.

**Not started (no code yet):** Bluetooth, session/lock/idle,
hardware-specific optimization, tray, notification center, control
center, lock screen. Quickshell now owns the bar and the app launcher
(Core Desktop v1, see "Next Milestone" below) - the rest of this list
is still genuinely not started.

**Deliberately deferred this run — open points, not oversights:**
- **LazyVim bootstrap**: resolved (Daily-Driver Integration batch) - the
  starter is created once only where no `~/.config/nvim` exists, never
  managed afterwards; Neovim config stays the user's/dotfiles'. The
  theme interface is `lua/plugins/workstation-theme.lua` (dofile of the
  helper's `neovim.lua`).
- **Discord**: Chromium web app (`apps_webapps`, 2026-10-08, the user's
  choice); WebCord (Flathub) retired. The Arch `discord` package is only
  Discord's self-updating bootstrap (client lives in ~/.config/discord) -
  not used.
- **`gaming_enabled` / `gaming_gpu_vulkan_packages`**: neither is set
  for `laptop` or `workstation` — real GPU hardware was not provided
  and must not be guessed. Gaming stays disabled on both real hosts
  until their real GPU is documented and both variables are set
  together in the relevant `host_vars/<hostname>.yml` (see
  `group_vars/all.yml` and the comments in both `host_vars/*.yml`).
- **Webapp management**: `apps_webapps` (roles/apps) renders launcher
  entries for Chromium web apps (WhatsApp so far); GeForce NOW,
  Overleaf, draw.io are plain pages until added there.

**Documentation gaps found during the prior audit, still open:**
- `docs/DESIGN_SYSTEM.md` covers colors and typography incl. the one
  text size (`Fonts.px`); spacing is still per-component constants.
- `config/`, `systemd/`, `hardware/`, and `scripts/diagnostics/` appear
  in `README.md`'s repository-structure diagram but hold no tracked
  files (git does not track empty directories) — a fresh clone will not
  have them. Don't assume they exist; create them with real content
  when the corresponding role is actually built, or fix the README
  diagram if they turn out unnecessary.

## Next Milestone

**Status as of Feature Architecture v1** (supersedes the stale
"Quickshell foundation" narrative this section used to carry - see git
history for that milestone's own record):

- **Quickshell Core Desktop v1**: real-VM-validated on `arch-dev`. Bar
  (per-monitor workspaces, clock, network incl. SSID, volume
  scroll/click-to-mute, battery-if-present) + a native keyboard-first
  app launcher (`Quickshell.DesktopEntries`, `mainMod+Space`, toggled
  via `qs ipc call launcher toggle`) - fuzzel fully retired (package
  removed, see commit `03d0b78`). Exactly one Quickshell process,
  parented by Hyprland, confirmed via real session restart.
- **VirtualBox GPU fix**: `arch-dev` needed `LIBGL_ALWAYS_SOFTWARE=1`
  for both Ghostty and Quickshell (`host_vars/arch-dev.yml`,
  `hyprland_terminal` / `hyprland_quickshell_cmd`) - the same
  `wl_surface.attach` failure class already documented for zathura/imv/
  mpv above, root-caused via the `scripts/diagnose-quickshell-autostart.sh`
  diagnostic added for this investigation. `laptop`/`workstation` are
  unaffected (real GPUs) and keep the plain defaults.
- **Feature Architecture v1**: see the new "Feature Architecture"
  section above and `docs/feature-architecture.md`. `screenshots_enabled`
  (`group_vars/all.yml`) is the proof-of-concept migration - real-VM
  validated both `true` (default) and `false` on `arch-dev`, then
  restored to `true`.

- **Central Color System v1**: Bar and Launcher read only the `Colors`
  singleton (`Colors.qml` -> `DefaultDark.qml`, contract
  `ColorScheme.qml`); no hex color left in components. Visually
  identical refactor. Superseded by Theme Architecture v1 (the scheme
  files are gone; `Colors.qml` is generated from `themes/`).
- **Power Menu v1**: `power_menu_enabled` - first optional Quickshell
  component; established the `shell.qml.j2` composition pattern (see
  `docs/feature-architecture.md`).
- **Lock + Idle v1**: `lock_idle_enabled` - hypridle + hyprlock, one
  lock path (`loginctl lock-session`) for Super+Delete, power menu, idle and
  before-sleep. First persistent process added since the idle baseline
  (hypridle, ~7 MB, 0% CPU - see `docs/idle-baseline.md`). arch-dev
  needs `LIBGL_ALWAYS_SOFTWARE=1` for hyprlock too (host_vars). Manual
  PAM test passed on arch-dev (wrong password rejected, correct one
  unlocks). v1.1: coffee-mode idle-inhibit toggle in the bar.
- **System Font v1** (+ correction): GTK/sans-serif use Adwaita Sans;
  Quickshell/hyprlock FiraCode Nerd Font; monospace/Ghostty FiraCode
  Nerd Font Mono (names only in `group_vars/all.yml`).
- **Theme Architecture v1**: themes are data (`themes/*.yml`, 5 shipped:
  Retro 82, Solarized Dark, Catppuccin Mocha / Rosé Pine Dawn,
  Catppuccin Latte), one semantic-role contract (11 roles since `success`) validated by `roles/theme`,
  adapters for Quickshell, Hyprland borders, hyprlock, GTK mode.
- **Theme Switcher v1**: theme directories with dark/light markers as the
  only registry, `theme` helper (state, discovery, render, live apply -
  no sudo, no bootstrap), bar moon/sun icon (left click toggle, right
  click picker).
- **Theme Coverage v2**: mandatory 16-color `terminal:` block per theme;
  Ghostty fully themed via the helper (`config-file` include, live
  reload by `SIGUSR2`); staged atomic writes. Zathura deferred.
- **Notifications v1**: `notifications_enabled` - Quickshell owns
  `org.freedesktop.Notifications`; toasts only (no history/center).
  mako retired. Quickshell 0.3.1 quirks found on arch-dev:
  `Notification.expireTimeout` is milliseconds (doc says seconds), and
  an `image-path` icon name becomes an unchecked `image://icon/` URL.

- **Functional completion (last milestone before RICE v1)**: Hyprland
  config split into modules (`conf/*.lua`) + monitor foundation
  (`hyprland_monitors`); hardware keys; lid -> lock + suspend (logind
  drop-in, `roles/power`); battery fix (UPower percentage is 0-1) +
  low-battery warning (core); features `power_profiles`, `audio_popup`,
  `connectivity` (Wi-Fi/QR/Bluetooth/VPN), `clipboard_history`
  (cliphist), `wallpaper` (theme backgrounds, per-theme choice) - see
  their contracts in `docs/feature-architecture.md`. Bootstrap now also
  brings back a stopped desktop Quickshell.

- **Daily Driver Polish batch** (laptop, real-hardware-tested - details in
  the commit messages and `docs/feature-architecture.md`): network
  password survives Wi-Fi scans (Other networks = SSID-keyed ListModel,
  frozen during the password interaction) + eye toggle + own 10-row
  scroll area; Bluetooth pair -> exactly one connect; AC = Performance
  policy; one desktop text size; display scale presets + Change; bar
  transparency in Appearance; Visuals bar widget (Timer, Day/Night via
  hyprsunset with a 1 s fade, Light/Dark, Coffee); Share view masks the saved Wi-Fi password; new apps (Anki, Disks, Loupe,
  Planify, LocalSend + WebCord via Flathub, WhatsApp web app) and
  `roles/development` (gh, lazygit, JDK 25, Python/uv, Docker on demand);
  the user's wallpapers.

- **RICE v1 step 1 - modular bar**: Omarchy-style bar host + widgets
  (`bar/`), layout as user state with drag & drop (also across zones),
  clock as exact center anchor, one-popup coordinator, common
  BarWidget/BarPopup, compact look (`docs/feature-architecture.md` "Bar",
  `docs/DESIGN_SYSTEM.md` "Bar look"). The rest of the rice is not
  started yet.

- **Pre-v1 Break-It Stability Audit** (real-VM-tested on `arch-dev`): no
  new features - systematic attack of the existing system, root-cause
  fixes, `repo-healthcheck` (on-demand PASS/FAIL invariants) and
  `tests/run.sh` (permanent repository checks). Fixed: logout/reboot
  coredumps of hyprpolkitagent, xdg-desktop-portal-hyprland, hypridle
  (+ failed portal units) via an ordered `session-stop` in Hyprland's own
  shutdown hook; bar popup and OS menu/overlays open together, popup then
  deaf to Escape (one coordinator for all transient surfaces); Escape dead
  after the network password box / Bluetooth PIN field closes; duplicate
  Wi-Fi failure log line; QML binding loop on the connectivity model during
  route changes with the popup open; "via VPN" missing for NM's
  policy-routed WireGuard full tunnel; lost theme updates on concurrent
  `theme` calls (flock); `theme` tracebacks on a non-UTF-8 state/theme.yml;
  no low-battery warning when already low at login; DeprecationWarning of
  the pairing agent at every pairing; a tracked `.pyc`; power menu / OS
  menu / clipboard history opened under a resting pointer took the row
  under it as selection (Enter on `mainMod+Escape` could log out or shut
  down instead of locking) - hover now selects only after real movement. Upstream/VM-only,
  documented in `docs/feature-architecture.md`/README: helpers still abort
  when a session is SIGTERMed from outside; imv busy-loops after the
  compositor is gone (ends with the user manager); hyprlock has no
  errors-only log level; mpv/zathura/imv need software GL on arch-dev.

- **Real Hardware Stage 1 - laptop bring-up** (ThinkPad T440p, hostname
  `laptop`; real-hardware-tested): first workstation-arch deployment over
  Ly -> start-hyprland on real i915 (Mesa crocus, OpenGL 4.6 core, no
  LIBGL workaround), `repo-healthcheck` HEALTHY, second bootstrap
  changed=0. Validated physically: eDP-1 1920x1080@60 scale 1, brightness
  (sliders + keys, no double steps), battery/AC/undock transitions and
  UPower estimates, all three power profiles, Wi-Fi (Intel 7260, 5 GHz,
  wrong/right password, Ethernet<->Wi-Fi default route), Bluetooth
  pairing/connect/disconnect/forget, internal speaker + mic, volume/mute/
  mic-mute keys + LEDs, idle lock, Coffee, DPMS, lid suspend/resume x3,
  docked lid ignore, external 4K HDMI monitor + hotplug, logout/login.
  Fixed on the way: wireless-regdb; per-host VA-API (libva-intel-driver);
  monitor `position: 0x0` read as the number 0 by YAML; battery popup empty
  (`power: power` self-binding); network icon one route read behind
  (FileView text() after reload() is stale in Quickshell 0.3.1); redundant
  Bluetooth connect() after pairing; emoji font. Upstream: Hyprland
  SIGSEGV at exit with two outputs (aquamarine teardown). Not validated:
  HDMI audio, multi-monitor layout persistence, captive portal/eduroam/
  Uni VPN, Hibernate.

- **Recovery v1** (`recovery_enabled`, laptop only): Btrfs snapshots +
  bootable recovery slots + update/rollback commands
  (`docs/recovery-design.md`, section 21 = as built). **Real-hardware
  tested on the laptop** (slot boot, broken userspace/desktop, truncated
  UKI, permanent rollback, retention, space guard). Workstation: not
  enabled - its layout needs its own Stage 0 check first.

- **Daily-Driver Integration batch** (laptop): read-only Coffee IPC
  (`qs ipc call coffee status`); system LANG guaranteed + healthcheck
  "session locale"; `roles/shell` (Starship, zoxide, fzf, eza, bat,
  tealdeer); LazyVim starter + exact per-theme Neovim colorscheme (theme
  payload `neovim:`, live switch); Zoom as web app (native Flathub Zoom
  retired: XWayland toolbar ignores input); `python-dbus` for the
  eduroam CAT installer; timer digits-from-the-right parser + H:MM:SS;
  Visuals hover fade; collapsible tray; Day/Night 0.5 s; network popup
  Connections... button. Real-hardware-tested over SSH: Coffee IPC,
  locale (session, systemd user, activated portals), tools, Starship,
  LazyVim plugin install, all 5 theme->Neovim mappings incl. live switch
  of a running Neovim, portal stack audit; GUI (virtual pointer +
  screenshots, and by the user): tray hover/menu, Visuals fade, timer
  input/Enter/Start/Stop and >1 h, Day/Night, Connections button,
  screen sharing in WebCord and Zoom web (Chromium path). Open: eduroam
  enrollment (needs the user's credentials).

- **Hardening v1 + Firewall UI** (laptop, real-hardware-tested 2026-10-07,
  explicitly requested past the freeze): `roles/firewall` (nftables table
  `inet workstation`, oneshot loader, no daemon, never `flush ruleset`;
  Docker-published ports filtered in `forward` by the pre-DNAT port),
  key-only SSH + host capability `ssh_server_enabled`, no ICMP redirects,
  Settings -> Firewall (pkexec + polkit helper `firewall-rules`, new rules
  start disabled), role `success`, Bluetooth battery % instead of
  Connected, two Appearance info lines removed. Tested on the laptop: boot
  load after the kernel upgrade, SSH offers only publickey, IPv4/DNS,
  IPv6 link-local/ND (the LAN has no global IPv6), redirects off, full rule
  lifecycle through the UI path with real TCP/UDP probes from a LAN host,
  persistence (Quickshell reload, unit restart = boot path), Docker
  (published port LAN-blocked until enabled, also via docker-proxy/IPv6;
  127.0.0.1 publish local; container networking/outbound/DNS; Docker's
  tables unchanged across rule ops and a firewall reload; Docker back to
  disabled/inactive), LocalSend both directions (multicast + mTLS API), a
  temporary split WireGuard profile (routes, outbound, handshake sent).
  Bluetooth battery confirmed by the user on the real popup (Bose QC
  headphones via Battery1 = correct %, JBL without Battery1 = Connected).
  A real LocalSend file transfer was confirmed by the user; the THWS VPN
  (real FortiGate peer through the firewall) works - see Networking Rules.
  Not tested: eduroam.
- **Chromium policy + VPN plugins** (laptop, 2026-10-07): managed policy
  `/etc/chromium/policies/managed/workstation.json` - six store
  extensions (installed by Chromium itself, IDs checked against store
  publisher) + the THWS library PAC (net-log: SpringerLink -> library
  proxy, others DIRECT; proxy answers 407, Chromium shows its own login).
  End-to-end confirmed by the user: proxy login in Chromium, licensed
  content accessible. Note: the THWS PAC names a plain-HTTP proxy.
  Official NM VPN plugins OpenVPN/OpenConnect/strongswan added (profiles +
  imports validated in memory, no extra idle process, strongswan's own
  daemons disabled); WireGuard imports come with autoconnect on (README).

- **Pre-transaction snapshots + Scratchpad phase 1** (laptop, 2026-10-07,
  real-hardware-tested): pacman PreTransaction hook -> one snapper snapshot
  per transaction (class `auto=pre-transaction`, newest 3 kept, slot-used
  and non-class snapshots never pruned; system-update's own snapshot makes
  the hook skip; failure aborts the transaction; baseline = known-good
  slot). Real: a 2-package transaction -> one snapshot, retention removed
  the oldest each time, non-class snapshots identical before/after.
  Scratchpad: Quickshell top-level window via LazyLoader (exists only while
  open), mainMod+N + bar icon, four notes `~/.local/share/workstation/
  scratchpad/{1..4}.txt`; real GUI tests (keys + mouse via a one-shot
  uinput test device): open/close paths incl. Super+Q and free-desktop
  click, Alt+1..4 + dots, autosave, no-wrap/scroll, -/+ persistence, bar
  icon, live theme switch. Found on hardware and fixed: 2-3 package hook
  abort (set -e), bar namespace collision (shell down ~8 min), no reopen
  after Super+Q, free-desktop click did not close.

- **Packages menu + network popup metrics** (laptop, 2026-10-07,
  real-hardware-tested): OS menu -> Packages -> Install/Remove (Arch, AUR,
  Flatpak) -> `workstation-pkg` (fzf in Ghostty; pacman/yay/flatpak with
  their own confirmations; yay = pinned AUR build, runtime only). Real: all
  six pickers opened from the menu search, Esc leaves no process; AUR
  `hello` installed via yay (built as the user, one pre-transaction
  snapshot) and removed again; a missing Flathub catalog is fetched on
  demand. Network popup: Download/Upload + Ping/Packet loss (one 5-ping
  run per 5 s to 1.1.1.1, only while open) and a speedtest icon
  (speedtest-cli once per click, no double start, killed on close; proven
  0 ping/speedtest processes after closing).

- **Private handover** (2026-10-07, explicitly requested): `stow` in
  `roles/base`, github.com host keys pinned in `~/.ssh/known_hosts`,
  `scripts/private-handover.sh` (+ `tests/private-handover.sh`) - the
  checkpoint and clone/fast-forward of the private `dotfiles-provision`,
  whose `bootstrap.sh` (GNU Stow, user-level) it then runs.

- **Enterprise Wi-Fi in the network popup** (2026-10-08, bugfix after the
  first campus use - eduroam autoconnected, internet fine, popup wrong):
  Quickshell 0.3.1 attaches a saved profile only with an explicit
  `802-11-wireless.mode infrastructure`; the CAT profiles eduroam/THWS have
  none, so they were neither Known nor Connected and a click said
  "enterprise". The popup now lists NM's Wi-Fi profiles itself (`nmcli`,
  open/NM events) and switches them by UUID (`nmcli connection up uuid`);
  bar signal via one `nmcli` per NM event only in that case. Deployed to the
  laptop (second bootstrap changed=0); logic checked against the laptop's
  real profiles. Not real-tested: the popup on campus and an actual
  eduroam <-> THWS switch (at home, both out of range; SSH only via Wi-Fi).

- **Discord web app + two-phase bootstrap** (laptop, 2026-10-08,
  real-hardware-tested): Discord = Chromium web app (`apps_webapps`),
  WebCord retired; the user tested login, UI, audio/mic and screen sharing
  (two shares in a row). `./bootstrap.sh` = phase 1 only (no GitHub SSH,
  no Bitwarden, no private repo): two runs in a row changed=0 failed=0
  exit 0. `./bootstrap-personal.sh` = phase 2 (preflight + the handover,
  no wait loop): locked agent -> one ACTION REQUIRED, exit 3 at once;
  unlocked -> fast-forward + private bootstrap, exit 0; second run
  idempotent. `nextcloud-client` moved to roles/apps (the private repo
  has no packages/sudo any more).

- **Power menu search, updater, Python/Java/Neovim languages** (laptop,
  2026-10-10, explicitly requested): power menu type-to-search + wrapping
  Up/Down; Update / Create Snapshot (recovery hosts) + bar update icon on top
  of system-update/system-snapshot (`--ui`, `--no-snapshot` only after a
  failed snapshot + explicit Ja; `snapshot-create` via pkexec); the locked uv
  Data Science environment with JupyterLab (127.0.0.1); Maven + Gradle on JDK
  25; LazyVim language extras + `workstation-languages.lua`, Mason/parsers
  installed headless by the bootstrap. Real-hardware-tested: menu keys incl.
  wrap/zero matches, dialogs (Nein default, Escape, snapshot-failed question,
  the Ja launch up to sudo), a real Create Snapshot, all Python imports +
  notebook + Streamlit, Java compile/Maven/Gradle, every language's LSP/
  diagnostics/completion/formatter/DAP config headless, VimTeX compile; two
  bootstraps changed=0. NOT tested live: a real update through the dialog
  (not released), a real snapshot failure, the icon with real pending updates
  (none pending; logic tests only), Zathura forward search after this change.

- **Scratchpad sync, Super+B, firewall transparency** (laptop, 2026-10-10,
  explicitly requested): scratchpad = one watched `~/Documents/.system/
  scratchpad.md` (Nextcloud folder /2_Dokumente - found already configured;
  migrated from the four .txt, old files kept), conflict copy on external
  change during typing; Super+B = Chromium via focus-or-launch; firewall
  window "Wirksamer Zustand" (`firewall-rules status`, read-only).
  Real-hardware-tested: migration, external change closed/typing (conflict
  copy), reopen; Super+B start + focus; status view (SSH = base rule for all
  sources/interfaces/IPv4+IPv6, live connection shown), ruleset hash
  unchanged throughout; :Lazy/:Mason UIs; VimTeX -> Zathura forward search
  (page 1 / page 3); bootstrap changed=0, --check ok. Still untested: a real
  update through the dialog, a real snapshot failure, the update icon with
  real pending updates (none pending).

**FEATURE FREEZE**: no new functional features. Next is RICE v1 (visual
polish only); real-hardware validation of the items listed in
`docs/feature-architecture.md` ("Hardware-only validation") and the
milestone report stays open on `laptop`/`workstation`.
