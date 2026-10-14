# REPO-Laptop: Offline-Wiederherstellung (Anleitung für Menschen)

Diese Anleitung funktioniert **ohne** das GitHub-Repository und **ohne** ein
startfähiges REPO-System. Du brauchst nur: diesen Stick, einen zweiten
USB-Stick mit dem Arch-Linux-Installationsmedium, dein LUKS-Passwort oder den
Recovery-Key (Papier) und einen zweiten Rechner/ein Handy zum Lesen.

Alle Gerätekennungen dieses Laptops stehen in `SYSTEM-INFO.md` (auf dem
Recovery-Stick). In der öffentlichen Kopie dieser Anleitung stehen statt
dessen Platzhalter in spitzen Klammern.

## 0. Die drei Arten von Befehlen

Jeder Befehl in dieser Anleitung ist markiert:

| Markierung | Bedeutung |
|---|---|
| **[READ-ONLY]** | liest nur. Kann nichts kaputt machen. |
| **[REVERSIBLE]** | ändert etwas, aber mit beschriebenem, geprüftem Rückweg. |
| **[DESTRUCTIVE]** | kann Daten oder Schlüsselmaterial **endgültig** überschreiben. Nur nach den Vorprüfungen im Abschnitt und nach bewusster Entscheidung. Wenn unsicher: **nicht ausführen**, erst Daten sichern (Abschnitt 8). |

Goldene Regeln:

1. Erst **lesen**, dann **Daten sichern**, dann reparieren.
2. Geräte **nie** über `/dev/sda`, `/dev/sdb` ansprechen, wenn es sich vermeiden
   lässt - im Live-System können die Buchstaben anders verteilt sein (der
   USB-Stick kann `sda` sein!). Immer `/dev/disk/by-uuid/...` oder
   `/dev/disk/by-id/...` verwenden und vorher mit `lsblk` prüfen.
3. **Nie** `cryptsetup luksFormat`, `mkfs`, `wipefs`, `luksKillSlot`,
   `luksHeaderRestore` "zum Probieren".
4. Die **Fedora-SSD** wird bei keiner dieser Reparaturen gebraucht oder
   verändert.

## 1. Die richtige SSD erkennen [READ-ONLY]

Im Laptop stecken zwei SSDs. Nur die REPO-SSD ist verschlüsselt (LUKS2).

```sh
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL,UUID,PARTUUID
ls -l /dev/disk/by-id/ /dev/disk/by-uuid/
```

| Gerät | Modell | Größe | Erkennungsmerkmal |
|---|---|---|---|
| **REPO-SSD** (dieses System) | <Modell der REPO-SSD> | <Größe> | Partition 2 = `crypto_LUKS`, UUID `<LUKS-UUID>` |
| Fedora-SSD (**nicht anfassen**) | <Modell der Fedora-SSD> | <Größe> | ext4 + btrfs mit Label `<Fedora-Label>`, **kein** LUKS |
| Recovery-Stick (dieser) | <Modell des Sticks> | <Größe> | ext4, Label `REPO-RECOVERY` |
| Arch-Installationsstick | (dein zweiter Stick) | | Label `ARCH_...` (iso9660) |

Die REPO-SSD ist **nur** die, deren zweite Partition `crypto_LUKS` mit genau
der UUID `<LUKS-UUID>` ist. Prüfen:

```sh
blkid /dev/disk/by-uuid/<LUKS-UUID>          # TYPE="crypto_LUKS"
readlink -f /dev/disk/by-uuid/<LUKS-UUID>    # z.B. /dev/sda2 - Name merken
```

## 2. Aufbau der REPO-SSD

