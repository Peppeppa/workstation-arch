# Offline recovery

Public, identifier-free copies of what lies on the offline recovery stick
`REPO-RECOVERY` (H14, 2026-10-14). The stick additionally holds the LUKS
header backup, `SYSTEM-INFO.md` with the machine's real UUIDs/models/boot
paths, and `SHA256SUMS`. Secrets (passphrase, recovery key) are on neither.

| File | For |
|---|---|
| `RECOVERY-GUIDE.md` | humans (German): identify the disk, unlock from an Arch ISO, mount, save data, header check/restore, systemd-boot/UKI repair, snapshot restore, troubleshooting - every command marked READ-ONLY / REVERSIBLE / DESTRUCTIVE |
| `AGENT-RECOVERY.md` | an AI agent: hard rules (never restore a header, kill a keyslot, format or restore a snapshot on its own), decision tree, commands |
| `../../scripts/luks-recovery-setup.sh` | the owner, locally as root: recovery key + header backup onto the mounted stick |

`<placeholders>` stand for the values in the stick's `SYSTEM-INFO.md`.

## Setting up a stick for another machine (e.g. the workstation)

A recovery key and a header backup belong to ONE LUKS container - every
machine (and every reinstall) needs its own. The workstation has
`recovery_enabled` off and its layout unchecked; its own Stage 0 check comes
first.

1. Identify the stick read-only (`lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN`,
   `/dev/disk/by-id/usb-*`); the owner confirms the device.
2. Wipe it, GPT, one ext4 labelled `REPO-RECOVERY`, mount (DESTRUCTIVE for
   the stick only; check serial + size again right before).
3. Locally, in a terminal on that machine:
   `sudo scripts/luks-recovery-setup.sh <mountpoint>`.
4. Copy `RECOVERY-GUIDE.md` and `AGENT-RECOVERY.md` with the placeholders
   filled in, write `SYSTEM-INFO.md` from read-only commands (`lsblk`,
   `blkid`, `cryptsetup luksDump`, `/etc/fstab`, `/etc/kernel/cmdline`,
   `bootctl status`) and a short `README.md`; then
   `sha256sum *.md luks-header.img > SHA256SUMS`.
5. Unmount, remount read-only, `sha256sum -c SHA256SUMS`, unmount.
6. Record the backup's date + sha256 (no secrets) in the release report.

After any keyslot change (`luksAddKey`, `luksKillSlot`, `luksChangeKey`,
`systemd-cryptenroll --wipe-slot`): a new backup, verified, and the old ones
destroyed - an old backup opens the disk with an old passphrase.
