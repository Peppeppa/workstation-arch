# Release Acceptance v1 - checklist

Gate list for the first stable release. **The release is NOT declared
before every mandatory row is PASS.** The final acceptance target is a
genuine clean install of the physical ThinkPad T440p
(`CLEAN_INSTALL_PLAN.md`); evidence from the current (development)
installation counts as pre-acceptance only.

Kinds: **A** = automatic (`tests/run.sh`, static/mocked), **HW** = real
hardware, **VM** = disposable VM, **U** = needs the user (input, password,
eyes), **D** = destructive / separately approved.
Status: PASS (evidence, date) - PRE (passed on the current install, must be
repeated after the clean install) - OPEN - DEFERRED - N/A.

## 1. Installation base (archinstall, `CLEAN_INSTALL_PLAN.md`)

| # | Requirement | Kind | Status |
|---|---|---|---|
| I1 | prerequisites: UEFI, Arch ISO (signature checked), network, sudo user, git + ansible | A | PASS - README "Requirements", checklist section 0-2 |
| I2 | target = the 238.5 GiB `LITEONIT LCS-256M6S`; the 512 GB Fedora disk never selected | A + U | PASS (checklist, `tests/clean-install.py`) |
| I3 | archinstall settings give: GPT, 1 GiB FAT32 ESP at `/boot`, LUKS2 (`encrypt` hook, `cryptdevice=PARTUUID`), Btrfs `@ @home @log @pkg`, fstab without `subvolid=`, systemd-boot + UKI `arch-linux.efi`, `rootflags=subvol=@`, zram, hostname `laptop`, wheel user | A | PASS - checked against the archinstall 4.5 source and the roles 2026-10-14 |
| I4 | the same on the installed system (checklist step 3 "Check") | HW + U | OPEN |
| I5 | `@snapshots @recovery` created by `roles/recovery` | HW | OPEN |
| I6 | an actual clean install on the T440p | D + U | **OPEN - the user's own step** |

## 2. Bootstrap and deployment

| # | Requirement | Kind | Status |
|---|---|---|---|
| B1 | `./bootstrap.sh` from a TTY, no credentials, public HTTPS clone | A | PASS (code review; real phase-1 runs 2026-10-08) / OPEN on the clean install |
| B2 | non-Arch refused (debian, cachyos, omarchy) before Ansible; playbook assert as second guard | A | PASS 2026-10-14 (bwrap with fake os-release) |
| B3 | not as root | A | PASS (code) |
| B4 | exactly one `pacman -Syu` per run; roles `state: present` only | A | PASS (`local.yml`, AGENTS.md) |
| B5 | pacman `SigLevel = Required DatabaseOptional`, never changed by a role | A + HW | PASS 2026-10-14 (laptop `pacman.conf`; no role writes SigLevel) |
| B6 | `--noconfirm` (system-update) does not bypass signatures/trust or conflict refusal | A | PASS (pacman: --noconfirm takes the default answer; conflicts default to No, signature trust is not a prompt) |
| B7 | check mode (`--check --diff`) reflects expected changes | HW + U | DEFERRED - needs the sudo password; run during the clean install |
| B8 | second run changed=0 | HW + U | PRE (2026-10-14 hardening deploy); OPEN on the clean install (H3) |
| B9 | runtime does not depend on Ansible (helpers, polkit, units) | A | PASS (AGENTS.md ownership table; helpers in /usr/local) |
| B10 | no secret required by phase 1; phase 2 separate (Bitwarden) | A | PASS (`tests/private-handover.sh`, README) |
| B11 | privileged files root-owned, not group/world-writable | HW | PASS 2026-10-14 (`/usr/local/{bin,lib,libexec}`, policies, units, PAM) |
| B12 | AUR builds pinned (yay, networkmanager-fortisslvpn) | A | PASS (roles/packages, roles/network) |

## 3. Desktop (HW + U; GUI)

| # | Requirement | Status |
|---|---|---|
| E1 | Ly -> Hyprland session, one Quickshell | PRE 2026-10-14 (post-reboot, healthcheck) |
| E2 | bar, OS menu, launcher, panels, close policy | PRE (66/66 close-policy 2026-10-11, 8/8 2026-10-14) |
| E3 | terminal, Nautilus, Chromium present | PRE 2026-10-14 (binaries); launch = H10 |
| E4 | notifications (Quickshell owns the bus name) | PRE 2026-10-14 |
| E5 | clipboard + history | PRE 2026-10-14 (wl-copy/wl-paste round trip, cliphist watcher) |
| E6 | screenshots | PRE (earlier hardware tests) |
| E7 | theme switch, GTK/Qt light/dark | PRE (RICE v1) |
| E8 | lockscreen, idle lock, Coffee | PRE 2026-10-14 (idle lock active, Coffee IPC) |
| E9 | audio, Wi-Fi, Bluetooth | PRE (Stage 1; sink present 2026-10-14) |
| E10 | Firewall UI (auth), Snapshot UI (auth), update dialog, power/logout dialogs | PRE (Hardening v1.1, Bug Hunt v1) |
| E11 | all of the above on the clean install | **OPEN (H10)** |

