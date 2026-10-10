# Recovery / Storage Design v1

Status: **implemented** (`roles/recovery`, `recovery_enabled`, laptop only)
and destructively tested on the laptop - deviations from this design and
the test results are in section 21 (as built), which wins where it differs.
Originally written as a design only (approved before any storage change). Evidence: Stage 0 audit and read-only inspection of
the ThinkPad T440p test laptop at commit `2255fe1`; `roles/power` as of the
same commit.

Snapshots are not backups. This document designs local, fast recovery of
the *system* from bad updates/deployments, and only defines the boundary
for a later backup design.

## 1. Current state (test laptop)

```
sda (SATA SSD, GPT)
  sda1  ESP, vfat 1 GiB  -> /boot   (systemd-boot 262, UKI arch-linux.efi ~42 MB,
                                     vmlinuz-linux, intel-ucode.img; 951 MB free)
  sda2  LUKS2 (aes-xts-plain64, argon2id, 1 keyslot)
          /dev/mapper/root  Btrfs (zstd:3, ssd, space_cache=v2)
            @      -> /                 (rootflags=subvol=@ in the UKI cmdline + fstab subvol=/@)
            @home  -> /home
            @log   -> /var/log
            @pkg   -> /var/cache/pacman/pkg
            @/var/lib/portables, @/var/lib/machines   (nested, created by systemd, unused)
swap: zram 4 GiB only; no disk swap
initramfs: mkinitcpio, busybox `encrypt` hook; preset `default` only (no fallback UKI)
cmdline source: /etc/kernel/cmdline (baked into the UKI by mkinitcpio -P)
Secure Boot off, no TPM2
sdb: old Fedora install - out of scope, never touched
```