```
<Modell der REPO-SSD> (<Größe>)
├─ Partition 1: 1 GiB FAT32 = EFI-Systempartition (ESP), UUID <ESP-UUID>
│   eingehängt als /boot - UNVERSCHLÜSSELT, enthält:
│   /EFI/systemd/systemd-bootx64.efi, /EFI/BOOT/BOOTX64.EFI   (Bootloader)
│   /EFI/Linux/arch-linux.efi        (UKI = Kernel+Initramfs+Kommandozeile)
│   /EFI/workstation/snapshots/*.efi (UKI-Kopien für Snapshot-Boot)
│   /EFI/workstation/backup/arch-linux.efi (Kopie des UKI vor dem letzten Neubau)
│   /EFI/workstation/broken/*.efi    (UKI des Systems vor einem Restore)
│   /loader/loader.conf, /loader/entries/workstation-snapshot-*.conf
│   /vmlinuz-linux, /intel-ucode.img
└─ Partition 2: LUKS2 (aes-xts-plain64, Argon2id), UUID <LUKS-UUID>,
    PARTUUID <LUKS-PARTUUID>
    Keyslot 0 = dein Passwort, Keyslot 1 = Recovery-Key (systemd-recovery)
    └─ entsperrt: /dev/mapper/root = Btrfs, UUID <Btrfs-UUID>
        @            → /          (das laufende System)
        @home        → /home      (deine Dateien)
        @log         → /var/log
        @pkg         → /var/cache/pacman/pkg
        @snapshots   → /.snapshots (Snapper-Snapshots: @snapshots/<n>/snapshot)
        @recovery    (alte Recovery-Slots, kann leer sein)
        @broken-<datum> (altes System nach einem Restore, read-only)
```

Der Kernel bekommt beim Booten:
`cryptdevice=PARTUUID=<LUKS-PARTUUID>:root root=/dev/mapper/root rootflags=subvol=@ ...`
- die Initramfs (busybox, Hook `encrypt`) fragt nach dem Passwort.
Tastatur im Initramfs: `de-latin1`.

## 3. Was du brauchst

- Diesen Stick (`REPO-RECOVERY`).
- Einen **zweiten** USB-Stick (≥ 2 GB) mit dem aktuellen Arch-Linux-ISO.
  **Nie** das ISO auf den REPO-RECOVERY-Stick schreiben - das löscht ihn.
  - Download: <https://archlinux.org/download/>; Prüfsumme/Signatur dort prüfen.
  - Schreiben (auf einem anderen Linux-Rechner, Zielgerät dreimal prüfen!)
    **[DESTRUCTIVE für den Zielstick]**:
    `dd if=archlinux-x86_64.iso of=/dev/disk/by-id/<ZIELSTICK> bs=4M status=progress oflag=sync`
- LUKS-Passwort **oder** Recovery-Key (Papier).
- Optional: externe Festplatte für Datensicherung.

Das Arch-ISO enthält alles Nötige: `cryptsetup`, `btrfs`, `mount`,
`arch-chroot`, `mkinitcpio` (im chroot), `bootctl`, `lsblk`, `blkid`, `sha256sum`.

## 4. Arch-Live-System starten [READ-ONLY]

1. Laptop aus. Arch-Stick einstecken (Dock-USB geht auch).
2. Einschalten, beim Lenovo-Logo **F12** (Boot-Menü) drücken, den USB-Stick
   wählen. Secure Boot ist auf diesem Gerät **aus** - das ISO startet direkt.
3. Im Arch-Menü "Arch Linux install medium" wählen. Es erscheint eine
   Root-Shell (`root@archiso`).
4. Deutsche Tastatur: `loadkeys de-latin1`
5. Optional Netzwerk: Ethernet geht automatisch; WLAN mit `iwctl`.

## 5. REPO-Partition entsperren

**Variante A - nur lesen (empfohlen für Datenrettung) [READ-ONLY]:**

```sh
L=/dev/disk/by-uuid/<LUKS-UUID>
cryptsetup isLuks "$L" && echo "LUKS ok"
cryptsetup open --readonly "$L" root     # Passwort ODER Recovery-Key eintippen
```

**Variante B - schreibbar (für Reparaturen) [REVERSIBLE]:**
`cryptsetup open "$L" root` (ohne `--readonly`). Schließen: `cryptsetup close root`.

Recovery-Key: 8 Gruppen à 8 Kleinbuchstaben mit Bindestrichen, genauso tippen.
Er enthält nur Buchstaben, die auf deutscher und US-Tastatur gleich liegen.
Ein Passwort mit Sonderzeichen braucht die richtige Belegung (`loadkeys de-latin1`).

