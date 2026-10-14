# Clean Install Acceptance v1 - report

Date: 2026-10-14. Target: the ThinkPad T440p, freshly installed by the user
with archinstall (`CLEAN_INSTALL_PLAN.md`), then `./bootstrap.sh` (phase 1)
and `./bootstrap-personal.sh` (phase 2). Tested over SSH (Ethernet via the
dock) and inside the running graphical session. Branch
`clean-install-acceptance-v1`.

**Result: release candidate, not yet stable.** Neovim and one missing CLI
tool fixed, bootstrap reproducible and idempotent, HEALTHY. The mandatory
gates that need a reboot, a suspend, a Wi-Fi password or the user's eyes
are still open (section 12).

No reboot, suspend, format, repartition or permanent restore was done. LUKS
was only read (`luksDump`). The Fedora disk was not touched. SSH stayed up
throughout.

## 1. Installed baseline

| Item | State | Checklist |
|---|---|---|
| Host | `laptop`, Arch rolling, kernel `7.2.9-arch1-1`, systemd 262, Hyprland 0.56.2, Quickshell 0.3.2 | ok |
| Repository | `workstation-arch` at `~/repos/peppeppa/` - installed at `3bc082f`, now `clean-install-acceptance-v1` | path differs from the checklist (section 10) |
| Disks | `sda` 238.5G `LITEONIT LCS-256M6S`: `sda1` 1G vfat `/boot`, `sda2` LUKS2 -> `root`; `sdb` 476.9G `MicroFrom` (Fedora) not mounted, untouched | ok |
| LUKS | LUKS2, aes-xts-plain64, argon2id, **1 keyslot**, no tokens; crypttab empty | ok (recovery key: H14) |
| Btrfs | `/`=`@`, `@home`, `@log`, `@pkg`, `@snapshots` (`nosuid,nodev`), `@recovery`; fstab `subvol=/@...` without `subvolid` | ok |
| Boot | systemd-boot 262, UKI `/boot/EFI/Linux/arch-linux.efi` only (no fallback), preset `PRESETS=('default')`, `loader.conf` `timeout 3` / `default arch-linux.efi`, Secure Boot off | ok |
| cmdline | `cryptdevice=PARTUUID=...:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs` | ok |
| Initramfs | `... keyboard keymap consolefont block encrypt filesystems fsck` + `workstation-snapshot-overlay` (both in the UKI) | ok |
| Swap | `/dev/zram0` 4G zstd prio 100 only; no swap partition/file | ok |
| ESP | mounted `fmask=0177,dmask=0077` (root only) - new archinstall default; nothing of ours reads `/boot` as the user (healthcheck uses the sync state file) | ok |
| Network | NetworkManager only (networkd/iwd/resolved inactive); Ethernet up; Wi-Fi radio scans 2.4 + 5 GHz, no profile yet | ok |
| Users | `medvidec` in `wheel`; root locked; sudo with password only (`00_medvidec`, no NOPASSWD) | ok |
| Locale/time | `LANG=en_US.UTF-8`, `KEYMAP=de-latin1`, Europe/Berlin, NTP synced | ok |
| Units | no failed system or user units | ok |
| Explicit packages | every one from the repo's lists or archinstall's base (`linux`, `linux-firmware`, `intel-ucode`, `btrfs-progs`, `efibootmgr`, `ansible`, `pkgconf` = `pkg-config`); AUR: `yay`, `networkmanager-fortisslvpn` (pinned builds); no manual installs | ok |

## 2. Neovim startup failure

**Error** (every interactive start, 13 notifications, one per extra):

```text
Failed to load `lazyvim.plugins.extras.lazyvim.plugins.extras.dap.core`
vim/_core/shared:1082: s: expected string, got nil
  - vim/fs:617 _in_ expand_home / vim/fs:694 normalize / vim/loader:259 loadfile
  - /LazyVim/lua/lazyvim/util/plugin.lua:139 _in_ load
  - ~/.config/nvim/lua/config/lazy.lua:20
```

