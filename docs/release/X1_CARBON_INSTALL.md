# Install REPO on the ThinkPad X1 Carbon 6th Gen - checklist

From backing up Omarchy to a running REPO desktop. The procedure is the one
validated on the T440p (`CLEAN_INSTALL_PLAN.md`, executed 2026-10-14, result
`CLEAN_INSTALL_ACCEPTANCE_V1_REPORT.md`): **archinstall** for the base system,
this repository for everything else. Only the differences for this machine
are new; they are marked **X1**. Done by the owner on the laptop - no agent,
no SSH.

| | |
|---|---|
| Machine | ThinkPad X1 Carbon 6th Gen (20KG), i7-8550U, Intel UHD Graphics 620 (i915), Wireless-AC 8265 (iwlwifi), I219-V (e1000e, via the Lenovo Ethernet adapter), 16 GiB |
| Target disk | internal NVMe `/dev/nvme0n1`, WD Blue, ~1.8 TiB - **erased completely** |
| Firmware | UEFI, Secure Boot **off** (stays off - `docs/recovery-design.md`), no TPM2 needed (LUKS passphrase only) |
| Hostname | `x1carbon` -> `host_vars/x1carbon.yml`: recovery (snapshots/rollback), gaming (`vulkan-intel` + `lib32-vulkan-intel`), VA-API `intel-media-driver`, THWS VPN, **no SSH server**; printing comes from `group_vars` (on for every host) |
| Display | no fixed mode/scale - Hyprland's automatic rule; change later in Appearance -> Display |

## 0. Before - backup (on the running Omarchy)

Everything on the internal NVMe is erased: the system, `/home`, every
snapshot, every Wi-Fi profile. Check each line yourself:

- [ ] Nextcloud client: all synced folders (Documents, Goodnotes, Studium, ...)
      show "up to date".
- [ ] Files outside the synced folders copied to an external disk/stick or
      into Nextcloud - at least: `~/Work`, `~/knime-workspace`, the Jupyter
      notebooks in `~` (`Untitled*.ipynb`), screenshots in `~`, `~/Downloads`
      items you still need, `~/AnyDesk`, `~/share`.
- [ ] Local VMs: `~/VirtualBox VMs/` (e.g. `systemnahe-programmierung-UBUNTU`)
      exported or copied (VirtualBox -> File -> Export Appliance, or the whole
      folder with the VM shut down).
- [ ] Thunderbird: profile copied (`~/.thunderbird/`, and `~/thunderbird` if
      you used it) - or confirmed that all accounts are IMAP and local folders
      are empty.
- [ ] Git: every repository under `~/repos` has no uncommitted changes and
      nothing unpushed (`git status`, `git log @{u}..` in each).
- [ ] Browser: bookmarks/passwords synced or exported (passwords belong in
      Bitwarden).
- [ ] Bitwarden: master password and the self-hosted server URL known -
      phase 2 needs them.
- [ ] LUKS passphrase for the NEW install chosen (written down safely).
- [ ] eduroam: the CAT installer (`eduroam-linux-THW.py`) can be downloaded
      again later (cat.eduroam.org) - no need to keep it.

## 1. Arch ISO

- [ ] Current Arch ISO on a USB stick, signature checked
      (`pacman-key -v archlinux-x86_64.iso.sig`).
- [ ] AC adapter plugged in. Network for the install: **X1** the Lenovo
      Ethernet adapter (I219-V) with a cable, or Wi-Fi (below).

F12 at the Lenovo logo -> the USB stick (UEFI). Then:

```sh
loadkeys de-latin1
```

**X1 - Wi-Fi in the live system** (only without the Ethernet adapter; the
Arch installation guide's `iwctl`; a WPA-Personal network such as a home
router or a phone hotspot - eduroam is set up later, in REPO):

```sh
iwctl device list                      # the Wi-Fi device, usually wlan0
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "<SSID>"   # asks for the Wi-Fi password
```

Then:

```sh
ping -c3 archlinux.org
lsblk -o NAME,SIZE,TRAN,MODEL
```

**X1 - the target disk.** Exactly two disks must show up - only one is the
target:

