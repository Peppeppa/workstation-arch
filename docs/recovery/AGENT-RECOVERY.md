# AGENT-RECOVERY - technical recovery instructions for an AI agent

Audience: an AI coding agent helping the owner recover the REPO laptop
(Arch Linux, LUKS2 + Btrfs + systemd-boot UKI) from an Arch live system or
from the installed system. Human guide: `RECOVERY-GUIDE.md` (German, same
section numbers). Real identifiers: `SYSTEM-INFO.md` (on the recovery stick;
the public copy uses `<placeholders>`).

## 1. Hard rules (non-negotiable)

You MUST NOT, on your own initiative or as part of a "fix" chain:

- run `cryptsetup luksHeaderRestore`, `luksFormat`, `luksKillSlot`,
  `luksRemoveKey`, `luksChangeKey`, `luksErase`, `reencrypt`,
  `systemd-cryptenroll --wipe-slot`, or `erase`;
- run `mkfs.*`, `wipefs`, `sgdisk`/`sfdisk`/`parted`/`fdisk` writes, `dd`
  with `of=` a block device, `blkdiscard`, `btrfs check --repair`;
- perform a permanent snapshot restore (`system-rollback`, `snapshot-restore`,
  renaming `@`), or delete any subvolume (`@broken-*` is the way back);
- touch the Fedora SSD (no LUKS on it; label `<Fedora-Label>`) at all;
- write anything to the REPO-RECOVERY stick except a NEW file the owner asked
  for (never overwrite `luks-header.img`);
- ask for, print, log, store, or pass through argv/files any passphrase,
  recovery key or header content. The owner types secrets at the local
  prompt. `cryptsetup` reads them from the TTY.

Each DESTRUCTIVE step requires, in this order:
1. the prerequisite checks of its section, run and shown;
2. re-identification of the target: `readlink -f <by-id/by-uuid path>` +
   `lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,UUID <dev>` matching `SYSTEM-INFO.md`;