(same for formatting.prettier, lang.ansible, clangd, docker, java, json,
markdown, python, rust, toml, typescript, yaml). Captured from Snacks'
notification history of a real TUI start; `:messages` shows none of it.

**Root cause** (category: bootstrap ordering / dependency on old machine
state): `roles/apps` adds the language extras to `lazyvim.json` before
Neovim's first start. On a fresh install the file does not exist yet, so the
task created `{"extras": [...]}` **without `version`**. LazyVim 16.0.1 reads a
file without `version` as format 0, whose migration prefixes every entry with
`lazyvim.plugins.extras.` - every name doubled, no extra loaded, their
plugins (nvim-dap, nvim-jdtls, rustaceanvim, SchemaStore, venv-selector, ...)
never installed. Lacking `install_version` it also chose the pre-v8 defaults
(fzf-lua, neo-tree) instead of the snacks picker/explorer that our
`Space p v` keymap and cheatsheet use. On the old installation LazyVim had
written the file first, so the bug never showed. Not: a missing package,
executable, permission or parser.

**Fix** (`ccb9016`): the script moved to `roles/apps/files/lazyvim-extras.py`.
A new file gets `version` and `install_version` 8 (what LazyVim 16 writes for
a new install; a later LazyVim migrates from 8 itself); a file with the
doubled prefix is repaired (+ `install_version`); other extras/keys of the
user stay.

**Regression test**: `tests/lazyvim-extras.py` (in `tests/run.sh`): fresh /
broken / user-owned / old one-string files, idempotence, and - when a
LazyVim checkout exists - the result goes through LazyVim's own
`json.migrate` code. The old task's output reproduces the bug in it
(doubled names, install_version 7).

