# REPO v1.0.0 - release notes

2026-10-14. First stable release of `workstation-arch`: a reproducible Arch
Linux workstation, provisioned with Ansible from a clean upstream Arch install
(archinstall + `./bootstrap.sh`, then `./bootstrap-personal.sh` for the
private handover).

Accepted on a ThinkPad T440p (`laptop`) after a genuine clean install:
kernel 7.2.9, systemd 262, Hyprland 0.56.2, Quickshell 0.3.2, LUKS2 + Btrfs +
systemd-boot UKI. Evidence: `CLEAN_INSTALL_ACCEPTANCE_V1_REPORT.md`.

## What is delivered

- **Provisioning**: `bootstrap.sh` (upstream-Arch guard, one
  `--ask-become-pass`) -> `local.yml` -> roles; one central `pacman -Syu`
  per run; per-host deltas in `host_vars/`; optional capabilities as flat
  `<name>_enabled` features. A second run reports `changed=0`.
- **Two-phase bootstrap**: phase 1 is public and credential-free; phase 2
  (`bootstrap-personal.sh`) checks the Bitwarden SSH agent and GitHub,
  then clones / fast-forwards the private dotfiles repository.
- **Desktop**: Ly -> Hyprland -> Quickshell. Modular bar (drag & drop
  layout), OS menu / launcher with type-to-search, notifications, tray,
  clipboard history, scratchpad, cheatsheets, power menu, lock + idle
  (hypridle/hyprlock), night light, timer, Coffee mode, Appearance
  (themes, wallpaper, text size, display scale, brightness).
- **Theming**: themes are data (`themes/<id>/`), one semantic color
  contract, one `theme` helper; live switching of Quickshell, Hyprland,
  hyprlock, GTK/Qt light/dark, Ghostty and Neovim; Omarchy theme
  repositories importable as data.
- **Connectivity**: NetworkManager (Wi-Fi, WPA Enterprise/eduroam
  profiles, captive portal login, WireGuard/OpenVPN/OpenConnect/IPsec,
  THWS FortiGate VPN), network popup with live metrics on demand, BlueZ
  with an in-popup pairing agent, PipeWire/WirePlumber audio popup.
- **Security**: nftables firewall (own table, oneshot loader, rule editor
  through polkit), key-only SSH only where enabled, no ICMP redirects,
  polkit PAM stack where a cancelled dialog is not a faillock failure,
  Docker on demand without the `docker` group, Chromium managed policy.
- **Updates and recovery** (`recovery_enabled`): snapper snapshots before
  every pacman transaction and update, `system-update` / `system-snapshot`
  / `system-rollback`, three manual snapshot slots, snapshot boot entries
  in systemd-boot with a read-only overlay boot, permanent restore from
  snapshot mode, updater dialog and pending-update icon.
- **Diagnostics**: `repo-healthcheck` (PASS/FAIL invariants),
  `repo-diagnose`, `repo-logs` (log viewer + rule-based analysis) - all on
  demand, no background processes.
- **Apps and development**: Chromium (+ web apps), Thunderbird, Nautilus,
  Neovim/LazyVim with language extras, VimTeX + Zathura, Obsidian,
  Bitwarden, Nextcloud client, IntelliJ IDEA (Flathub), JDK 25 +
  Maven/Gradle, Python/uv data-science environment, Docker; Packages menu
  for pacman / AUR (pinned yay) / Flatpak at runtime.

## Tests completed before this release

- Clean install of the T440p with archinstall + both bootstraps; second
  bootstrap `changed=0`, `repo-healthcheck` HEALTHY.
- Hardware acceptance **H1-H14: all PASS** on the clean install, including
  Wi-Fi + SSH, firewall and snapshot polkit flows (faillock 0 after
  cancel), lid suspend/resume, display/audio/microphone/Bluetooth, a real
  `system-update`, snapshot boot round trip, permanent restore + resync,
  and the LUKS recovery key, header backup and offline recovery stick
  (H14).
- Earlier milestones on real hardware: Bug Hunt v1 supervised tests,
  security hardening, 66/66 close-policy GUI checks, theme/Neovim live
  switching, VPN/firewall/Docker interaction.
- `tests/run.sh` (syntax checks, YAML, theme helper, QML logic) passes.

## Known limitations

- **Destructive LUKS header restore was not tested.** The header backup
  was verified byte-identical and opens the container with
  `--test-passphrase --header`, but `luksHeaderRestore` was never run.
- **Recovery from Arch live media was not tested.** Unlocking, mounting,
  chroot repair and the manual restore in `docs/recovery/RECOVERY-GUIDE.md`
  (section 12b) are written but not executed. The LUKS recovery key was
  verified by typing it back, not at the real boot prompt.
- **Recovery setup is machine-specific.** The recovery key, header backup
  and stick belong to the laptop's LUKS container only; every other
  machine and every reinstall needs its own (`docs/recovery/README.md`).
  An old backup becomes invalid after any keyslot change.
- **Only `laptop` is accepted on hardware.** `workstation` has
  `recovery_enabled` off and its disk layout unchecked; gaming is not
  enabled on either host.
- Not validated on hardware: eduroam / campus Enterprise Wi-Fi switching
  in the popup, HDMI audio, multi-monitor layout persistence, hibernate,
  Secure Boot, a restore failing halfway, an older-kernel snapshot.
- Upstream: Hyprland may crash at exit with two outputs connected; Anki
  reads light/dark only at its start.