## 4. Update, snapshots, recovery

| # | Requirement | Kind | Status |
|---|---|---|---|
| F1 | update check (private DB copy) | HW | PASS 2026-10-14 (`workstation-checkupdates` status ok) |
| F2 | stale pacman lock refused; one system-update at a time | A | PASS (`tests/system-update.sh`; `db.lck` refusal, flock) |
| F3 | package conflict / failed transaction handling | A | PASS (mocked, `tests/system-update.sh`) |
| F4 | pre-update snapshot, retention 2 update + 2 other | A + HW | PASS (tests); PRE (update 2026-10-13, healthcheck retention 2026-10-14) |
| F5 | manual slots: create passwordless, delete/overwrite with password | A + HW + U | PASS (tests); PRE (Hardening v1.1 GUI) |
| F6 | boot entries + matching UKI copies | A + HW | PASS (tests); PRE 2026-10-14 ("every entry: kernel = its UKI copy") |
| F7 | snapshot boot protections (overlay, pacman blocked) | HW | PRE (round trip 2026-10-13) |
| F8 | permanent restore: validation, guarded switch, failure injection | A | PASS (`tests/system-rollback.sh`: success, failure between renames, UKI build failure, missing UKI) |
| F9 | post-restore resync unit | A | PASS (static review, flag/condition) |
| F10 | real permanent restore + resync on hardware | D + U | **DEFERRED** - procedure in the report section 7; separate approval |
| F11 | snapshot boot round trip on the clean install | HW + U | OPEN (H12) |

## 5. Security

| # | Requirement | Status |
|---|---|---|
| S1 | no secrets in the repository | PASS 2026-10-14 (scan) |
| S2 | SSH key-only; root refused | PASS 2026-10-14 (drop-in, `root@` -> publickey denied) |
| S3 | firewall mutations need auth, status passwordless | PASS (tests) / PRE (GUI 2026-10-14 night; status passwordless after reboot 2026-10-14) |
| S4 | snapshot delete/overwrite need auth | PASS (tests) / PRE |
| S5 | no docker group (account + session), Docker disabled, no Docker side effects after reboot | PASS 2026-10-14 post-reboot |
| S6 | polkit cancel not counted (P1), faillock counting intact | PASS (tests) / PRE; faillock 0 |
| S7 | `/.snapshots` nosuid,nodev | PASS 2026-10-14 (mount options) |
| S8 | theme input validation | PASS (tests) |
| S9 | signature verification | PASS (B5) |
| S10 | helper/unit permissions | PASS (B11) |
| S11 | SSH + LocalSend reachable | ACCEPTED (user decision until the end of acceptance) |
| S12 | LUKS recovery (2nd keyslot, header backup) | DEFERRED - `LUKS_RECOVERY_PLAN.md` (H14) |

## 6. Documentation

| # | Requirement | Status |
|---|---|---|
| Doc1 | install checklist archinstall -> bootstrap | PASS (`CLEAN_INSTALL_PLAN.md`) |
| Doc2 | LUKS recovery | PASS (`LUKS_RECOVERY_PLAN.md`, new) |
| Doc3 | restore procedure incl. re-applying the bootstrap afterwards | PASS (report section 7) |
| Doc4 | README/AGENTS.md match the repository | PASS (updated 2026-10-14) |
| Doc5 | `BOOTSTRAPPER.md` | N/A - does not exist; the bootstrap is documented in README "Quickstart" |

## 7. Mandatory gates for "stable"

I6 (clean install), B7, B8/H3, E11/H10, F10 (or an explicit user decision
to release with the restore deferred), F11, H1-H9 (section 8), S12 (or an explicit deferral by the
user). SSH is closed only after all of these.

## 8. Hardware acceptance after the clean install

| # | Test | Pass |
|---|---|---|
| H1 | `bootctl status` Current Entry `arch-linux.efi`; `findmnt /` = `[/@]` | as stated |
| H2 | `repo-healthcheck` in the session | HEALTHY |
| H3 | second `./bootstrap.sh` | changed=0 (roles); recovery baseline snapshot exists |
| H4 | `swapon --show` | `/dev/zram0` prio 100 |
| H5 | SSH over Ethernet and Wi-Fi; password and root refused | key-only |
| H6 | `getent group docker`; `docker ps` as the user | not a member; denied |
| H7 | Firewall change: cancel = unchanged, faillock 0; password = applied, ~5 min cache; status passwordless | as Hardening v1.1 |
| H8 | Create Snapshot passwordless; Delete/Overwrite ask, cancel = unchanged | as Hardening v1.1 |
| H9 | lock/unlock, idle lock, lid suspend/resume | faillock 0 |
| H10 | desktop rows E1-E10 | user + GUI tests |
| H11 | one real `system-update` with pending updates | snapshot + entry, healthy after reboot |
| H12 | snapshot boot round trip from the menu | old state, pacman blocked, back to @ |
| H13 | permanent restore + resync (report section 7) | separate approval |
| H14 | LUKS second keyslot + header backup (`LUKS_RECOVERY_PLAN.md`) | separate approval |