Repository constraint (`roles/power`, hibernate host capability): swapfile
via `mkswap --file` (No_COW on btrfs), `resume=UUID=<unlocked fs>
resume_offset=<btrfs inspect-internal map-swapfile -r>` written into
`/etc/kernel/cmdline`, `HOOKS+=(resume)` drop-in for busybox initramfs,
`mkinitcpio -P`; it refuses other bootloader layouts and never creates
subvolumes ("btrfs: the file must be on a subvolume that is never
snapshotted, e.g. @swap at /swap").

## 2. Failure model

Recovered by this design (system rollback):

| Failure | Recovery path |
|---|---|
| broken `pacman -Syu` (bad package, partial breakage) | boot "Recovery: before update", then permanent rollback |
| broken kernel | same: the recovery slot carries the *old* kernel+initramfs together with the *old* modules tree |
| broken initramfs / UKI (mkinitcpio error, missing hook) | same - the slot's UKI is a copy of the last UKI that booted |
| broken workstation-arch deployment / bad system config / bad Hyprland or Quickshell deployment | system part: rollback of `@`; user part (~/.config) is NOT rolled back - see section 7 |
| package downgrade wanted | rollback (pacman db and files move together) or `pacman -U` from `@pkg` |
| accidental changes in system files | rollback, or copy single files out of a read-only snapshot |
| machine boots but desktop fails | TTY/SSH/recovery entry; `system-rollback` |
| root no longer boots | boot menu recovery entry; last resort Arch ISO (section 15) |

Not solved by snapshots (backup / hardware problem):

| Failure | Why |
|---|---|
| failed SSD | snapshots share the disk |
| destroyed LUKS header | everything behind it is unreadable - needs a header backup |
| destroyed ESP | the slot UKIs live there too; recoverable via Arch ISO (regenerate), not via snapshots |
| catastrophic Btrfs corruption | snapshots share extents |
| deleted/overwritten personal files in `@home` | `@home` is deliberately outside system rollback; needs backups (section 14) |
| theft, fire, hardware failure | backups off the machine |

## 3. Subvolume layout

| Subvolume | Mount | In system rollback | Reason |
|---|---|---|---|
| `@` | `/` | **yes** | the system: /usr, /etc, **/var/lib/pacman** (db and files must move together), /var/lib/* service state, /etc/kernel/cmdline |
| `@home` | `/home` | no | personal data and runtime user state (`~/.config/workstation`, `~/workstation-arch`) must never roll back with the system |
| `@snapshots` | `/.snapshots` | no (container) | flat, top-level: snapshots are never inside the tree they snapshot, a rollback never deletes or nests them, `btrfs send` sees plain read-only subvolumes |
| `@log` | `/var/log` | no | keep: logs of the broken state survive the rollback that undoes it - needed for diagnosis |
| `@pkg` | `/var/cache/pacman/pkg` | no | keep: package cache is the downgrade source and big; snapshotting it only costs space |
| `@swap` | `/swap` | never snapshotted | swapfile for hibernate (No_COW, a snapshot would make it unusable as swap) |

Not added: `@var_tmp`, `@tmp` (tmpfs), `@flatpak`, `@docker`, `@libvirt` -
no concrete need. `/var/lib/flatpak` (IntelliJ, several GB) stays in `@`:
Flatpak is provisioned by Ansible like pacman packages, so rolling it back
with the system is consistent; the cost is snapshot space on Flatpak
updates - revisit only if measured space becomes a problem.

`@/var/lib/machines` and `@/var/lib/portables`: unused nested subvolumes
created by systemd. Nested subvolumes are not part of a snapshot (they show
up as empty directories) and are left behind in the old `@` by a rollback.
Recommendation: delete them during migration (nothing uses machinectl or
portable services); systemd re-creates them as plain directories/subvolumes
on demand. *As built: kept* - systemd-tmpfiles re-creates them on every
boot, so deleting them is pointless; they stay empty and are irrelevant to
rollback (section 21).

Final tree (top level, `subvolid=5`):

```
@            -> /
@home        -> /home
@snapshots   -> /.snapshots
@log         -> /var/log
@pkg         -> /var/cache/pacman/pkg
@swap        -> /swap            (only with hibernate_enabled)
@recovery    (not mounted)       writable boot clones of recovery slots, see 5/7
```

## 4. Snapper model

- One snapper config, `root`, for `/` (`SUBVOLUME="/"`); snapshots stored
  in `@snapshots` mounted at `/.snapshots` (config written by Ansible, not
  `snapper create-config`, which would create a nested `.snapshots`).
- Snapshots are read-only.
- No timeline snapshots (`TIMELINE_CREATE="no"`): history is created by
  events (updates, manual), not by the clock.
- Cleanup: `NUMBER_CLEANUP="yes"`, `NUMBER_LIMIT="10"` (the last 5
  pre/post pairs of the older system-update; the pre-transaction class is
  outside it, section 6), `NUMBER_LIMIT_IMPORTANT="4"` (manual known-good
  snapshots carry `important=yes`), `NUMBER_MIN_AGE="0"`,
  `EMPTY_PRE_POST_CLEANUP="no"` (*as built* - `yes` deleted a pinned slot
  snapshot after a no-op update, section 21).
- No quota groups (`QGROUP=""`): qgroups cost write performance on Btrfs
  and only feed space-aware cleanup; free space is guarded by
  `system-update` instead (section 13).
- Snapshots referenced by a recovery slot are pinned (`--cleanup-algorithm
  ""`), so snapper's cleanup can never delete a bootable recovery state;
  the helper unpins on slot rotation.
- `snapper-cleanup.timer` (package unit; hourly, 10 min after boot) is the only timer added -
  it is snapper's own and does nothing between snapshot events. Needs an
  `AGENTS.md`/healthcheck exception ("no timers of ours" -> "only
  snapper-cleanup.timer").
- No `snap-pac`: see section 6 (our own pacman hook, one snapshot per
  transaction, own retention).

A separate snapper config for `@home` is not part of v1 (no rollback for
home); the backup design may add read-only home snapshots for `btrfs send`.

## 5. Bootloader / UKI decision: keep systemd-boot + UKI, add bounded recovery slots

### The problem

`/boot` is the FAT ESP. A root snapshot contains `/usr/lib/modules/<old>`
but the ESP holds only the newest UKI. Booting an old root with the new UKI
mismatches kernel and modules; booting the new root with an old UKI the
same.

### Decision

A **recovery slot** = a matching pair, created at one moment from the
*running, booted* system:

```
UKI copy        /boot/EFI/workstation/recovery/<slot>.efi
                (the UKI that booted this system, rebuilt by ukify with an
                 embedded recovery cmdline - see below)
root state      read-only snapper snapshot  @snapshots/<n>/snapshot
boot clone      writable snapshot of it     @recovery/<slot>   (what the slot boots)
boot entry      /boot/loader/entries/workstation-recovery-<slot>.conf
                (BLS Type #1, `uki /EFI/workstation/recovery/<slot>.efi`)
```

Slots (bounded, at most 3):

| Slot | Created by | Meaning |
|---|---|---|
| `before-update` | `system-update`, before pacman runs | the system as it was right before the last update |
| `known-good` | `system-snapshot --known-good "<label>"` | a state the user explicitly declared good |
| `previous-update` (optional) | rotation of `before-update` | one more step back |

Recovery UKI build: extract `.linux`, `.initrd`, `.ucode`, `.osrel`,
`.uname` from the running UKI (`objcopy`, binutils) and rebuild with
`ukify build` (systemd-ukify, official core) embedding the recovery
command line:

```
cryptdevice=PARTUUID=…:root root=/dev/mapper/root rootflags=subvol=@recovery/<slot> rw rootfstype=btrfs noresume zswap.enabled=0
```

Embedded instead of a loader-entry `options` override: systemd-stub ignores
an override once Secure Boot is on - the embedded form keeps a later Secure
Boot path open (the slot UKI would then be signed like the main one) and
does not depend on loader behaviour. Fallback if the extraction proves
brittle: Type #1 entry with `uki` + `options` (valid while Secure Boot is
off) - decided in the implementation spike (section 23).

Why a writable clone: the busybox initramfs cannot overlay a read-only
root (systemd's `systemd.volatile=overlay` needs a systemd initramfs), and
a read-only root breaks NetworkManager, journald state, random seed,
logins. A Btrfs snapshot of the read-only snapshot costs nothing until
written; booting it never touches the pristine read-only snapshot.

Recovery UKIs live outside `/EFI/Linux/` so systemd-boot does not
auto-list them as normal Type #2 entries (which would boot `@` with an old
kernel).

### Why this wins

| Option | Package | LUKS2 + Argon2id | Kernel/modules consistency | Complexity | Verdict |
|---|---|---|---|---|---|
| **systemd-boot + UKI + recovery slots (this)** | official (systemd, systemd-ukify, snapper) | unchanged: initramfs unlocks, ESP stays the only unencrypted part | exact pair by construction | one small helper, ≤3 entries | **chosen** |
| GRUB + grub-btrfs | official (grub, grub-btrfs) | GRUB 2.12 cannot unlock Argon2id keyslots -> PBKDF2 keyslot (weaker) or unencrypted `/boot`; grub-btrfs needs `/boot` *inside* the snapshotted root for consistency | only if /boot is in Btrfs (then GRUB must unlock LUKS) | second bootloader, menu with every snapshot, `/boot` move, `roles/power` rewrite (no `/etc/kernel/cmdline`) | rejected: weakens LUKS or loses consistency |
| Limine + snapshot sync | limine official, `limine-snapper-sync` AUR only | Limine reads only FAT: kernels copied to ESP per snapshot (same idea as ours) | yes via copies | AUR tool (policy: last resort), new bootloader | rejected: same mechanism as ours but via AUR and a bootloader switch |
| systemd-boot, all snapper snapshots as entries | official | fine | needs a kernel copy per snapshot: ESP fills (42 MB each), long menu | high | rejected: unbounded |
| Btrfs default-subvolume + `snapper rollback` (SUSE model) | official | fine | does not solve the ESP kernel problem at all; our cmdline/fstab pin `subvol=@` | medium | rejected as the mechanism (section 7) |

## 6. Update transaction: `system-update` owns it

**Pre-transaction snapshots (2026-10-08, supersedes "system-update is the
only automatic creator")**: every pacman transaction - `pacman -S/-R/-U`,
a bare `pacman -Syu`, every package task of a bootstrap - gets ONE
snapshot of `/` right before it, so a recovery point no longer depends on
using `system-update`:

- `/etc/pacman.d/hooks/00-workstation-pre-snapshot.hook`: `PreTransaction`,
  `Install/Upgrade/Remove`, `Target = *`, `NeedsTargets`, `AbortOnFail` -
  pacman runs a hook once per transaction with all targets, not per
  package. It runs `/usr/local/lib/workstation/pre-transaction-snapshot`.
- Class: `snapper create --type single --cleanup-algorithm ""
  --userdata auto=pre-transaction`, description `pacman: <n> packages
  (a, b, c, ...)`. No post snapshot: recovery means "the state right
  before the transaction".
- Retention: after each new one, `prune_auto` (recovery-lib.sh) reads
  `snapper --jsonout list`, takes the class members newest first by number
  and deletes all but the newest **3** - never one a recovery slot still
  uses (`slot=` userdata), never anything outside the class. Snapper's own
  number cleanup does not see the class (cleanup algorithm "").
- `system-update` takes THE snapshot of its update (same class, + the
  `before-update` slot) and leaves a one-shot skip marker
  (`/run/workstation-recovery/skip-pre-snapshot`) so the hook does not take
  a second one for that `pacman -Syu`; the marker is honoured only while
  < 1 h old and removed by system-update's last step. One snapshot per
  update.
- A failed snapshot aborts the transaction (no silent update without its
  recovery point); a recovery boot (not `@`) takes none and lets pacman
  run. One-shot escape: `echo manual > /run/workstation-recovery/skip-pre-snapshot`
  as root.
- Bootstrap noise is bounded by the retention (3), which is why this is no
  longer the snap-pac objection above it: a bootstrap that installs
  nothing runs no transaction and takes no snapshot.

```
system-update
  1 preflight      root via sudo once; on AC or battery > 30 %; free space
                   >= 10 GiB and >= 10 % (section 13); no pacman lock;
                   booted from @ (not from a recovery slot)
  2 repo-healthcheck --system --since-boot    must not FAIL (WARN ok; FAIL -> stop,
                   unless --force; the user decides)
  3 slot           rotate before-update -> previous-update, create the new
                   before-update slot from the RUNNING system (UKI copy +
                   PRE snapshot + clone + entry) BEFORE pacman touches anything
  4 snapshot       (step 3's: class auto=pre-transaction, userdata update=<id>;
                   the pacman hook skips its own for this pacman -Syu)
  5 pacman -Syu    (interactive, as today; mkinitcpio hooks rebuild the UKI)
  6 (no post snapshot since 2026-10-08 - the pre-transaction snapshot is the recovery point)
  7 checks         pacman exit code; UKI exists and is newer than the kernel;
                   bootctl/ESP sanity
  8 repo-healthcheck --system --since <T0>
  9 summary        reboot required? (kernel/systemd/mesa/hyprland changed) - says so,
                   never reboots by itself
```

| Outcome | Behaviour |
|---|---|
| update ok, healthcheck PASS | done; "before-update" slot remains as the way back |
| update ok, healthcheck WARN | done, WARN lines printed |
| update ok, healthcheck FAIL | **no rollback**; prints FAIL lines, how to boot "Recovery: before update", and `system-rollback before-update` |
| pacman fails | exit non-zero, slot kept (the pre-transaction snapshot is the state before); no automatic rollback |
| UKI generation fails | exit non-zero, loud: "do not reboot - the current UKI may be broken; recovery entry is available"; slot kept |
| reboot needed | message; after reboot the user runs `repo-healthcheck` (or `system-update --check`) |

`bootstrap.sh` stays a provisioning tool and keeps its central `pacman -Syu`
(repo rule). On a provisioned machine the documented update path is
`system-update`; running bootstrap afterwards makes its `-Syu` a no-op.
Bootstrap does not create snapshots (it would never be idempotent).

## 7. Rollback semantics

**A. Temporary boot (diagnosis)**: pick "Recovery: …" in the boot menu ->
the slot UKI boots the writable clone `@recovery/<slot>` (own matching
kernel, `noresume`). `@` is untouched; `@home`, `@log`, `@pkg` are the
normal ones (the clone's fstab still mounts them by subvol name - shared).
Changes inside the clone are discarded by default (the clone is recreated
from its read-only snapshot on the next slot refresh). `repo-healthcheck`
reports "booted from recovery slot <slot>" as WARN.

**B. Permanent rollback**: `system-rollback <slot>` (root), from the
recovery boot or from the normal system:

```
1 mount top level (subvolid=5) at a private mount point
2 btrfs subvolume snapshot @snapshots/<n>/snapshot  @rollback-new   (rw, pristine)
3 rename  @ -> @broken-<date>   (kept, read-only afterwards, pinned until removed by hand)
4 rename  @rollback-new -> @
5 rebuild /boot/EFI/Linux/arch-linux.efi from the slot UKI's kernel + initramfs
  with the restored system's normal cmdline (kernel and modules match again;
  built before step 3), keep the replaced one in /EFI/workstation/broken/;
  copy the snapshot's kernel to /boot/vmlinuz-linux (mkinitcpio builds from it)
6 sync; reboot is left to the user
```

The cmdline keeps `rootflags=subvol=@` - the name always means "the live
system"; no dependence on the Btrfs default subvolume, and `snapper
rollback` (which switches the default subvolume) is deliberately not used.
Renaming the mounted `@` is safe on Btrfs (mounts refer to the subvolume
id); doing it from the recovery boot is still the recommended path.

After a permanent rollback: run `repo-healthcheck`; then `bootstrap.sh`
**only if** the repository checkout (in `@home`, not rolled back) is newer
than the restored system and that newer state is wanted - otherwise check
out the commit that matches the restored system first (`git log` /
the snapshot description stores the repo commit at snapshot time).
`~/.config/workstation` (theme, bar layout) is not rolled back by design;
its formats are versioned/validated by the helpers (theme-state, bar
layout) so an older system tolerates newer state - an explicit check in the
destructive test plan.

## 8. Hibernate / swap

- zram stays (priority 100); `/swap/swapfile` on `@swap`, priority 0,
  size = RAM (existing `hibernate_swapfile_size_mib`).
- `roles/power` stays as is with `hibernate_swapfile_path: /swap/swapfile`
  in host_vars. Its guard "never creates subvolumes" stays: `@swap` is
  created by the new recovery/storage role (sole owner of the subvolume
  layout) before `roles/power` runs.
- `resume=/resume_offset=` remain in `/etc/kernel/cmdline` (main UKI only).
  Recovery UKIs carry `noresume`: a recovery kernel must never resume an
  image written by another kernel.
- Stale image risk: hibernate, then boot a recovery slot -> the image
  stays in the swapfile and a later normal boot would resume it on a
  filesystem the recovery boot changed. Mitigation to implement and test:
  the recovery boot runs `swapon` on the swapfile (fstab) after mkswap-ing
  it if a hibernation signature is present (`blkid -p /swap/swapfile`
  reports `swsuspend`) - a one-shot unit only in the recovery cmdline
  context. Open item 23.4.
- `@swap` is never snapshotted (outside `@`, not a snapper config).

## 9. LUKS

Unchanged: LUKS2, aes-xts-plain64, argon2id, busybox `encrypt` hook in the
initramfs (no bootloader ever unlocks LUKS, so Argon2id stays). The ESP
remains the only unencrypted part (UKIs: kernel + initramfs, no secrets).
Recovery UKIs embed the same `cryptdevice=`. Recommended separately: a
LUKS header backup (`cryptsetup luksHeaderBackup`) stored off the machine
- it is the single point of failure snapshots cannot cover. Lowering the
Argon2 cost on the disposable laptop for faster reboot testing is a test
convenience, not part of this design.

## 10. ESP / UKI fallback

- `arch-linux.efi` (current, from mkinitcpio) + slot UKIs in
  `/EFI/workstation/recovery/`: `before-update.efi`, `known-good.efi`,
  optionally `previous-update.efi` - each ~42 MB, total ≤ ~130 MB + current
  42 MB + vmlinuz 17 MB + ucode 15 MB ≈ 210 MB of 1 GiB.
- A slot UKI is only ever produced from the UKI the running system booted
  with (`bootctl` "Current Entry" = arch-linux.efi and booted from `@`),
  never from a freshly generated, untested one - so a broken new UKI can
  never overwrite the last known-good image.
- No mkinitcpio `fallback` preset: same kernel, same generation, so it fails
  in the same cases; the slots cover "current UKI broken".
- `system-update` preflight refuses to start with < 150 MB free on the ESP.

## 11. repo-healthcheck integration

New modes (one script, same checks):

- `--system`: skip graphical-session checks (for TTY/SSH/update use).
- `--since <epoch>`: coredumps and QML errors only count as FAIL after that
  moment; earlier ones stay WARN.

Where it runs: before the update (`--system --since <boot>`), after the
update (`--system --since <T0>`), after a reboot (normal), after a rollback
(normal). New checks once recovery exists: snapper config present,
`/.snapshots` mounted from `@snapshots`, every slot complete (UKI + entry +
snapshot + clone), ESP free space, "booted from @" (WARN when in a slot),
swapfile not in a snapshot. Known upstream crashes (the two-output
Hyprland exit SIGSEGV) are earlier-session coredumps -> WARN; no allowlist
of executables (that would hide a real new Hyprland crash).

## 12. Manual snapshots

`system-snapshot "<label>"` -> read-only snapper snapshot, `important=yes`,
description = label + repo commit. `system-snapshot --known-good "<label>"`
additionally makes it the `known-good` slot (replacing the old one, which
stays an ordinary important snapshot). `system-snapshot --list` = snapper
list + slot markers. Nothing else (no generic manager).

## 13. Retention / space

| What | Kept |
|---|---|
| automatic pre-transaction snapshots (class `auto=pre-transaction`: the pacman hook + system-update) | newest 3 (`prune_auto`), slot-used ones kept |
| older system-update pre/post pairs (before 2026-10-08) | snapper NUMBER_LIMIT=10 until they age out |
| baseline | the `known-good` slot; only while a host has none, one pinned `baseline=yes` snapshot taken once after a complete bootstrap (`recovery-baseline`, `local.yml` post_tasks) |
| manual important | last 4 |
| recovery slots | ≤ 3, pinned, rotated by the helpers |
| @broken-<date> from rollbacks | until removed by hand; healthcheck WARNs while one exists |

Space guard instead of qgroups: `system-update` refuses below 10 GiB / 10 %
free (`btrfs filesystem usage`), offering `snapper cleanup number` and the
list of pinned/broken states. Snapper's cleanup timer (hourly) applies the
count limits.

## 14. Backup / NAS boundary (later, not designed in detail)

- System: re-provisionable from this repository; snapshots for local
  rollback only. Optional: `btrfs send` of the `known-good` snapshot.
- Home: the real backup target. Two compatible ways: read-only snapshots of
  `@home` + `btrfs send/receive` (needs Btrfs on the NAS; incremental,
  exact) or restic/borg on a read-only `@home` snapshot (any NAS, encrypted,
  deduplicated, file-level restore). Nextcloud for selected folders is
  sync, not backup.
- The flat layout (top-level subvolumes, snapshots in `@snapshots`) works
  with all of them; nothing in v1 blocks either choice.

## 15. Arch ISO recovery path

1. Boot the Arch ISO; `cryptsetup open /dev/sda2 root`.
2. `mount -o subvolid=5 /dev/mapper/root /mnt` -> see `@`, `@snapshots`,
   `@recovery`, `@broken-*`.
3. Pick a state: `ls /mnt/@snapshots/*/info.xml` (snapper metadata).
4. Rollback by hand = section 7 steps 2-4 with `btrfs subvolume snapshot`
   and `mv`.
5. Mount the system: `mount -o subvol=@ … /mnt2`, `@home`, `@log`, `@pkg`,
   ESP at `/mnt2/boot`; `arch-chroot /mnt2`.
6. `mkinitcpio -P` (regenerate the UKI), `bootctl install` if the ESP was
   lost, re-create loader entries (`system-snapshot --refresh-entries`).
7. Reboot; `repo-healthcheck`; `bootstrap.sh` if the deployment must be
   re-applied.

Everything uses standard Arch tools (cryptsetup, btrfs-progs, arch-chroot,
mkinitcpio, bootctl).

## 16. Repository changes the implementation needs

- `roles/recovery` (new, host capability `recovery_enabled`, default false;
  laptop/workstation true when ready): packages `snapper`, `systemd-ukify`;
  subvolumes `@snapshots` (+ `@swap` with hibernate) created once with
  guards (refuse when not Btrfs-on-LUKS root with `rootflags=subvol=@`);
  fstab lines; snapper `root` config; loader.conf `default arch-linux.efi`;
  `/EFI/workstation/recovery/`; helpers in `/usr/local/bin`:
  `system-update`, `system-snapshot`, `system-rollback` (no Ansible at
  runtime); removal of the unused nested subvolumes.
- `roles/power`: unchanged code; host_vars `hibernate_swapfile_path:
  /swap/swapfile`; the recovery role runs before it in `local.yml`.
- `roles/diagnostics`: `repo-healthcheck --system/--since`, recovery
  checks, `snapper-cleanup.timer` allowed.
- `docs/feature-architecture.md`, `AGENTS.md` (ownership rows: snapshots,
  updates, boot recovery entries), `README` (update/rollback how-to),
  `tests/` (helper dry-run/unit tests with a loopback Btrfs image in a VM).

## 17. Migration of the test laptop

Online, no repartitioning: mount top level; create `@snapshots` (and later
`@swap`); delete `@/var/lib/{machines,portables}`; fstab; snapper config;
first `known-good` slot; reboot into the slot once (proves the pair);
reboot normal. All of it through `roles/recovery`, never by hand.

## 18. Destructive test plan (laptop, after implementation)

Precondition each time: HEALTHY, `known-good` slot exists, marker file
`~/recovery-marker` with a timestamp, theme/bar state checksums recorded.

1. Slot boot: boot "Recovery: known-good" -> `findmnt /` shows
   `@recovery/known-good`, `uname -r` = slot kernel, healthcheck WARN
   "recovery slot", network/desktop work; reboot normal.
2. Userspace breakage: `systemctl mask NetworkManager` + `system-update`
   (no-op update) -> reboot -> no network -> recovery entry -> network ok ->
   `system-rollback before-update` -> NetworkManager active.
3. Desktop breakage: replace `/usr/bin/start-hyprland` with `exit 1` ->
   Ly login fails -> recovery -> rollback -> Ly/Hyprland ok, `pacman -Qkk
   hyprland` clean.
4. Kernel/initramfs breakage: initramfs without the `encrypt` hook (test
   drop-in, `mkinitcpio -P`) -> normal entry cannot unlock -> recovery entry
   boots -> rollback restores the matching UKI.
5. Broken current UKI: truncate `arch-linux.efi` -> systemd-boot cannot
   start it -> recovery entry -> rollback restores it.
6. Package rollback: `pacman -U` an older package from `@pkg` -> rollback
   -> `pacman -Q` and files consistent (`pacman -Qkk`).
7. After every rollback: `~/recovery-marker` unchanged and newer files in
   home intact, theme/bar checksums equal, `@log` contains the broken
   boot's journal, `repo-healthcheck` HEALTHY, `bootstrap.sh` changed=0.
8. Retention: 7 no-op `system-update` runs -> 5 pairs left, slots intact.
9. Space guard: fill a test file until < 10 % free -> `system-update`
   refuses.
10. Arch ISO drill: section 15 steps 1-3 + chroot + `mkinitcpio -P`.
11. Later (with hibernate): hibernate -> boot recovery slot -> the stale
    image is invalidated -> normal boot does not resume it.

## 19. Risks / open questions

1. **Spike first**: does `ukify build` from extracted sections of the
   mkinitcpio UKI boot reliably (microcode, splash, os-release)? Fallback:
   Type #1 `uki` + `options` (Secure Boot off only).
2. Booting a clone whose fstab mounts the shared `@log`/`@pkg`: fine for
   logs; pacman inside a slot boot must be blocked (would write the shared
   cache and a db that is thrown away) - the helpers refuse, and
   `system-update` checks "booted from @".
3. Slot creation copies the UKI of the *current boot*: if the user updated
   without rebooting and then creates `known-good`, the running kernel and
   `arch-linux.efi` differ -> the helper must refuse ("reboot first") when
   `uname -r` != the UKI's `.uname`.
4. Hibernate stale-image handling in recovery boots (section 8).
5. `snapper-cleanup.timer` vs the "no timers" rule: needs explicit approval.
6. Secure Boot later: slot UKIs must then be signed - compatible with the
   embedded-cmdline choice, not designed further now.
7. `/var/lib/flatpak` snapshot growth: measure after a few updates.
8. Workstation host: same design assumed (archinstall layout); verify its
   real layout in its own Stage 0 before enabling.

## 20. Recommendation

**GO**, starting with a bounded spike on the laptop (ukify slot UKI +
writable clone boot + `noresume`), then `roles/recovery` with
`recovery_enabled` on the laptop only, then the destructive test plan.
NO-GO conditions: the spike cannot produce a bootable slot UKI by either
method, or a rollback cannot be performed without touching the LUKS
header, partition table or `sdb`.

## 21. As built (v1) and test results

Implemented in `roles/recovery` (Ansible: layout, snapper config, timer,
helpers only) and the three on-demand commands `system-update`,
`system-snapshot`, `system-rollback` (+ `recovery-lib.sh`,
`system-update-root`). No resident process; the only timer is
`snapper-cleanup.timer`.

Deviations from sections 1-20:

- **`EMPTY_PRE_POST_CLEANUP="no"`**: with `yes`, snapper's cleanup deleted
  the pre snapshot of a no-op update although the `before-update` slot had
  pinned it (cleanup algorithm "") - the slot's clone/UKI were left without
  their snapshot and `system-rollback before-update` refused. A no-op
  update now keeps its (cheap) pair; the number limit removes it later.
  `tests/run.sh` checks the setting.
- **Number limit counts a pre/post pair once**: `NUMBER_LIMIT=10` keeps
  10 pairs (measured: after 11 update runs the oldest pair went, pinned slot
  snapshots and `known-good` stayed).
- **Nested `var/lib/machines`/`portables` kept** (section 3). They stay in
  the `@broken-<date>` a rollback leaves behind, inside a read-only parent:
  removing it needs `btrfs property set ... ro false` and `btrfs subvolume
  delete -R` (the command `system-rollback` prints).
- **Rollback rebuilds the main UKI** instead of copying the slot UKI (the
  slot UKI embeds the slot's cmdline) and restores `/boot/vmlinuz-linux`.
- **Healthcheck**: `--system`, `--since`; recovery checks = `/.snapshots`
  from `@snapshots`, cleanup timer enabled, booted from `@` (WARN "RECOVERY
  SLOT <slot>" in a slot boot), ESP free space (WARN < 150 MB). Slot
  completeness and `@broken-*` are root-only (snapper, ESP dir 0700, top
  level) and therefore shown by `sudo system-snapshot --list`, not by the
  user-run healthcheck.
- **pacman inside a slot boot is not blocked**, only `system-update`
  refuses there (risk 2): plain `pacman` in a slot writes the throw-away
  clone and the shared `@pkg` cache - harmless to `@`, but pointless.

Destructive results (ThinkPad T440p, 2026-10-05):

| Test | Result |
|---|---|
| spike: ukify slot UKI + Type #1 entry boots the writable clone | pass (same kernel/modules, `@` untouched, `@home` shared, network up) |
| `system-snapshot --known-good`, `system-update` (no-op) | pass; slot rotation before-update -> previous-update |
| userspace + desktop breakage (qpdf removed, NetworkManager masked, `start-hyprland` = `exit 1`) | normal boot broken (session 0.4 s, no network); recovery entry boots a working system |
| permanent rollback (`system-rollback known-good`) | pass: next normal boot healthy, `pacman -Dk` clean, `pacman -Qkk hyprland qpdf networkmanager` 0 altered files, home marker unchanged, bootstrap changed=0 on the 2nd run |
| truncated `arch-linux.efi` (1 MB) | **systemd-boot still starts it** (the PE header survives) and the boot hangs at the vendor/Arch splash; the recovery entry has to be picked by hand in the menu (keep the menu reachable: `timeout` or a held key). `system-rollback before-update` rebuilt the main UKI (kernel section identical to the original), normal boot healthy |
| retention: 11 no-op updates + `snapper-cleanup.service` | oldest pair removed at > 10 pairs; all three slots intact |
| space guard (fake `btrfs` on `PATH`, SSD not filled) | 5 GiB/1 % and 27 GiB/6 % refused, 93 GiB/20 % and the real 223 GiB accepted, unreadable `btrfs` refused with a message |

Not tested on hardware: kernel/initramfs breakage (test 4 - the broken-UKI
test covers the same recovery path), package downgrade from `@pkg`
(test 6), Arch ISO drill (test 10), hibernate (test 11, no `@swap` yet).
Possible later improvement: systemd-boot boot counting (`+3` in the UKI
name + `systemd-bless-boot`) would demote a main UKI that failed to boot
a few times (each attempt still needs a manual reset when it hangs) - not
in v1 (it changes the normal boot path).

### 21.x Desktop UI (2026-10-10)

`system-update` gained `--ui` (reports back to the Quickshell updater over
IPC, keeps the terminal open) and `--no-snapshot` (the only way past a
failed pre-update snapshot: exit 3 = only the snapshot failed, nothing
changed; with the option the hook's skip marker is set and the decision is
logged with `logger -t system-update`), plus a flock (one run at a time).
`snapshot-create` (pkexec, polkit `org.workstation.snapshot.create`) is the
desktop's Create Snapshot - a validated label into `system-snapshot`.
`workstation-checkupdates` feeds the bar's update icon. Details:
`docs/feature-architecture.md` "System updates".