Nur prüfen, ob ein Schlüssel passt (öffnet nichts) **[READ-ONLY]**:
`cryptsetup open --test-passphrase "$L"` → Exit-Code 0 = passt.

## 6. Btrfs-Subvolumes einhängen

```sh
mkdir -p /mnt/top /mnt/sys
mount -o ro,subvolid=5 /dev/mapper/root /mnt/top        # [READ-ONLY] Übersicht
ls /mnt/top                                             # @ @home @log @pkg @snapshots ...
btrfs subvolume list /mnt/top
mount -o ro,subvol=@home /dev/mapper/root /mnt/sys      # nur deine Dateien, lesend
```

Für Reparaturen (Abschnitt 11/12) das ganze System **schreibbar** **[REVERSIBLE]**:

```sh
umount -R /mnt/sys 2>/dev/null
O=compress=zstd:3
mount -o $O,subvol=@          /dev/mapper/root /mnt/sys
mount -o $O,subvol=@home      /dev/mapper/root /mnt/sys/home
mount -o $O,subvol=@log       /dev/mapper/root /mnt/sys/var/log
mount -o $O,subvol=@pkg       /dev/mapper/root /mnt/sys/var/cache/pacman/pkg
mount -o $O,subvol=@snapshots /dev/mapper/root /mnt/sys/.snapshots
mount /dev/disk/by-uuid/<ESP-UUID> /mnt/sys/boot
```

Aushängen am Ende: `umount -R /mnt/sys /mnt/top; cryptsetup close root`.

## 7. Diesen Stick im Live-System einhängen [READ-ONLY]

```sh
mkdir -p /mnt/rec
mount -o ro /dev/disk/by-label/REPO-RECOVERY /mnt/rec
cd /mnt/rec && sha256sum -c SHA256SUMS
```

## 8. Persönliche Dateien sichern [READ-ONLY für die SSD]

Mit Variante A (Abschnitt 5) und `@home` read-only eingehängt:

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,LABEL      # externe Platte finden
mkdir -p /mnt/ext && mount /dev/disk/by-id/<EXTERNE-PLATTE>-part1 /mnt/ext
rsync -aHAX --info=progress2 /mnt/sys/medvidec/ /mnt/ext/laptop-home-$(date +%F)/
```

(`@home` ist `/home`, daher liegt dein Ordner direkt unter `/mnt/sys/medvidec`.)
Auch ältere Stände: `/mnt/top/@snapshots/<n>/snapshot/` ist das System zum
Zeitpunkt von Snapshot `<n>` (ohne /home). Dokumente liegen zusätzlich in
Nextcloud, Code in Git.

## 9. LUKS-Header und Backup prüfen [READ-ONLY]

```sh
L=/dev/disk/by-uuid/<LUKS-UUID>          # wenn der Header kaputt ist: über by-id
                                           # /dev/disk/by-id/<ata-ID-der-REPO-SSD>-part2