3. a backup of what will be overwritten (section-specific), verified;
4. a statement of the risk and the way back;
5. explicit owner confirmation naming the device (e.g. "JA /dev/sda2
   <Modell der REPO-SSD>"), given in this conversation for this exact step.
Never batch a DESTRUCTIVE command with other commands.

Kernel device names (`sda`, `sdb`, `sdc`) differ between the installed system
and the live ISO. Use only `/dev/disk/by-uuid/...` and `/dev/disk/by-id/...`.

## 2. Classification

| Class | Examples |
|---|---|
| READ-ONLY | `lsblk`, `blkid`, `findmnt`, `cryptsetup isLuks/luksDump/luksUUID`, `cryptsetup open --test-passphrase`, `cryptsetup open --readonly`, `mount -o ro`, `btrfs subvolume list`, `bootctl status/kernel-inspect`, `sha256sum -c`, `dd if=<dev> of=<file>` (reading the device) |
| REVERSIBLE | `cryptsetup open` (rw) / `close`, rw mounts, `arch-chroot`, `mkinitcpio -P` (after copying `/boot`), `bootctl install`, `btrfs subvolume snapshot` into a new name, `mv` of subvolumes with the old one kept |
| DESTRUCTIVE | everything in section 1's forbidden list |

## 3. Facts (verify, do not assume)

| Item | Value |
|---|---|
| REPO SSD | `/dev/disk/by-id/<ata-ID-der-REPO-SSD>` (<Modell der REPO-SSD>, <Größe>) |
| ESP | partition 1, vfat, UUID `<ESP-UUID>`, mounted at `/boot` (root-only, fmask 0177) |
| LUKS2 | partition 2, UUID `<LUKS-UUID>`, PARTUUID `<LUKS-PARTUUID>`, keyslot 0 passphrase, keyslot 1 recovery key (token `systemd-recovery`) |
| Btrfs in LUKS | `/dev/mapper/root`, UUID `<Btrfs-UUID>`; default subvolume = 5 (top level) |
| Subvolumes | `@`→`/`, `@home`→`/home`, `@log`→`/var/log`, `@pkg`→`/var/cache/pacman/pkg`, `@snapshots`→`/.snapshots`, `@recovery`, `@broken-<stamp>` |
| Mount options | `rw,relatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@...` |
| Kernel cmdline | `/etc/kernel/cmdline`: `cryptdevice=PARTUUID=<LUKS-PARTUUID>:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs` |
| Initramfs | mkinitcpio, busybox hooks `base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck` + `workstation-snapshot-overlay` (`/etc/mkinitcpio.conf.d/60-workstation-snapshot-overlay.conf`) |
| UKI | preset `/etc/mkinitcpio.d/linux.preset`, `PRESETS=('default')`, `default_uki=/boot/EFI/Linux/arch-linux.efi`, `ALL_kver=/boot/vmlinuz-linux` |
| Bootloader | systemd-boot, `/boot/loader/loader.conf`: `timeout 3`, `default arch-linux.efi`; snapshot entries `/boot/loader/entries/workstation-snapshot-<n>.conf` (`uki /EFI/workstation/snapshots/<uname>.efi`, `rootflags=subvol=@snapshots/<n>/snapshot ... workstation.snapshot=<n>`) |
| Secure Boot / TPM | disabled / TPM 1.2 (no TPM2 unlock) |
| crypttab | empty (unlock happens only in the initramfs) |
| Console keymap | `de-latin1` |
| Header backup | `REPO-RECOVERY:/luks-header.img`, 16777216 bytes, root 0400, created <Backup-Datum>, keyslots 0+1 |

REPO recovery tools on the installed system (root): `/usr/local/bin/system-rollback`,
`/usr/local/bin/system-snapshot`, `/usr/local/bin/system-update`,
`/usr/local/lib/workstation/snapshot-boot` (`status`, `sync`, `check N`),
`/usr/local/libexec/workstation/snapshot-restore`, library
`/usr/local/lib/workstation/recovery-lib.sh`. On the Arch ISO none of these
exist - use the plain commands below.

## 4. Decision tree

1. Does the firmware show the systemd-boot menu?
   - no → §7 (ESP/bootloader), after §5 + data check.
2. Does the LUKS prompt accept the passphrase or recovery key?
   - no, both rejected → keymap check (§5), then §6 header check.
3. Does the normal entry boot to login?
   - no → owner picks a snapshot entry in the menu (temporary, safe). If that
     boots: diagnose; permanent restore only with owner consent (§8).
   - no snapshot boots → live ISO, §5 → §7 (UKI) or §8b.
4. Before ANY repair: offer data backup (§5 read-only + rsync of `@home`).

## 5. Live ISO: identify, unlock, mount (READ-ONLY)

```sh
loadkeys de-latin1
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL,UUID,PARTUUID
L=/dev/disk/by-uuid/<LUKS-UUID>
test -b "$L" || echo "LUKS UUID missing -> header damaged? use /dev/disk/by-id/<ata-ID-der-REPO-SSD>-part2 and §6"
cryptsetup isLuks "$L" && cryptsetup luksDump "$L" | sed -n '1,12p'
cryptsetup open --readonly "$L" root           # owner types the secret
mkdir -p /mnt/top && mount -o ro,subvolid=5 /dev/mapper/root /mnt/top
btrfs subvolume list /mnt/top
mkdir -p /mnt/rec && mount -o ro /dev/disk/by-label/REPO-RECOVERY /mnt/rec
(cd /mnt/rec && sha256sum -c SHA256SUMS)
```

Read-write (REVERSIBLE): close + `cryptsetup open "$L" root`, then
`mount -o compress=zstd:3,subvol=@ /dev/mapper/root /mnt/sys` + `@home`
`/mnt/sys/home`, `@log` `/mnt/sys/var/log`, `@pkg` `/mnt/sys/var/cache/pacman/pkg`,
`@snapshots` `/mnt/sys/.snapshots`, `mount /dev/disk/by-uuid/<ESP-UUID> /mnt/sys/boot`.

## 6. LUKS header

Check (READ-ONLY):
```sh
D=/dev/disk/by-id/<ata-ID-der-REPO-SSD>-part2
cryptsetup isLuks "$D"; echo "isLuks=$?"
cryptsetup luksUUID /mnt/rec/luks-header.img        # must equal <LUKS-UUID>
cryptsetup open --test-passphrase --header /mnt/rec/luks-header.img "$D"
```
Data access without writing the disk (READ-ONLY, preferred):
`cryptsetup open --readonly --header /mnt/rec/luks-header.img "$D" root`.

Restore (DESTRUCTIVE, last resort, owner approval per §1; NOT EXECUTED on this
hardware, drilled on image files only):
- Explain first: a header restore is not a snapshot restore. It replaces ALL
  keyslots with the backup's (<Backup-Datum>: slot 0 passphrase of that day, slot 1
  recovery key). Later passphrase changes are undone; removed keys work again.
