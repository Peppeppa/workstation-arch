# Release Acceptance v1 - report

2026-10-14. ThinkPad T440p (`laptop`), after the user's reboot following
Security Hardening v1.1. Branch `release-acceptance-v1` (from `main`
`c899617`). Mid-batch the user decided that the **final acceptance is a
genuine clean install of this ThinkPad**; this batch therefore prepares that
install and does not execute it.

**Update (same day, simplification requested by the user)**: the install is
archinstall + `./bootstrap.sh`, nothing custom. `CLEAN_INSTALL_PLAN.md` is
now one screen-by-screen archinstall checklist, checked against the
archinstall 4.5 source (default Btrfs subvolumes `@ @home @log @pkg`, ESP
1 GiB at `/boot`, busybox `encrypt` + `cryptdevice=PARTUUID`,
`rootflags=subvol=@`, UKI `/boot/EFI/Linux/arch-linux.efi`, loader
`timeout`, sudo user in `wheel`). Corrections to this report: **R4 was
wrong** - `genfstab` (arch-install-scripts 31) already drops `subvolid=`
when `subvol=` is present; the guard added for it was removed again. R3:
archinstall itself enables the `timeout` line - the role owns it anyway so
the snapshot menu does not depend on the installer. New: archinstall also
builds a fallback UKI, which a restore would leave with the newer kernel -
the checklist removes it (the laptop's preset already was `default` only).
The disk serial number is no longer in any document; the branch was
squash-merged into `main`.

Evidence levels used below: **HW** = measured on the real laptop today;
**HW-earlier** = real hardware evidence from an earlier batch (named);
**A** = automatic / static / mocked tests; **plan** = written, not run.

## 1. Executive summary

- **The release is not declared.** The mandatory gates (checklist section 7)
  need the clean install, which needs the user's separate approval of the
  target disk - the clean install is the user's own step (the archinstall checklist).
- Post-reboot state verified on hardware: HEALTHY, booted on `@`, SSH over
  Ethernet and Wi-Fi, no `docker` group in the account **and** the new
  session, Docker never started this boot, firewall = the five standard
  rules, faillock 0, no failed units.
- Clean-install reproducibility: the repository provisions everything
  above a base layer that so far existed only from the laptop's original
  archinstall run. That layer is now an archinstall checklist, and two
  pieces of laptop-only state were moved into the roles (section 4).
- Nothing destructive ran: no reboot, no partitioning, no restore, no LUKS
  change, no package transaction, SSH untouched.

## 2. Post-reboot verification (Phase A, HW, read-only, no sudo)

| # | Check | Result |
|---|---|---|
| 1 | normal boot on Btrfs `@` | `findmnt /` = `/dev/mapper/root[/@]`, booted 09:01:02 |
| 2 | systemd-boot entry | Current Entry `arch-linux.efi`, systemd-boot/-stub 262, Secure Boot off |
| 3 | root FS + options | btrfs `rw,relatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@`; `/.snapshots` `nosuid,nodev` |
| 4 | repo-healthcheck | **HEALTHY**, 41/41 PASS incl. docker access, polkit PAM stack, ICMP redirects, snapshot boot kernels |
| 5 | SSH | Ethernet and Wi-Fi both key-only, same pinned host key (the Wi-Fi address had no known_hosts entry - checked with the pinned key as alias) |
| 6 | account database | `docker:x:960:` (no members); `id medvidec` = medvidec wheel video vboxusers |
| 7 | new desktop session | Hyprland (pid 1373) and Quickshell (pid 1432), started 09:01:27/29: groups 108 983 998 1000 - **no 960** |
| 8 | unprivileged Docker | `docker ps` -> no socket (Docker not running); socket would be `root:docker 0660` with an empty group |
| 9-10 | Docker daemon / units | docker.service, docker.socket, containerd.service: disabled + inactive; no dockerd/containerd process; **0 journal lines this boot** |
| 11 | Docker interfaces / rules | links: lo, enp0s25, wlp3s0, wwp0s20u10 only; no docker cgroups. Docker's nft tables exist only while dockerd ran - it did not run this boot, so the previous incident's tables are gone (inferred; `nft list` needs root) |
| 12 | firewall | `workstation-firewall.service` enabled, active (09:01:19, status 0); `pkexec firewall-status` from the session **without a prompt**: loaded, exactly DHCP, DHCPv6, LocalSend UDP/TCP, SSH, all enabled + active |
| 13 | forwarding / redirects | `ip_forward=0`, IPv6 forwarding 0, `accept_redirects` 0 (all/default/IPv6) |
| 14 | snapshots + entries | slots #43, #44 (bootable), slot 3 empty; boot entries #48 #47 #44 #43, every UKI copy matches its kernel; ESP 784 MiB free |
| 15 | faillock | 0 (checked four times during the batch) |
| 16 | units | `systemctl --failed` empty (system + user), `is-system-running` = running; boot errors only harmless (TDX/kvm_amd probes, wpa_supplicant multicast, gkr-pam control file) |
| 17 | auth / network regressions | no sudo/polkit/sshd failures in the journal; NetworkManager connectivity full on both links |

## 3. Release checklist

`docs/release/RELEASE_ACCEPTANCE_V1_CHECKLIST.md` - 60+ rows by kind
(automatic / hardware / VM / user / destructive) with status. Summary:
automatic and static gates PASS; hardware gates PRE (passed on the current
install, to repeat after the clean install); the clean install itself, check
mode, the real restore and LUKS recovery OPEN/DEFERRED.

## 4. Clean-install reproducibility

Read-only inventory of the laptop (disks, fstab, cmdline, mkinitcpio,
bootloader, users, pacman.conf, explicit packages, enabled units, NM
profiles, modified/unowned `/etc` files) against the repository:

- **Explicit packages not declared by a role**: `base linux linux-firmware
  intel-ucode btrfs-progs mkinitcpio sudo efibootmgr wpa_supplicant ansible`
  (base layer - archinstall), `zram-generator` (now
  `roles/power`), `flatpak`/`pkgconf`/`networkmanager-fortisslvpn` (installed
  by role tasks), `claude-code` (the user's runtime choice).
- **Unowned `/etc` files** not from the repository: only
  `zram-generator.conf` (fixed below); all others are written by roles.
- **Modified package files**: fstab, passwd/group/shadow, locale.gen,
  mkinitcpio.conf, pacman.conf (Color, ParallelDownloads = archinstall),
  mirrorlist, ly config, snapper conf.d - base layer or role-owned.

| ID | Finding | Class | Resolution |
|---|---|---|---|
| R1 | The base layer (GPT, LUKS2, Btrfs subvolumes, cmdline, HOOKS, UKI preset, bootloader, user, sudoers) is assumed by `roles/recovery` but documented nowhere - a clean install could not be reproduced from the repository | BLOCKER (doc) | `CLEAN_INSTALL_PLAN.md` + README requirement; `tests/clean-install.py` checks the plan against the role guards, the UKI path of recovery-lib and host_vars |
| R2 | zram swap came from archinstall: a clean install would have **no swap** | MAJOR | `roles/power` owns `zram-generator` + `/etc/systemd/zram-generator.conf` (content identical to the laptop's) |
| R3 | `loader.conf` `timeout` came from archinstall: after a fresh `bootctl install` the menu is hidden, snapshot entries reachable only with a held key | MAJOR | `roles/recovery` sets `timeout {{ recovery_boot_menu_timeout }}` (3) next to `default` |
| R4 | ~~`genfstab` writes `subvolid=`~~ - withdrawn: genfstab removes it when `subvol=` is set | - | guard removed again |
| R5 | `~/.ssh/authorized_keys` exists only on the laptop | DOC | it is one of the public keys at github.com/Peppeppa.keys (fingerprint verified); the plan installs exactly that key by fingerprint |
| R6 | `BOOTSTRAPPER.md` (named in the task) does not exist | DOC | README Quickstart is the bootstrap documentation |

Not reproduced on purpose (user state): Wi-Fi/eduroam/VPN profiles,
Bitwarden, Nextcloud data, Flatpak apps the user added, theme/bar choices.

**Disposable VM / container**: no clean install was performed. The
controller host is Omarchy (the bootstrap refuses it, correctly); no
disposable VM was created (none was approved, and a container cannot show
LUKS/bootloader/first boot). Clean-install acceptance = **OPEN**, to be done
on the T440p itself per the plan.

## 5. Bootstrap acceptance

| Check | Result | Level |
|---|---|---|
| distro guard | `bootstrap.sh` with a fake `/etc/os-release` (bwrap): debian, cachyos, omarchy refused before Ansible; `ID=arch` / `ID="arch"` pass to `ansible-playbook`; the playbook's own assert is a second guard | A |
| not as root, git/ansible required | code review | A |
| one `pacman -Syu`, roles `state: present` | `local.yml` | A |
| signature verification | laptop `SigLevel = Required DatabaseOptional`; no role writes SigLevel; `--noconfirm` answers prompts with their default - conflicts default to No (abort), trust is not a prompt | HW + A |
| check mode / idempotence | **DEFERRED** - needs the sudo password, not available in this session; last real: hardware deploy 2026-10-14 night changed=9 then 0 | HW-earlier |
| privileged file permissions | all helpers, libraries, policies, units, `/etc/pam.d/polkit-1` root-owned, no group/world write; `rules.d` root:polkitd 0750 | HW |
| secrets | phase 1 none; phase 2 Bitwarden only; diff + tree scanned | A |

## 6. Desktop acceptance

On the current install (HW, read-only): one Hyprland 0.56.2 instance, eDP-1
1920x1080@60 scale 1; Quickshell IPC targets present (coffee, osmenu, bar,
firewall, snapshot); Coffee status `off`; theme state retro-82/dark valid;
PipeWire sink present; hypridle, hyprpolkitagent, clipboard watcher
running; notifications owned by Quickshell; clipboard round trip through
`wl-copy`/`wl-paste` (test entry removed from cliphist afterwards); ghostty,
nautilus, chromium, nvim, grim, slurp present, LocalSend as Flatpak; idle
lock engaged (hyprlock running - SSH tests unaffected).

**Not re-run**: the uinput GUI regression tests (they need sudo for the
one-shot input device, and the session was idle-locked). Hardware evidence
is HW-earlier (RICE v1 66/66 close policy, Hardening v1.1 GUI auth tests
8/8, Bug Hunt v1). The full desktop list is gate H10 after the clean install.

## 7. Update and snapshot acceptance

| Item | Result | Level |
|---|---|---|
| update check | `workstation-checkupdates`: status ok, pending updates listed | HW |
| stale lock / concurrency | `db.lck` refusal, flock - `tests/system-update.sh` | A |
| conflicts / failed transactions, pre-update snapshot, retention | `tests/system-update.sh`, `tests/recovery-snapshots.sh` | A; HW-earlier (update 2026-10-13) |
| manual slots + authorization | `tests/system-update.sh`, `tests/privileges.py`; GUI | A; HW-earlier (Hardening v1.1) |
| entries + matching UKIs | `tests/snapshot-boot.py`; healthcheck today | A; HW |
| snapshot boot protections | round trip 2026-10-13 - not repeated | HW-earlier |
| restore validation + guarded switch | `tests/system-rollback.sh`: success; failure between the renames -> old @ back; UKI build failure -> unchanged; kernel without UKI -> refused | A |
| resync logic | static review: flag written only into the NEW @ by system-rollback; unit `ConditionPathExists`, `RequiresMountsFor=/boot /.snapshots`; flag removed only after a successful sync (a failed sync retries next boot); snapshot-boot.json of the old view dropped | A |
| real permanent restore + resync on hardware | **DEFERRED** (procedure below) | - |

**Finding R7 (DOC, restore)**: every existing snapshot (#43, #44, #47, #48)
predates the security fixes - checked read-only: each still has
`docker:...:medvidec` in `/etc/group` and no `/etc/pam.d/polkit-1`.
Restoring one reverts S4 and P1 (and S3) until `./bootstrap.sh` runs again;
repo-healthcheck then FAILs "docker access" and "polkit PAM stack", so it is
visible. After the clean install, new snapshots carry the fixes; the
procedure below re-applies the bootstrap anyway.

### Supervised procedure E1 - permanent restore (after the clean install, separate approval)

Preconditions: HEALTHY; faillock 0; SSH on both paths; ESP free > 150 MB;
the user at the laptop (LUKS unlock, polkit password); slot 3 empty.

1. `date > ~/restore-marker-home` (must survive). Create Snapshot ->
   slot 3, label `restore-test` (no password). Note its number N.
2. `sudo touch /etc/restore-marker-after-snapshot` (must disappear).
3. Reboot -> boot menu (3 s) -> "snapshot N"; LUKS unlock.
4. Snapshot mode: `snapshot-boot status`, the strip is shown; dialog ->
   "Restore permanently" -> polkit password -> result `{"ok": true,
   "snapshot": N, "previous": "@broken-..."}`.
5. Before rebooting: `journalctl -t system-rollback -t snapshot-restore -b`;
   faillock 0.
6. Reboot -> default entry; LUKS unlock.
7. Verify: `findmnt /` = `[/@]`; `/etc/restore-marker-after-snapshot`
   absent; `~/restore-marker-home` present; `journalctl -b -u
   workstation-snapshot-boot-resync` = one run, success;
   `/var/lib/workstation/snapshot-boot.resync` gone; `snapshot-boot status`
   synced after this boot; healthcheck "last snapshot restore" = N, WARN for
   `@broken-*` only; SSH on both paths.
8. `./bootstrap.sh` -> succeeds, (near) zero changes.
9. Cleanup (approved): delete slot 3 (password), remove `@broken-*` with the
   commands system-rollback printed.

Abort / recovery: no boot after step 6 -> the boot menu's snapshot entries
(still listed) or the Arch ISO: `mount -o subvolid=5`, `mv @ @failed; mv
@broken-<stamp> @`, the old UKI is in `/boot/EFI/workstation/broken/`
(recovery-design 15).

## 8. Security acceptance

| Property | Result |
|---|---|
| no secrets in the repository | diff + tree scan clean; the new docs name no Wi-Fi SSID/LAN IP; no passphrase, key or header anywhere |
| SSH key-only | drop-in `PubkeyAuthentication yes / PasswordAuthentication no / KbdInteractiveAuthentication no`; `root@localhost` with password -> `Permission denied (publickey)` |
| root SSH | package default `prohibit-password`, root has no key -> refused. MINOR (R8): `PermitRootLogin no` would make it explicit - not changed (SSH closing is the user's later step) |
| firewall / snapshot authorization | tests PASS; status passwordless after the reboot (HW) |
| docker group removal | HW (section 2) |
| polkit cancel / PAM accounting | healthcheck PASS; `tests/pam-polkit.sh` PASS |
| `/.snapshots nosuid,nodev` | HW |
| theme input validation | `tests/theme-helper.sh` PASS |
| pacman signatures | section 5 |
| helper / unit permissions | section 5 |
| `net.ipv4.conf.all.send_redirects=1` | MINOR (R9): irrelevant without forwarding (`ip_forward=0`); not changed |
| SSH + LocalSend reachable | ACCEPTED (user decision) |

## 9. LUKS recovery status

`docs/release/LUKS_RECOVERY_PLAN.md`. Current: one keyslot, no header
backup, TPM **1.2** (TPM2 unlock impossible on this machine), Secure Boot
off. Recommended: a systemd recovery key as second keyslot (layout-safe
characters, works with the busybox prompt) + two offline header backups,
refreshed after every keyslot change. Mechanics proven on image files
(backup/wipe/restore, stale backup still opens a removed key, recovery key
as a plain passphrase). Implementation: after the clean install, separately
approved (H14). Nothing changed on the laptop.

## 10. Bugs found and fixed

| ID | Fix | Test |
|---|---|---|
| R2 | zram-generator owned by `roles/power` | `tests/clean-install.py` (3 checks failed before) |
| R3 | systemd-boot `timeout` owned by `roles/recovery` | `tests/clean-install.py` (failed before) |
| R1 | archinstall checklist | `tests/clean-install.py` (checklist vs. roles, no disk serial in tracked files) |

## 11. Regression results

`tests/run.sh`: all checks passed (before and after the changes; the new
`tests/clean-install.py` is part of it). Plan shell blocks: `bash -n` OK;
its `sed` edits checked on sample fstab/locale.gen/mkinitcpio.conf; the key
filter checked against the real public key list.

## 12. Hardware tests this batch

Sections 2, 5 (permissions, SigLevel), 6, 7 (update check, entries), 8 -
all read-only. Plus one passwordless `pkexec firewall-status` inside the
session. Inventory for the plan. No GUI input, no sudo, no state change on
the laptop except one clipboard entry (removed again).

## 13. Deferred

Clean install (I11) and H1-H14; Ansible check mode + idempotence on the new
install (B7/B8); the GUI regression suite on the new install (H10); real
permanent restore + resync (E1/F10); LUKS second keyslot + header backup
(H14); real update on the new install (H11).

## 14. Remaining blockers

1. Clean install not yet performed - the user's own step.
2. The changes of this branch are structurally tested only - they are
   proven by the clean install (H1-H4).

## 15. Git

`release-acceptance-v1` squash-merged into `main` (one commit; the branch's
first commit named the disk serial, so the branch was deleted instead of
merged as is).

## 16. Deployment status

Not deployed (no sudo password in this session; the clean install applies
it from scratch). The laptop stays on `c899617` until then.

## 17. Final system health

HEALTHY (09:21, post-reboot, last check of the batch), faillock 0, SSH on
both paths, no reboot, Docker inactive/disabled.

## 18. Next steps toward release

1. User: `CLEAN_INSTALL_PLAN.md` from section 0 to `./bootstrap.sh`.
2. Hardware acceptance H1-H12 (checklist section 8); H13 restore and H14
   LUKS with their own approvals.
3. Release decision; afterwards the user's separate SSH-closing step.