**Verification on the laptop**: the role's script repaired the file
(`changed`, then `unchanged`), the role's headless `nvim-install.lua` added
the missing plugins + 5 parsers (`failed: []`), a real TUI start shows **no
notifications**; pyright + ruff attach to a Python file, Tree-sitter
highlighting active, picker `snacks`, explorer `snacks_explorer` (not
neo-tree), theme `retro-82`, `Space p v` mapped, editing works. The later
bootstrap reported `apps` unchanged. fzf-lua and neo-tree remain in
`~/.local/share/nvim/lazy` unused (`:Lazy clean` is the user's call).

## 3. Bootstrap reproducibility

| Check | Result |
|---|---|
| Phase 1 log (pacman.log) | one run 10:37-11:00, roles in order, no manual pacman runs before/after |
| `./bootstrap.sh --check --diff` | ok=206 changed=2 failed=0: package DB sync (known cosmetic) + `bluez-utils` (the fix below) |
| Real run 1 | changed=2 failed=0 (sync upgraded `uv`; `bluez-utils` installed) |
| Real run 2 | **changed=0** failed=0 |
| Phase 2 | dotfiles stowed (`~/.bashrc`, `~/.gitconfig`), Bitwarden agent socket, `dotfiles-provision`, `homepage`, `scripts`, `var/walls` checked out clean; secrets not read |
| Recovery baseline | snapshot #13 `baseline: first complete provisioning (repo 3bc082f)` |

Findings:

1. **Neovim** (section 2) - fixed.
2. **`bluetoothctl` missing** - `docs/system_architecture.md` keeps the system
   administrable from the CLI and names `bluetoothctl`; `roles/bluetooth`
   left `bluez-utils` out on purpose (the desktop never uses it). The old
   laptop had it from before the repository. Fixed (`62c10b3`): `bluez-utils`
   in `bluetooth_packages`; `tests/clean-install.py` now checks every CLI of
   that list against the installed package lists (fails without the fix).
   Deployed, `bluetoothctl show` works.
3. **Checklist path**: it said `~/repos/Peppeppa/`; phase 2 and the README
   use `~/repos/peppeppa/` (the user followed those). Fixed in
   `CLEAN_INSTALL_PLAN.md`; the roles are path-independent (`playbook_dir`).

Not repo defects, user steps still open: Nextcloud client login (so
`~/Documents`, the scratchpad file, is empty), Wi-Fi/eduroam/VPN profiles.

## 4. Desktop

Automated in the live session (one-shot uinput device, IPC, `hyprctl`):

| Test | Result |
|---|---|
| Close policy: OS menu, power menu, Appearance, Firewall, Snapshot, Updater, Scratchpad, Cheatsheet - open / Escape / Super+Q / click outside | 32/32 |
| Super+Q with an app behind an overlay closes only the overlay; without overlay closes the app | 4/4 |
| Clipboard round trip + cliphist entry (test entries deleted) | ok |
| Notification (`notify-send`, server = Quickshell) | ok |
| Region screenshot (grim), slurp present | ok |
| Theme dark -> light -> dark, GTK `color-scheme` follows | ok |
| Lock (`loginctl lock-session`) -> hyprlock -> unlock with the password | ok, faillock 0 |
| Processes: 1 Hyprland, 1 Quickshell, hyprpolkitagent, hypridle, clipboard watcher; portals hyprland + gtk; no mako/dunst | ok |
| Fonts (FiraCode Nerd, Adwaita Sans, Noto Color Emoji), Adwaita cursor, Papirus icons, `QT_QPA_PLATFORMTHEME=xdgdesktopportal` | ok |
| Binaries: Ghostty, Nautilus (Thunar retired by design), Chromium, nvim, IntelliJ + LocalSend (Flatpak), yay, all repo helpers | ok |
| Audio controls (volume, mute, restore) | ok |
| Coffee | IPC answers `on` - found switched on, left as the user set it |
| `repo-healthcheck` | HEALTHY (incl. QML runtime, Hyprland config, session env/locale) |

Not tested by me (need the user's eyes or actions): visual look of bar and
popups, the network/Bluetooth popups with real connections, the polkit
password dialogs (firewall change, snapshot delete) - H7/H8.

## 5. Hardware

| Item | Result |
|---|---|
| Display | eDP-1 AU Optronics 1920x1080@60, scale 1 |
| Graphics | i915, VA-API (`libva-intel-driver`) |
| Ethernet | enp0s25 via dock, up, default route |
| Wi-Fi | Intel, radio on, scan sees 2.4 + 5 GHz networks; **no connection tested** (no profile/password on the new system) |
| WWAN | Sierra EM7345 present, down (unused) |
| Bluetooth | hci0 powered, not blocked; no pairing tested |
| Audio | HDA Intel PCH: built-in sink + source; HDMI card present |
| Brightness | `intel_backlight` 50% -> 100% from the session (logind); from SSH refused by design (not the active session) |
| Keyboard / pointer | AT keyboard (layout `de`), ThinkPad extra buttons, Synaptics touchpad, TrackPoint |
| Power | BAT0 97%, full 55.3 Wh (capacity 55.6%), AC online; power-profiles-daemon: performance (AC) / balanced / power-saver |
| Suspend config | logind lid -> suspend, docked -> ignore; `mem_sleep` deep; **not suspended** |
| USB | dock, integrated camera, LTE modem detected (`lsusb` not installed; sysfs) |
| LocalSend | Flatpak installed; firewall UDP 53317 (multicast) + TCP 53317 open |

## 6. Security

| Item | Result |
|---|---|
| SSH | key only (`sshd -T`: password + kbd-interactive no); password and root logins refused from the controller; reachable over Ethernet |
| Firewall | table `inet workstation` only, policy drop; repo rules exactly DHCP, DHCPv6, LocalSend UDP/TCP, SSH (rules.json v2, 5 enabled) |
| Polkit | firewall.manage `auth_admin_keep`, firewall.status `yes`, snapshot.create `yes`, snapshot.delete `auth_admin_keep`, snapshot.restore `auth_admin`; no extra rules |
| PAM | `/etc/pam.d/polkit-1` with `authtok_err=die` (P1 fix); healthcheck "polkit PAM stack" PASS |
| faillock | 0 after every test |
| Docker | group exists, no members; session groups without it; docker/socket/containerd disabled + inactive; `ip_forward` 0, redirects 0 |
| Snapshots mount | `/.snapshots` `nosuid,nodev` |
| Helpers | `/usr/local/{bin,lib,libexec}` root-owned, nothing group/world-writable |
| pacman | `SigLevel = Required DatabaseOptional` |
| Repository | secret scan of the diff clean; no disk serial (`tests/clean-install.py`) |

## 7. Snapshot and recovery readiness

| Item | Result |
|---|---|
| snapper | config `root`, no timeline, number cleanup, `snapper-cleanup.timer` enabled |
| Pre-transaction hook | one snapshot per transaction (#14 `upgrade=yes`, #15), retention kept 2 other (#12, #15) + baseline #13 |
| Manual slot create (as the dialog: `pkexec snapshot-create set 3`, no password) | snapshot #16/#17 created, no polkit window |
| Boot entry generation | `workstation-snapshot-17.conf`, UKI copy `/EFI/workstation/snapshots/7.2.9-arch1-1.efi` exists, listed by `bootctl`, cmdline `rootflags=subvol=@snapshots/17/snapshot ... workstation.snapshot=17` |
| Protected slot | a second create into occupied slot 3 refused ("overwrite it only after confirming"), `delete` through the create name refused |
| Delete (`system-snapshot --delete-slot 3 N`) | entry + snapshot removed, slots empty, update entry #14 kept |
| Overlay hook, resync unit (`ConditionPathExists` flag), sync unit, snapper plugin, recovery helpers | installed, enabled as designed |
| Healthcheck | snapshot storage/cleanup/retention/slots/boot entries/kernels/ESP PASS |

Minor finding (not a repo defect): after one of the two slot deletions snapper
left an **empty** directory `/.snapshots/17` (subvolume and `info.xml` gone,
snapper list clean); the other deletion left nothing. Our tools never write
there. Removed with `rmdir`. Watch for it in later deletions.

## 8. Regression tests added

| Test | Detects |
|---|---|
| `tests/lazyvim-extras.py` | a created `lazyvim.json` LazyVim would double / misread as an old install |
| `tests/clean-install.py` (CLI section) | a CLI tool promised by `system_architecture.md` without an installing role |

`tests/run.sh`: all checks passed (controller and laptop).

## 9. Changes and commits (`clean-install-acceptance-v1`)

| Commit | Change |
|---|---|
| `ccb9016` | apps: create lazyvim.json with LazyVim's version keys |
| `62c10b3` | bluetooth: install bluez-utils |
| (this report) | checklist path + status, report, checklist/AGENTS status |

## 10. Deployment status

Deployed to the laptop from the branch (`./bootstrap.sh`, second run
changed=0). The Neovim repair was applied by the role's own script before
the bootstrap, which then reported it unchanged. Nothing touches boot, LUKS,
PAM, SSH or the firewall - no separate safety review needed.

## 11. Remaining defects

None open in the repository. Upstream/minor: snapper's leftover empty
directory (section 7).

## 12. Deferred supervised tests (need the user / approval)

| # | Test | Needs |
|---|---|---|
| H5 | SSH over Wi-Fi | a Wi-Fi profile (the user's password) |
| H7 / H8 | firewall change and snapshot delete through the polkit dialog: cancel = unchanged, faillock 0 | the user at the laptop |
| H9 | lid suspend / resume | approval to suspend |
| H10 | visual check of bar, popups, Wi-Fi/Bluetooth/audio with real devices | the user |
| H11 | a real `system-update` with pending updates + reboot | approval to reboot |
| H12 | snapshot boot round trip from the menu | approval to reboot |
| H13 | permanent restore + resync | separate approval |
| H14 | LUKS recovery key + header backup (`LUKS_RECOVERY_PLAN.md`) | separate approval, the user types the secrets |
| - | eduroam / THWS VPN / Nextcloud on the new install | the user's credentials |

## 13. Final state

`repo-healthcheck`: **HEALTHY** after all tests. faillock 0. SSH reachable
(Ethernet). Test files and the test device removed.

## 14. Recommendation

The clean install reproduces the system from the public repository: one
bootstrap plus a second idempotent run, nothing installed by hand. The two
fresh-install defects are fixed. **Do not declare the stable release yet**:
H9, H11-H14 and the user checks in section 12 are mandatory gates
(`RELEASE_ACCEPTANCE_V1_CHECKLIST.md` section 7). Merge the branch to `main`
after review; SSH stays open until those gates pass.

## 15. Hardware Acceptance v2, round 1 (2026-10-14 afternoon, the user at the laptop)

Kinds: **A** = automated / CLI by the agent, **U** = confirmed by the user at
the laptop (GUI, eyes, ears, password). No reboot, suspend, snapshot boot,
restore or LUKS change; SSH reachable throughout; faillock 0 at the end.

| # | Result | Evidence |
|---|---|---|
| H5 Wi-Fi + SSH | **PASS** | A: Intel 7260 (`iwlwifi`, fw 17), not rfkilled, NetworkManager + wpa_supplicant active. U: connected through the bar's network popup, password typed by the user; profile stores it system-wide (`psk-flags 0`). A: the home LAN's Wi-Fi, connectivity full, DNS, HTTPS 200 over `wlp3s0`, 0 % ping loss; SSH with the key to the Wi-Fi address OK, password + root refused; firewall `tcp dport 22` has no interface restriction. First network tried was a separate subnet the LAN does not route to (controller could not reach its gateway) - topology, not the laptop. Note: replies leave by Ethernet (same subnet, lower metric) - pure-Wi-Fi only with Ethernet unplugged, not done |
| H7 Firewall polkit | **PASS** (+ 1 defect fixed) | U+A: dialog appears for a protected change (cache expired, `pkcheck` 2); Cancel -> `rules.json` + nft byte-identical, faillock 0; wrong password -> "authentication failure", retry offered, counted **once** in faillock (the cancel after it not), "Not authorized - the firewall was not changed"; right password -> add/remove applied, then ~5 min without prompt (`auth_admin_keep`). Rule really applied: `cia-test` TCP 49999 enabled -> `tcp dport 49999 accept` in the kernel, a test listener answered from the LAN on both addresses; disabled -> nft byte-identical to the baseline, connection dropped while the listener still ran; deleted -> `rules.json` + nft = baseline. SSH rule never touched |
| H8 Snapshot polkit | **PASS** | A (read only first): slot 1 = the user's #16 "init" - never touched. U: Create Snapshot into free slot 3 (`cia-delete-test`, #17) without a password, boot entry at once; Delete -> password dialog -> Cancel: slot unchanged, "Delete failed: Not authorized (polkit) - nothing was changed", faillock 0; Delete with the password -> exactly `snapshot-delete delete 3 17`, entry removed, #16/#14 kept |
| H10 Visual + hardware | **PASS** for: session, display, launcher/windows, theme/icons, audio output, brightness, touchpad/keyboard, notifications; **NOT TESTED**: microphone with speech, Bluetooth with a real device | A: eDP-1 1920x1080@60 scale 1; bar + OS menu screenshots checked (Retro 82, icons, sharp); speaker -> internal mic loopback: 1 kHz +40 dB (x110) during a tone; Bluetooth discovery found 17 devices; brightness + volume/mute from the session; touchpad + TrackPoint detected. U ("ok" to the list): notification seen, beep heard, Fn brightness, touchpad/TrackPoint/keyboard, look of apps. No evidence for the speech recording (`~/voice.wav` missing) or a pairing (no paired device) -> not counted |

**Defect fixed - firewall Add/Edit lost its input** (`df6348e`). Repro: Firewall
-> Add -> fill in -> Add -> password window -> Cancel (or a wrong password):
the dialog came back empty and without the reason. Cause: `AddRule.qml`
reset fields and message in `onVisibleChanged`; since Hardening v1.1 the
window hides itself while polkit asks, so the re-show reset it. Now it
resets only when opened (`opened` = the window's `addOpen`).
`tests/qml-logic.qml` checks it (fails without the fix). Deployed
(`./bootstrap.sh --tags quickshell`, live reload, Quickshell pid unchanged);
the user confirmed input + "Not authorized" stay after a wrong password.

**Observation - internal microphone level**: at the default source volume
100 % the internal mic clips heavily on background noise (19-76 % of samples
at full scale in two "quiet" recordings; 80 %: no clipping). The repository
sets no input level (WirePlumber's default). Not changed: whether speech is
distorted needs the speech recording (H10 open item) - no speculative fix.

**Observation - snapper leaves an empty `/.snapshots/<n>`** after every
`snapper delete` (5 of 5 probes, snapper 0.13.2); the next `create` removes
it and takes the next free number (collision probe: leftover 17 -> new #18).
Harmless, upstream behaviour; replaces the "minor finding" of section 7.

Still open from section 12: H9 (suspend), H10 microphone speech + Bluetooth
device, H11-H14.

## 16. Hardware Acceptance v2, round 2 (2026-10-14, 13:55-14:25)

The user ran the remaining physical tests on their own ("alles getestet und
geht"); the agent verified each from the journal afterwards, then ran H11.

| # | Result | Evidence |
|---|---|---|
| H9 lid suspend / resume | **PASS** (U + journal) | 13:59:15 lid closed -> hypridle started hyprlock -> `PM: suspend entry (deep)`; 14:08:27 lid opened, resumed |
| H10 microphone speech, Bluetooth device | **PASS** (U only) | confirmed by the user; no artefact left (no `~/voice.wav`; pairing data lives in `/var/lib/bluetooth` on `@` and went with the restore below) |
| H12 snapshot boot | **PASS** (U + journal) | boot -1 with `rootflags=subvol=@snapshots/14/snapshot ... workstation.snapshot=14`, overlayfs root |
| H13 permanent restore | **PASS** (U + journal) + 1 defect | from the snapshot boot: `pkexec snapshot-restore 14` (password) -> `system-rollback`: @ = #14, old @ kept as `@broken-20261014-140947`; next boot: resync unit ran, boot menu #16 + #14, HEALTHY |
| H11 real system-update | **PASS** (A) | after the restore `uv` was pending again: `system-update` (real pty, sudo once) -> pre-update snapshot #17 (boot menu), `pacman -Syu` (uv, electron43), UKI check, healthcheck HEALTHY. Reboot after it not repeated (two real boots today) |

**Defect fixed - a restored pacman-hook snapshot blocked every update**
(`2c6beef`). Repro: boot an update snapshot from the boot menu (one the
pacman hook took, e.g. "pacman: uv"), restore it, reboot, run
`system-update`: "pacman is running (or /var/lib/pacman/db.lck is stale)";
`./bootstrap.sh` would fail at `pacman -Syu` the same way, and
`repo-healthcheck` still said HEALTHY. Cause: the PreTransaction hook
snapshots while pacman holds `db.lck` - #12, #14, #15 contain it, #13
(baseline) and #16 (manual) do not. Fix: `system-rollback` removes the lock
from the new @ before the switch (nothing runs there yet);
`repo-healthcheck` FAILs "pacman lock" on a lock without a running pacman.
Tests: `tests/system-rollback.sh` (fails without the fix),
`tests/healthcheck-pacman-lock.py`. On the laptop: the stale lock removed
by hand once (no pacman running, lock dated 12:44:14 = the snapshot), new
helpers deployed, live check with a fake lock: FAIL, removed: PASS.

After the restore the system was at 12:44 (R7): the bootstrap brought back
`bluez-utils` and the new helpers (changed=4 incl. handlers), the second run
**changed=0**. The old system `@broken-20261014-140947` stays until the
user removes it (`system-rollback` prints the two commands).

Also reset by the restore (expected - `/etc` and `/var/lib` are on `@`): the
home Wi-Fi profile (Wi-Fi SSH unreachable afterwards until it is saved again)
and the Bluetooth pairing. README "Booting a snapshot and restoring it" now
says so.

Agent mistakes in this round, both corrected at once: two `sudo` calls with
empty input (a loop and a stray command) added one faillock entry each -
reset to 0.

**Status after round 2**: H1-H13 PASS. Open: **H14** (LUKS recovery key +
header backup, `LUKS_RECOVERY_PLAN.md`) - the user types the secrets.