| NAME | SIZE | TRAN | MODEL | |
|---|---|---|---|---|
| `nvme0n1` | ~1.8T | nvme | WD Blue ... | **target** (internal SSD, today's Omarchy) |
| `sda` (or `sdb`) | small | usb | the stick | the ISO - **never select** |

If anything else shows up (another USB disk), unplug it before going on.

```sh
archinstall
```

## 2. archinstall - screen by screen

> **The next step erases the whole internal NVMe (`nvme0n1`): the Omarchy
> system, its LUKS container, `/home`, all snapshots and boot entries. Do not
> continue before section 0 is done.** The validated layout is created new
> (the old partitions are not reused).

| Menu | Setting | Why |
|---|---|---|
| Archinstall language | English | - |
| Locales | Keyboard layout `de-latin1`; Locale language `en_US.UTF-8`; Locale encoding `UTF-8` | LANG the healthcheck expects; the keymap is in the initramfs = the layout of the LUKS prompt |
| Mirrors and repositories | region Germany; no optional repositories | multilib is switched on by the bootstrap itself (gaming host) |
| Disk configuration -> Partitioning | "Use a best-effort default partition layout" -> select **only** the internal NVMe `nvme0n1` (WD Blue, ~1.8 TiB) -> filesystem `btrfs` -> "BTRFS subvolumes with a default structure?" **Yes** -> "compression or disable CoW?" **Use compression** | gives a 1 GiB FAT32 ESP at `/boot` and Btrfs `@` `/`, `@home`, `@log` `/var/log`, `@pkg` `/var/cache/pacman/pkg` - exactly what `roles/recovery` expects |
| Disk configuration -> Btrfs snapshots | none | the repository sets up snapper and `@snapshots` itself |
| Disk configuration -> LVM | none | - |
| Disk configuration -> Disk encryption | Encryption type **LUKS**; Password = your new LUKS passphrase (typed here, on the laptop); Partitions: the **btrfs** partition only; no FIDO2/HSM | LUKS2 + the `encrypt` hook with `cryptdevice=PARTUUID=...` (an HSM would switch to `sd-encrypt`) |
| Swap | "swap on zram?" **Yes**, algorithm `zstd` | the repository's zram config is identical |
| Bootloader | **Systemd-boot**; Unified kernel images **Enabled**; Plymouth off | UKI `/boot/EFI/Linux/arch-linux.efi`; Plymouth can hide the LUKS prompt |
| Kernels | `linux` only | the UKI must be `arch-linux.efi` |
| Additional firmware | default | `linux-firmware` (iwlwifi for the AC 8265, i915) |
| Hostname | `x1carbon` | loads `host_vars/x1carbon.yml` (recovery, gaming, VA-API, VPN, no SSH server) |
| Authentication | Root password: **empty** (root stays locked); User: `medvidec`, password, **superuser: yes**; Passwordless sudo: **no**; U2F: none | superuser = group `wheel` = polkit's administrator (firewall, snapshot delete, restore); sudo with a password only |
| Profile | **Minimal** | no desktop and no greeter - the repository installs Hyprland and Ly |
| Applications | none | audio and Bluetooth come from the repository |
| Network configuration | **Use Network Manager (default backend)** (not iwd) | the network owner in this repository, with its default Wi-Fi backend |
| Pacman | default | - |
| Additional packages | `git ansible openssh` | the bootstrap's prerequisites (+ the SSH client) |
| Timezone | `Europe/Berlin` | - |
| Automatic time sync (NTP) | enabled | - |

**Install** -> check the summary once more: the only disk is `nvme0n1`,
~1.8 TiB. Confirm. When it is done, pick **"chroot into installation for
post-installation configurations"**.

## 3. In the chroot - before the first boot

archinstall builds a fallback UKI as well; after a snapshot restore it would
still carry the newer kernel (only `arch-linux.efi` is rebuilt) - remove it:

```sh
sed -i "s/^PRESETS=.*/PRESETS=('default')/" /etc/mkinitcpio.d/linux.preset
rm -f /boot/EFI/Linux/arch-linux-fallback.efi
```

**X1:** no SSH key step - this laptop runs no SSH server.

Check (read only) - each line must show what the comment says:

```sh
cat /etc/kernel/cmdline        # cryptdevice=PARTUUID=...:root root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs
grep ^HOOKS /etc/mkinitcpio.conf   # ... keyboard keymap consolefont block encrypt filesystems fsck
grep -v '^#' /etc/fstab        # subvol=/@, /@home, /@log, /@pkg (no subvolid=), /boot vfat
ls /boot/EFI/Linux/            # arch-linux.efi only
cat /boot/loader/loader.conf   # default arch-linux.efi, timeout 3
cat /etc/hostname              # x1carbon
id medvidec                    # ... wheel
pacman -Q intel-ucode          # X1: installed (archinstall adds the CPU's microcode; it goes into the UKI)
```

```sh
exit
reboot                         # remove the stick at the Lenovo logo
```

**Old Limine boot entry:** the erased ESP took Limine's files with it;
systemd-boot puts "Linux Boot Manager" first in the firmware's boot order. A
leftover "Limine" entry in the firmware menu (F12) points to nothing and is
harmless - leave it. Removing firmware boot entries is not part of this
validated procedure.

## 4. First boot -> bootstrap

1. Boot menu (3 s) -> Arch Linux; LUKS passphrase; log in as `medvidec` on
   tty1.
2. Network: Ethernet adapter comes up by itself; Wi-Fi: `nmtui` ->
   Activate a connection.
3. Bootstrap (phase 1 - asks once for your sudo password, everything else
   runs without questions):

   ```sh
   mkdir -p ~/repos/peppeppa       # lower case: phase 2 clones into ~/repos/peppeppa too
   git clone https://github.com/Peppeppa/workstation-arch.git ~/repos/peppeppa/workstation-arch
   cd ~/repos/peppeppa/workstation-arch
   ./bootstrap.sh
   ```

   It must end without `failed` (exit 0). It installs gaming (Steam, Lutris,
   GameMode - roughly 0.6 GiB more) and printing on this host.
4. `reboot`, log in at Ly (Hyprland starts).
5. In a terminal (`mainMod+Return`):

   ```sh
   repo-healthcheck                # HEALTHY
   cd ~/repos/peppeppa/workstation-arch && ./bootstrap.sh   # second run: changed=0
   ```

6. Phase 2 as in the README: Bitwarden (server URL, login, Settings ->
   Enable SSH agent), then `./bootstrap-personal.sh`.
7. Networks: Wi-Fi profiles in the Network popup; eduroam/THWS with
   `eduroam-setup ~/Downloads/eduroam-linux-THW.py` (README "eduroam"); THWS
   VPN (README "Uni VPN (THWS)").
8. Sign-ins at first use: `claude`, `codex`, `bw login` (README "AI coding
   CLIs").

## 5. Hardware checks after the install

Not testable before - tick what works, note what does not (then
`repo-diagnose` / OS menu -> System -> Diagnostic):

- [ ] Display: resolution and scale look right (Appearance -> Display);
      brightness keys and the Appearance slider.
- [ ] Audio: speakers, headphone jack, internal microphone, volume and
      mute/mic-mute keys incl. their LEDs. (If there is no sound card at all:
      note it - `sof-firmware` is not part of REPO yet.)
- [ ] Touchpad (click, two-finger scroll) and TrackPoint with its buttons.
- [ ] ThinkPad keys: volume, mute, mic mute, brightness.
- [ ] Wi-Fi (home, eduroam/THWS on campus), Ethernet adapter, Bluetooth
      (pair a device).
- [ ] Battery: percentage and AC/battery switch in the bar, power profiles.
- [ ] Lid close -> lock + suspend -> resume, three times. (The X1 Carbon 6th
      Gen offers a BIOS sleep setting "Windows"/"Linux" - if suspend drains
      the battery or resume fails, note the setting used.)
- [ ] Idle lock and unlock (hyprlock).
- [ ] Video playback (mpv, Chromium) - VA-API via `intel-media-driver`.
- [ ] Steam starts; GeForce NOW web app opens and streams.
- [ ] Printing: a printer added (README "Printing") and a test page.
- [ ] Create Snapshot (OS menu -> System) -> the entry appears in the boot
      menu.

## 6. LUKS recovery for this machine

A recovery key and a header backup belong to ONE LUKS container - the X1
needs its own, never the T440p's stick or files. Procedure (owner, locally,
as root on the X1): `docs/recovery/README.md` "Setting up a stick for another
machine" - its own `REPO-RECOVERY` stick, then
`sudo scripts/luks-recovery-setup.sh <mountpoint>` from the repository
(recovery key as a 2nd keyslot + verified header backup). Background and
storage rules: `docs/release/LUKS_RECOVERY_PLAN.md` (written for the T440p;
the steps read the LUKS partition from `/etc/kernel/cmdline`, so they are the
same here).

## Not carried over

Everything on the internal NVMe: Omarchy, `/home`, all snapshots and boot
entries, NetworkManager profiles, Bitwarden/Chromium/Flatpak data, SSH host
keys. Only what section 0 saved.