cryptsetup isLuks "$L"; echo $?            # 0 = Header lesbar
cryptsetup luksDump "$L" | sed -n '1,12p'  # UUID muss <LUKS-UUID> sein
cryptsetup luksUUID /mnt/rec/luks-header.img          # muss gleich sein
cryptsetup luksDump /mnt/rec/luks-header.img | grep -E '^\s+[0-9]+: luks2|systemd-recovery'
cryptsetup open --test-passphrase --header /mnt/rec/luks-header.img "$L"   # 0 = Backup + Schlüssel passen
```

Das Backup ist vom <Backup-Datum> und enthält **Keyslot 0 (Passwort zu diesem
Zeitpunkt) und Keyslot 1 (Recovery-Key)**. Prüfsumme: `SHA256SUMS`.

## 10. Beschädigten LUKS-Header wiederherstellen [DESTRUCTIVE]

> **Ein LUKS-Header-Restore ist KEIN Snapshot-Restore.** Er ersetzt die
> Schlüsselverwaltung der Partition (alle Keyslots) durch den Stand des
> Backups. Wurde danach ein Passwort geändert, ein Keyslot gelöscht oder ein
> Schlüssel hinzugefügt, gilt nach dem Restore wieder der **alte** Stand -
> neue Passwörter funktionieren nicht mehr, alte wieder. Nur als **letzter
> Ausweg**, wenn `cryptsetup isLuks` fehlschlägt bzw. kein gültiges Passwort
> den Header mehr öffnet.

**Erst der risikofreie Weg - Daten mit dem Backup-Header lesen, ohne die SSD zu ändern [READ-ONLY]:**

```sh
D=/dev/disk/by-id/<ata-ID-der-REPO-SSD>-part2       # by-id, weil by-uuid bei kaputtem Header fehlt
readlink -f "$D"           # Name prüfen, Modell/Größe mit lsblk vergleichen
cryptsetup open --readonly --header /mnt/rec/luks-header.img "$D" root
```

Funktioniert das: zuerst Abschnitt 6 + 8 (Daten sichern). Ganz ohne
Schreibzugriff auf die SSD.

**Erst danach, falls die Partition selbst wieder startfähig werden soll:**

Voraussetzungen (alle müssen erfüllt sein):
1. `luksUUID` des Backups = `<LUKS-UUID>` (die richtige Partition).
2. `cryptsetup open --test-passphrase --header /mnt/rec/luks-header.img "$D"`
   = 0 mit einem Schlüssel, den du **heute** kennst.
3. `readlink -f "$D"` zeigt auf die zweite Partition der <Modell der REPO-SSD>
   (<Größe>) - **nicht** auf die Fedora-SSD.
4. Daten sind gesichert (oder bewusst darauf verzichtet).

Den aktuellen (kaputten) Header-Bereich vorher wegsichern - das ist der
Rückweg **[READ-ONLY für die SSD]**:

```sh
dd if="$D" of=/mnt/ext/damaged-header-$(date +%F).img bs=1M count=16 status=none
```

Dann der eigentliche Restore (fragt mit `YES` nach) **[DESTRUCTIVE, NICHT AUSGEFÜHRT - nur auf Image-Dateien geübt]**:

```sh
cryptsetup luksHeaderRestore "$D" --header-backup-file /mnt/rec/luks-header.img
cryptsetup open --test-passphrase "$D"      # muss jetzt 0 sein
```

Rückweg: `dd if=/mnt/ext/damaged-header-<datum>.img of="$D" bs=1M count=16 conv=fsync`
(schreibt den vorherigen Zustand zurück; ebenfalls DESTRUCTIVE).
Danach: neues Header-Backup anlegen und alte Backups vernichten (Abschnitt 14).

## 11. systemd-boot und UKI reparieren [REVERSIBLE]

Symptom: Bootmenü fehlt, "No bootable device", Kernel-Panic direkt nach dem
Menü, "Failed to mount /sysroot", falscher Kernel.

1. Abschnitt 5 Variante B, Abschnitt 6 "schreibbar" (inkl. `/boot`).
2. Vorher sichern (Rückweg): `cp -a /mnt/sys/boot /mnt/rec-or-ext/boot-copy-$(date +%F)`
   - z.B. auf die externe Platte (der Recovery-Stick ist read-only eingehängt).
3. In das System wechseln: `arch-chroot /mnt/sys`
4. Prüfen **[READ-ONLY]**:
   ```sh
   ls /usr/lib/modules/                       # installierte Kernelversion
   bootctl kernel-inspect /boot/EFI/Linux/arch-linux.efi   # Version im UKI
   cat /etc/kernel/cmdline                    # cryptdevice=PARTUUID=<LUKS-PARTUUID>...
   cat /etc/mkinitcpio.d/linux.preset         # default_uki=/boot/EFI/Linux/arch-linux.efi
   ```
5. UKI neu bauen: `cp /usr/lib/modules/<version>/vmlinuz /boot/vmlinuz-linux && mkinitcpio -P`
6. Bootloader neu installieren (nur wenn er fehlt): `bootctl install`
   (schreibt `/EFI/systemd`, `/EFI/BOOT`, den EFI-Booteintrag).
   `/boot/loader/loader.conf` muss enthalten: `default arch-linux.efi` und `timeout 3`.
7. Snapshot-Einträge neu erzeugen: `/usr/local/lib/workstation/snapshot-boot sync`
   (im chroot; schlägt sie fehl, ist das kein Bootproblem - das Hauptsystem
   bootet auch ohne diese Einträge).
8. `exit`, aushängen (Abschnitt 6), `reboot`.

Notlösung ohne Neubau: `/boot/EFI/workstation/backup/arch-linux.efi` ist eine
ältere Kopie des UKI. Nur verwenden, wenn `bootctl kernel-inspect` dort die
gleiche Kernelversion zeigt wie `ls /mnt/sys/usr/lib/modules`; dann
`cp /mnt/sys/boot/EFI/Linux/arch-linux.efi /mnt/ext/` (Rückweg) und
`cp /mnt/sys/boot/EFI/workstation/backup/arch-linux.efi /mnt/sys/boot/EFI/Linux/arch-linux.efi`.

ESP komplett zerstört (`mkfs.fat` nötig) ist **[DESTRUCTIVE]** und ändert die
ESP-UUID - dann in `/etc/fstab` die `/boot`-UUID anpassen. Nur nach Prüfung,
dass wirklich Partition 1 der REPO-SSD gemeint ist.

## 12. Wiederherstellung aus einem Btrfs-Snapshot

### 12a. Normaler Weg (System startet noch bis zum Bootmenü)

1. Im systemd-boot-Menü (3 s, Pfeiltaste drücken) einen Eintrag
   "Update snapshot ..." oder "Slot n: ..." wählen = **temporärer Snapshot-Boot**.
2. Das System läuft im alten Zustand, alle Änderungen landen im RAM.
3. Oben erscheint ein Hinweisstreifen: "Just test" oder "Restore permanently"
   (Administratorpasswort). Permanent = `system-rollback <n>`.
4. Neu starten. Das alte System liegt als `@broken-<datum>` daneben (Rückweg).

Im Terminal (ebenfalls aus dem Snapshot-Boot oder dem normalen System):
`sudo system-rollback <nummer>` - fragt mit `rollback` nach.
Liste: `sudo snapper -c root list` bzw. `/usr/local/lib/workstation/snapshot-boot status`.

### 12b. Aus dem Arch-Live-System (System startet gar nicht mehr) [REVERSIBLE, NICHT AUSGEFÜHRT]

```sh
# Abschnitt 5 Variante B; dann:
mount -o subvolid=5 /dev/mapper/root /mnt/top
cat /mnt/top/@snapshots/*/info.xml | grep -E '<num>|<date>|<description>'   # Snapshot wählen
N=<nummer>
ls /mnt/top/@snapshots/$N/snapshot/usr/lib/modules     # Kernelversion des Snapshots
btrfs subvolume snapshot /mnt/top/@snapshots/$N/snapshot /mnt/top/@restore-new
rm -f /mnt/top/@restore-new/var/lib/pacman/db.lck      # alte pacman-Sperre im Snapshot
S=$(date +%Y%m%d-%H%M%S)
mv /mnt/top/@ /mnt/top/@broken-$S                      # altes System bleibt erhalten
mv /mnt/top/@restore-new /mnt/top/@
btrfs property set /mnt/top/@broken-$S ro true
```

Dann den Kernel passend machen (Abschnitt 6 schreibbar, `arch-chroot /mnt/sys`,
Abschnitt 11 Schritt 5: `cp /usr/lib/modules/<version>/vmlinuz /boot/vmlinuz-linux && mkinitcpio -P`).

Rückweg (vor dem Neustart oder danach aus dem Live-System):
```sh
mv /mnt/top/@ /mnt/top/@restore-failed-$S
btrfs property set /mnt/top/@broken-$S ro false
mv /mnt/top/@broken-$S /mnt/top/@
```
(und das UKI wieder für den Kernel von `@` bauen, Abschnitt 11.)

## 13. Temporärer Snapshot-Boot vs. permanenter Restore

| | Snapshot-Boot (temporär) | Permanenter Restore |
|---|---|---|
| Wie | Eintrag im Bootmenü | Dialog "Restore permanently", `system-rollback <n>` oder 12b |
| Änderungen am System | keine - Schreibzugriffe nur im RAM | `@` wird durch eine Kopie des Snapshots ersetzt |
| Nach dem Neustart | wieder das normale System | das alte System bleibt `@broken-<datum>` |
| `/home`, `/var/log` | normal, Änderungen bleiben | unverändert |
| Risiko | keines | WLAN-Profile, Bluetooth-Kopplungen, Firewall-Regeln, Pakete aus der Zeit nach dem Snapshot sind weg (liegen in `/etc` und `/var/lib`) |
| Rückweg | einfach normal starten | `@broken-<datum>` zurück nach `@` (12b) |

## 14. Nach einer Wiederherstellung prüfen [READ-ONLY]

```sh
findmnt /                         # /dev/mapper/root[/@]
repo-healthcheck                  # HEALTHY
sudo /usr/local/lib/workstation/snapshot-boot status
sudo btrfs subvolume list / | grep broken
systemctl --failed
sudo cryptsetup luksDump /dev/disk/by-uuid/<LUKS-UUID> | grep -E '^\s+[0-9]+: luks2'
```

Nach einem Header-Restore oder jeder Keyslot-Änderung (`luksAddKey`,
`luksKillSlot`, `luksChangeKey`, `systemd-cryptenroll --wipe-slot`):
neues `cryptsetup luksHeaderBackup` auf diesen Stick (neuer Dateiname),
mit `--test-passphrase --header` prüfen, **alte Backups vernichten** - ein
altes Backup öffnet die Platte mit einem alten Passwort.

Nach einem permanenten Restore: WLAN neu verbinden, Bluetooth neu koppeln,
dann im Repository `./bootstrap.sh`.

## 15. Typische Fehlerbilder

| Fehlerbild | Ursache | Abhilfe |
|---|---|---|
| Passwortabfrage lehnt richtiges Passwort ab | Tastaturbelegung | Recovery-Key versuchen (layoutunabhängig); im Live-System `loadkeys de-latin1` / `loadkeys us` + `--test-passphrase` |
| "No key available with this passphrase" | falscher Schlüssel | Recovery-Key vom Papier; Groß/Klein: Key ist nur Kleinbuchstaben |
| "Device ... is not a valid LUKS device" | Header beschädigt | Abschnitt 9, dann 10 (erst `--header` read-only!) |
| Bootmenü fehlt / Firmware findet nichts | ESP/Bootloader | Abschnitt 11 (`bootctl install`) |
| Kernel-Panic, "Failed to mount" nach Passwort | UKI passt nicht zum System / `@` kaputt | Snapshot-Boot (12a), sonst 11 / 12b |
| "unable to lock database" bei Updates | verwaiste `/var/lib/pacman/db.lck` | nur wenn kein pacman läuft: `sudo rm /var/lib/pacman/db.lck` |
| Login nach 3 Fehlversuchen gesperrt | faillock | 10 min warten oder als root `faillock --user medvidec --reset` |
| SSD wird gar nicht erkannt | Hardware | Header-Backup hilft nicht; Neuinstallation, Daten aus Nextcloud/Git |

## Getestet / nicht getestet

| Verfahren | Status |
|---|---|
| Snapshot-Boot aus dem Bootmenü | **getestet** auf diesem Laptop (2026-10-14) |
| Permanenter Restore über Dialog + `system-rollback` | **getestet** auf diesem Laptop (2026-10-14) |
| Recovery-Key + Passwort mit `--test-passphrase` | **getestet** (<Backup-Datum>) |
| Header-Backup: Byte-Vergleich mit der SSD, `--test-passphrase --header` | **getestet** (<Backup-Datum>) |
| Recovery-Key an der echten Boot-Passwortabfrage | **NICHT AUSGEFÜHRT** (kein Neustart erlaubt); auf Image-Datei geübt |
| Header-Restore | **NICHT AUSGEFÜHRT** - nur auf Image-Dateien geübt |
| Live-System: Entsperren, Einhängen, chroot, `mkinitcpio -P`, `bootctl install` | **NICHT AUSGEFÜHRT** auf diesem Laptop (Standard-Arch-Werkzeuge) |
| Manueller Restore aus dem Live-System (12b) | **NICHT AUSGEFÜHRT** (entspricht den Schritten von `system-rollback`) |
