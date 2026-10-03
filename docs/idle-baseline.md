# Idle Baseline (arch-dev, Clean Rebuild)

Referenzwerte aus einem vollständigen Clean-VM-Rebuild-Audit (arch-dev,
VirtualBox-Testumgebung) nach erfolgreichem `./bootstrap.sh` und
laufender Hyprland/Quickshell-Session, Desktop im Leerlauf, keine
Benutzerinteraktion. Stand: 2026-10-03, Commit 63b58e2.

Zweck: Referenzpunkt für spätere Features, nicht harte
Performance-Grenzwerte. Einzelne CPU-Samples sind kein Beweis - relevant
sind strukturelle Abweichungen (neue Daemons, Polling, doppelte
Prozesse), nicht Prozent-Schwankungen.

## Prozesse (je genau einmal, kein Polling beobachtet)

| Prozess            | CPU (idle) | RSS     |
|---------------------|-----------|---------|
| Hyprland            | ~0.4%     | ~145 MB |
| quickshell          | ~0.2%     | ~305 MB (frisch gestartet nach Notifications v1 + FiraCode: ~366 MB; nach vielen Hot-Reloads beobachtet bis ~460 MB) |
| wireplumber         | 0.0%      | ~24 MB  |
| hyprpolkitagent     | 0.0%      | ~60 MB  |
| xdg-desktop-portal* (3 Prozesse: core, gtk, hyprland) | 0.0% je | ~20-32 MB je |
| pipewire            | 0.0%      | (im service) |
| pipewire-pulse      | 0.0%      | ~11 MB  |
| ~~mako~~ (seit Notifications v1 entfernt - Quickshell besitzt `org.freedesktop.Notifications` selbst) | - | - |
| hypridle (seit Lock + Idle v1) | 0.0% | ~7 MB |

Lifecycle-Owner für quickshell/hyprpolkitagent/hypridle:
ausschließlich Hyprland (`hl.on("hyprland.start", ...)`), kein
zusätzlicher systemd --user-Service für diese Prozesse. hypridle ist der
einzige persistente Prozess, der nach dieser Baseline dazukam
(ereignisgesteuert über ext-idle-notify, kein Polling). hyprlock läuft
nur während gesperrt ist (arch-dev mit Software-Rendering: ~215 MB RSS
solange gesperrt, danach 0).

## systemd --user (idle)

17 aktive Units, ausschließlich D-Bus-aktivierte Standarddienste
(PipeWire-Stack, xdg-desktop-portal-Stack, dconf, gvfs, at-spi).
**0 Timer.**

## systemd (System) Timer

Nur Standard-Arch-Timer (`fstrim.timer`, `systemd-tmpfiles-clean.timer`,
`shadow.timer`, `archlinux-keyring-wkd-sync.timer`) - keine durch dieses
Repo neu hinzugekommenen Timer oder Polling-Loops.

## Bekannte Nicht-Probleme

- `quickshell`-RSS (~300 MB) ist für eine QtQuick/QML-Shell mit
  geladenen Fonts/Icons im normalen Bereich, kein Leak-Indikator ohne
  Vergleichswert über Zeit.
- arch-dev läuft Ghostty/Quickshell mit `LIBGL_ALWAYS_SOFTWARE=1`
  (VirtualBox-GPU-Workaround, siehe `host_vars/arch-dev.yml`) - dieser
  Workaround ist VM-spezifisch und erhöht die CPU-Last hier etwas
  gegenüber echter GPU-Beschleunigung auf Laptop/Workstation.

## Clean Rebuild + Integration Audit v2 (2026-10-03, commit e7bf806+)

Frische VM, ein `./bootstrap.sh` (ok=67 changed=44 failed=0), Reboot,
TTY-Login + `Hyprland`, Messung ~2 min nach Login, 30 s CPU-Fenster:

| Prozess | CPU (30 s) | RSS |
|---|---|---|
| Hyprland | 0.0% | ~142 MB |
| quickshell (Bar, Launcher, Power Menu, Notifications, Tray, Theme) | 0.0% | ~254 MB |
| hypridle | 0.0% | ~6 MB |
| hyprpolkitagent | 0.0% | ~55 MB |
| wireplumber / pipewire | 0.0% | ~22 / ~12 MB |

Gegenüber der ersten Baseline: mako entfällt (Quickshell ist Notification-
Owner), hypridle kam dazu; Quickshell liegt frisch *unter* dem alten Wert
(~305 MB) - die früher beobachteten 370-570 MB stammten aus vielen Hot
Reloads in einer langen Session. 0 User-Timer, 12 aktive User-Services
(D-Bus-aktivierte Standarddienste), nur die 4 Arch-System-Timer.

## Bluetooth v1 (2026-10-03)

`bluetoothd` (BlueZ, systemd system service) is the one new permanent
process - but only where Bluetooth exists: the unit's
`ConditionPathIsDirectory=/sys/class/bluetooth` keeps it from running on
a machine without an adapter (fresh arch-dev boot: enabled, inactive,
0 processes). Measured on arch-dev after the `bluetooth` kernel module
had been loaded (no controller): ~6 MB RSS, 0 CPU ticks over 30 s.
Quickshell's Bluetooth slot/popup add no process; the pairing agent
exists only while pairing. Real-adapter numbers (scan off, devices
paired/connected) still to be taken on laptop/workstation.

