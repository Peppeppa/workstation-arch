# Clean install of the ThinkPad T440p - checklist

From booting the Arch ISO to `./bootstrap.sh`. The base system comes from
**archinstall**, everything else from this repository. Not executed yet -
the install erases the internal SSD.

Settings checked against archinstall 4.5 (source of the current Arch
package) and the repository's own requirements (`roles/recovery` layout
guard, `recovery-lib` UKI path, `host_vars/laptop.yml`), 2026-10-14.

## 0. Before

- [ ] Nextcloud client shows Documents, Goodnotes and Studium up to date;
      anything else in `~` you still want is copied off (everything on the
      internal SSD is erased, including all snapshots).
- [ ] Current Arch ISO on a USB stick, signature checked
      (`pacman-key -v archlinux-x86_64.iso.sig`).
- [ ] Laptop docked (Ethernet + AC).

## 1. Boot the ISO

F12 at the Lenovo logo -> the USB stick (UEFI). Then:

```sh
loadkeys de-latin1
ping -c3 archlinux.org
lsblk -o NAME,SIZE,TRAN,MODEL
```

Three disks must show up - only one is the target:

| MODEL | SIZE | TRAN | |
|---|---|---|---|
| `LITEONIT LCS-256M6S` | 238.5G | sata | **target** (internal SSD, today's system) |
| `MicroFrom 512GB SATA3 SSD` | 476.9G | sata | **never select** (old Fedora disk) |
| the USB stick | small | usb | the ISO |

```sh
archinstall
```

## 2. archinstall - screen by screen

| Menu | Setting | Why |
|---|---|---|
| Archinstall language | English | - |
| Locales | Keyboard layout `de-latin1`; Locale language `en_US.UTF-8`; Locale encoding `UTF-8` | LANG the healthcheck expects; the keymap is in the initramfs = the layout of the LUKS prompt |
| Mirrors and repositories | region Germany; no optional repositories | multilib only for gaming (off) |
| Disk configuration -> Partitioning | "Use a best-effort default partition layout" -> select **only** `LITEONIT LCS-256M6S` (238.5 GiB) -> filesystem `btrfs` -> "BTRFS subvolumes with a default structure?" **Yes** -> "compression or disable CoW?" **Use compression** | gives a 1 GiB FAT32 ESP at `/boot` and Btrfs `@` `/`, `@home`, `@log` `/var/log`, `@pkg` `/var/cache/pacman/pkg` - exactly what `roles/recovery` expects |
| Disk configuration -> Btrfs snapshots | none | the repository sets up snapper and `@snapshots` itself |
| Disk configuration -> LVM | none | - |
| Disk configuration -> Disk encryption | Encryption type **LUKS**; Password = your new LUKS passphrase (typed here, on the laptop); Partitions: the **btrfs** partition only; no FIDO2/HSM | LUKS2 + the `encrypt` hook with `cryptdevice=PARTUUID=...` (an HSM would switch to `sd-encrypt`) |
| Swap | "swap on zram?" **Yes**, algorithm `zstd` | the repository's zram config is identical |
| Bootloader | **Systemd-boot**; Unified kernel images **Enabled**; Plymouth off | UKI `/boot/EFI/Linux/arch-linux.efi`; Plymouth can hide the LUKS prompt |
| Kernels | `linux` only | the UKI must be `arch-linux.efi` |
| Additional firmware | default | - |
| Hostname | `laptop` | loads `host_vars/laptop.yml` (recovery, SSH server, VA-API, monitor) |
| Authentication | Root password: **empty** (root stays locked); User: `medvidec`, password, **superuser: yes**; Passwordless sudo: **no**; U2F: none | superuser = group `wheel` = polkit's administrator (firewall, snapshot delete, restore); sudo with a password only |
| Profile | **Minimal** | no desktop and no greeter - the repository installs Hyprland and Ly |
| Applications | none | audio and Bluetooth come from the repository |
| Network configuration | **Use Network Manager (default backend)** (not iwd) | the network owner in this repository, with its default Wi-Fi backend |
| Pacman | default | - |
| Additional packages | `git ansible openssh` | the bootstrap's prerequisites + `ssh-keygen` for step 3 |
| Timezone | `Europe/Berlin` | - |
| Automatic time sync (NTP) | enabled | - |

**Install** -> check the summary once more: the only disk is the
`LITEONIT LCS-256M6S`, 238.5 GiB. Confirm. When it is done, pick
**"chroot into installation for post-installation configurations"**.

## 3. In the chroot - before the first boot

archinstall builds a fallback UKI as well; after a snapshot restore it would
still carry the newer kernel (only `arch-linux.efi` is rebuilt) - remove it:

```sh
sed -i "s/^PRESETS=.*/PRESETS=('default')/" /etc/mkinitcpio.d/linux.preset
rm -f /boot/EFI/Linux/arch-linux-fallback.efi
```

Your SSH key from GitHub, only the one with this fingerprint (public, no
secret; lets the laptop be tested over SSH after the bootstrap):

```sh
curl -fsS https://github.com/Peppeppa.keys -o /tmp/keys
FP=SHA256:SGUsz61ZGjcqPZBHWWf3N8VAWBJV6DO0FCPg890Ogq4
install -d -m700 -o medvidec -g medvidec /home/medvidec/.ssh
while read -r l; do
    printf '%s\n' "$l" > /tmp/k1
    ssh-keygen -lf /tmp/k1 | grep -qF "$FP" && printf '%s\n' "$l"
done < /tmp/keys > /home/medvidec/.ssh/authorized_keys
chown medvidec:medvidec /home/medvidec/.ssh/authorized_keys
chmod 600 /home/medvidec/.ssh/authorized_keys
ssh-keygen -lf /home/medvidec/.ssh/authorized_keys     # one line: SHA256:SGUsz61...
```

Check (read only) - each line must show what the comment says:

```sh
cat /etc/kernel/cmdline        # cryptdevice=PARTUUID=...:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs
grep ^HOOKS /etc/mkinitcpio.conf   # ... keyboard keymap consolefont block encrypt filesystems fsck
grep -v '^#' /etc/fstab        # subvol=/@, /@home, /@log, /@pkg (no subvolid=), /boot vfat
ls /boot/EFI/Linux/            # arch-linux.efi only
cat /boot/loader/loader.conf   # default arch-linux.efi, timeout 3
cat /etc/hostname              # laptop
id medvidec                    # ... wheel
```

```sh
exit
reboot                         # remove the stick at the Lenovo logo
```

## 4. First boot -> bootstrap

1. Boot menu (3 s) -> Arch Linux; LUKS passphrase; log in as `medvidec` on
   tty1.
2. Network: Ethernet comes up by itself (Wi-Fi: `nmtui`).
3. Bootstrap:

   ```sh
   mkdir -p ~/repos/Peppeppa
   git clone https://github.com/Peppeppa/workstation-arch.git ~/repos/Peppeppa/workstation-arch
   cd ~/repos/Peppeppa/workstation-arch
   ./bootstrap.sh
   ```

Then as in the README: reboot, log in at Ly, `repo-healthcheck`, a second
`./bootstrap.sh` (changed=0), phase 2 (Bitwarden, `./bootstrap-personal.sh`),
Wi-Fi/eduroam/VPN profiles. On the controller, drop the old host key
before the first SSH login (`ssh-keygen -R <address>` for both addresses) -
the new system has new host keys. LUKS second keyslot and header backup:
`LUKS_RECOVERY_PLAN.md`.

## Not carried over

Everything on the internal SSD: the old system, `/home`, all snapshots and
boot entries, NetworkManager profiles, Bitwarden/Chromium/Flatpak data,
SSH host keys. The 512 GB Fedora disk is not touched by any step here.