- Preconditions: backup UUID matches; `--test-passphrase --header` = 0 with a
  key the owner knows today; target re-identified; data backed up or waived.
- Way back first: `dd if="$D" of=<external>/damaged-header-<date>.img bs=1M count=16`.
- `cryptsetup luksHeaderRestore "$D" --header-backup-file /mnt/rec/luks-header.img`
- Verify: `cryptsetup open --test-passphrase "$D"`.
- Afterwards: new header backup under a new name, old ones destroyed (owner).

## 7. systemd-boot / UKI (REVERSIBLE)

```sh
cp -a /mnt/sys/boot <external>/boot-copy-$(date +%F)   # way back
arch-chroot /mnt/sys
ls /usr/lib/modules; bootctl kernel-inspect /boot/EFI/Linux/arch-linux.efi
cp /usr/lib/modules/<kver>/vmlinuz /boot/vmlinuz-linux
mkinitcpio -P                       # rebuilds /boot/EFI/Linux/arch-linux.efi
bootctl install                     # only if /EFI/systemd or the EFI entry is missing
/usr/local/lib/workstation/snapshot-boot sync     # snapshot entries (optional)
```
`/boot/loader/loader.conf` must hold `default arch-linux.efi`. Recreating the
ESP filesystem is DESTRUCTIVE and changes its UUID (update `/etc/fstab`).

## 8. Snapshots

a) Installed system / snapshot boot: the owner selects a snapshot entry
(temporary, RAM overlay, nothing persists). Permanent: the owner runs
`sudo system-rollback <n>` (asks to type `rollback`) or the dialog. It keeps
the old `@` as `@broken-<stamp>` (ro), builds the UKI for the snapshot's
kernel, removes a stale `var/lib/pacman/db.lck`, writes
`/var/lib/workstation/snapshot-restore.json`. Agent: propose, never run.

b) Live ISO (NOT EXECUTED on hardware; equals system-rollback's steps), rw
top level at `/mnt/top`, owner consent required:
```sh
btrfs subvolume snapshot /mnt/top/@snapshots/<n>/snapshot /mnt/top/@restore-new
rm -f /mnt/top/@restore-new/var/lib/pacman/db.lck
mv /mnt/top/@ /mnt/top/@broken-<stamp> && mv /mnt/top/@restore-new /mnt/top/@
btrfs property set /mnt/top/@broken-<stamp> ro true
# then §7 with the snapshot's kernel version
```
Way back: rename `@` away, `ro false` + rename `@broken-<stamp>` back to `@`, §7.

Effects of a permanent restore: everything on `@` reverts - packages, `/etc`
(NetworkManager profiles stored "for all users"), `/var/lib` (Bluetooth
pairings, `/var/lib/workstation/firewall/rules.json`). `/home`, `@log` stay.

## 9. Verification after recovery (READ-ONLY)

`findmnt /` = `/dev/mapper/root[/@]`; `repo-healthcheck` exit 0;
`systemctl --failed` empty; `sudo /usr/local/lib/workstation/snapshot-boot status`;
`sudo cryptsetup luksDump /dev/disk/by-uuid/<LUKS-UUID>` keyslots as expected;
`faillock --user medvidec` empty.

## 10. Tested vs. not tested

Tested on this laptop: snapshot boot, permanent restore via dialog,
`--test-passphrase` of passphrase and recovery key, header backup byte-compare
with the disk + `--test-passphrase --header` (<Backup-Datum>).
NOT EXECUTED here: recovery key at the real boot prompt, header restore,
anything from the live ISO (unlock, chroot, mkinitcpio, bootctl install,
manual rollback). Header restore / stale backup / recovery key mechanics were
drilled on image files only.
