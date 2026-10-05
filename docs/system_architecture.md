# System Architecture

## 1. Projektziel

Dieses Projekt definiert ein eigenes, minimalistisches Arch-Linux-System mit Hyprland und Quickshell.

Das System soll für den täglichen Einsatz auf einem Laptop geeignet sein und insbesondere auf älterer Hardware sehr schnell und direkt reagieren.

Hauptziele:

- hohe subjektive Responsiveness
- niedrige Input-Latenz
- geringe Idle-CPU-Last
- geringe GPU-Last
- moderater RAM-Verbrauch
- gute Akkulaufzeit
- zuverlässige Laptop-Funktionalität
- reproduzierbare Installation
- einfache Wartbarkeit
- konsistente Desktop-Oberfläche
- möglichst wenig unnötige Hintergrunddienste

Omarchy Quattro dient als wichtige Referenz für funktionierende Desktop-Workflows und die visuelle Gestaltung.

Das Ziel ist jedoch ausdrücklich **keine Omarchy-Distribution** und kein Fork von Omarchy.

Es entsteht ein eigenes Arch-Linux-System.

---

# 2. Leitprinzip

Das zentrale Architekturprinzip lautet:

> Use proven components. Configure instead of reinventing.

Wenn eine etablierte Linux-Komponente ein Problem bereits zuverlässig löst, soll diese verwendet und passend konfiguriert werden.

Eigener Code wird hauptsächlich für folgende Bereiche geschrieben:

- Desktop-UI
- Integration bestehender Komponenten
- Automatisierung
- kleine fehlende Workflows
- projektspezifische Konfiguration

Nicht für bereits gelöste Infrastrukturprobleme.

---

# 3. Was "minimal" bedeutet

Minimal bedeutet in diesem Projekt nicht:

> möglichst wenige installierte Pakete

sondern:

> möglichst wenig unnötige Komplexität.

Ein bewährter Daemon mit etwas höherem RAM-Verbrauch ist einer fragilen Eigenimplementierung vorzuziehen.

Prioritäten:

```text
Reliability
    ↓
Responsiveness
    ↓
Maintainability
    ↓
Resource usage
    ↓
Package count
```

Paketanzahl allein ist kein Optimierungsziel.

---

# 4. High-Level Architecture

Das System besteht aus klar getrennten Schichten:

```text
┌───────────────────────────────────────┐
│              Applications             │
├───────────────────────────────────────┤
│                                       │
│              Quickshell               │
│                                       │
│  Bar · Launcher · Applets · OSD · UI  │
│                                       │
├───────────────────────────────────────┤
│              Hyprland                 │
│                                       │
│       Wayland compositor / WM         │
│                                       │
├───────────────────────────────────────┤
│          Linux User Services          │
│                                       │
│ Network · Audio · Bluetooth · etc.    │
│                                       │
├───────────────────────────────────────┤
│               systemd                 │
├───────────────────────────────────────┤
│             Linux Kernel              │
├───────────────────────────────────────┤
│               Hardware                │
└───────────────────────────────────────┘
```

Jede Schicht soll möglichst klar definierte Aufgaben besitzen.

---

# 5. Base System

Basis:

```text
Arch Linux
systemd
Linux kernel
Wayland
Hyprland
Quickshell
```

Arch Linux bleibt möglichst nah am Upstream.

Das Projekt soll keine eigene Paketdistribution auf Arch aufbauen.

Systempakete werden nach Möglichkeit direkt aus:

```text
official Arch repositories
```

bezogen.

AUR-Pakete werden nur verwendet, wenn ein sinnvoller Grund dafür besteht.

---

# 6. Rolling Release

Das System bleibt ein normales Arch-Linux-Rolling-Release-System.

Es soll kein eigener komplexer Update-Layer entstehen.

Standard:

```text
pacman
```

bleibt der primäre Paketmanager.

Das System soll möglichst wenig eigene Magie zwischen Benutzer und Arch Linux einführen.

---

# 7. Package Policy

Jedes Paket muss einen nachvollziehbaren Zweck erfüllen.

Bevorzugt werden Pakete, die:

- etabliert sind
- aktiv gepflegt werden
- gut dokumentiert sind
- auf Arch Linux verbreitet sind
- Wayland nativ unterstützen
- wenig zusätzliche Infrastruktur benötigen

Vermeiden:

- mehrere Tools für dieselbe Aufgabe
- unnötige Frameworks
- redundante Daemons
- große Abhängigkeiten für triviale Funktionen
- eigene Implementierungen etablierter Systemfunktionen

---

# 8. Package Categories

Pakete sollen im Repository nach Funktion gruppiert werden.

Beispiel:

```text
packages/
├── base
├── desktop
├── graphics
├── audio
├── network
├── bluetooth
├── power
├── fonts
├── utilities
├── applications
└── development
```

Dadurch soll nachvollziehbar bleiben, warum ein Paket installiert wird.

---

# 9. Core Desktop Stack

Geplanter Desktop-Stack:

```text
Hyprland
Quickshell
PipeWire
WirePlumber
NetworkManager
BlueZ
```

Weitere Komponenten werden ergänzt, sobald ihre konkrete Aufgabe definiert wurde.

---

# 10. Hyprland

Hyprland ist:

```text
Wayland compositor
window manager
input/window orchestration layer
```

Hyprland soll möglichst wenig zusätzliche visuelle Arbeit durchführen.

Das Ziel ist ein sehr direkt reagierender Desktop.

---

# 11. Hyprland Performance Baseline

Initial:

```text
animations       OFF
blur             OFF
heavy shadows    OFF
heavy effects    OFF
```

Transparenz nur dort, wo sie praktisch kostenlos ist und visuell sinnvoll erscheint.

Diese Konfiguration bildet die Performance-Baseline.

---

# 12. Animation Policy

Animationen sind opt-in.

Nicht opt-out.

Neue Komponenten werden zunächst ohne Animation implementiert.

Danach darf eine Animation hinzugefügt werden, wenn sie:

1. funktionalen oder deutlichen visuellen Nutzen besitzt
2. sehr kurz ist
3. keine Bedienung verzögert
4. keine relevante permanente GPU-Last erzeugt

Besonders folgende Aktionen sollen unmittelbar wirken:

```text
workspace switching
launcher opening
panel opening
window focus
window movement
application switching
```

---

# 13. Responsiveness

Subjektive Geschwindigkeit ist ein primäres Qualitätsmerkmal.

Ziel:

```text
input
  ↓
immediate visible result
```

Nicht:

```text
input
  ↓
animation
  ↓
transition
  ↓
result
```

UI-Animationen dürfen niemals zum künstlichen Bottleneck einer schnellen Operation werden.

---

# 14. Quickshell

Quickshell bildet die Desktop-Shell.

Sie soll langfristig eine konsistente Oberfläche bereitstellen für beispielsweise:

```text
bar
launcher
notifications
OSD
system applets
power menu
lock-related UI
```

Nicht jede dieser Komponenten muss von Anfang an vorhanden sein.

Das System soll inkrementell aufgebaut werden.

---

# 15. Quickshell ist keine Systemschicht

Quickshell darf nicht Voraussetzung für grundlegende Systemfunktionalität sein.

Beispiel:

```text
Quickshell running
    ↓
nice graphical controls

Quickshell crashed
    ↓
system still works
```

Folgende Dinge müssen unabhängig von Quickshell funktionieren:

```text
networking
audio
Bluetooth
power management
VPN
suspend
system services
```

---

# 16. Thin Shell Principle

Quickshell soll primär:

```text
display state
receive user input
call established backend
react to backend events
```

Nicht:

```text
implement network stack
implement audio stack
implement Bluetooth stack
maintain duplicate system state
```

---

# 17. Stateless Shell

Persistenter Systemzustand gehört dem jeweiligen Backend.

Beispiel:

```text
Quickshell
     │
     │ reads / controls
     ▼
system service
     │
     │ owns
     ▼
persistent state
```

Quickshell darf UI-State besitzen, beispielsweise:

```text
currently selected tab
expanded row
open popup
hover state
```

Sie soll aber keine zweite Systemdatenbank aufbauen.

---

# 18. Shared Design System

Die gesamte Quickshell-Oberfläche verwendet eine gemeinsame Designsprache.

Keine einzelnen Applets mit unabhängig entwickelten Styles.

Zentrale Definitionen für:

```text
colors
typography
spacing
corner radius
icon sizes
row heights
panel sizes
hover states
focus states
error states
disabled states
```

---

# 19. Omarchy as Reference

Omarchy Quattro darf als Referenz und Codequelle verwendet werden, wenn eine dort vorhandene Lösung:

- gut funktioniert
- visuell zum Projekt passt
- technisch sauber isolierbar ist
- keine unnötige Omarchy-Infrastruktur voraussetzt

Bevor etwas neu implementiert wird, soll geprüft werden, ob Omarchy bereits eine gute Lösung besitzt.

---

# 20. No Blind Copying

Omarchy-Code wird nicht blind übernommen.

Vor Übernahme prüfen:

```text
What does it do?
What does it depend on?
Is it Omarchy-specific?
Is there an upstream solution?
Can it be simplified?
Does it fit our architecture?
```

Nur der tatsächlich benötigte Teil wird übernommen.

---

# 21. Omarchy Components Are Not Dependencies

Das fertige System soll nicht darauf angewiesen sein, dass eine vollständige Omarchy-Installation vorhanden ist.

Wenn Omarchy-Code übernommen wird, soll dieser:

```text
vendored
adapted
documented
```

oder durch eine direkte Upstream-Abhängigkeit ersetzt werden.

Das System bleibt ein eigenständiges Arch Linux.

---

# 22. System Services

Bewährte Linux-Dienste bilden die eigentliche Systemfunktionalität.

Beispiele:

```text
Networking
→ NetworkManager

Audio
→ PipeWire + WirePlumber

Bluetooth
→ BlueZ

Service management
→ systemd

Session/power actions
→ systemd-logind

VPN
→ established VPN backend
```

Weitere Backends werden pro Feature ausgewählt.

---

# 23. One Owner per Responsibility

Für jede Aufgabe soll möglichst genau eine Komponente verantwortlich sein.

Vermeiden:

```text
two network managers
two audio session managers
two notification daemons
multiple competing power managers
duplicate autostart mechanisms
```

Eine Funktion hat einen klaren Owner.

---

# 24. Process Ownership

Prozesse sollen durch die richtige Schicht gestartet werden.

Grundregel:

```text
system daemon
→ systemd system service

user daemon
→ systemd user service

Hyprland/session-specific process
→ session lifecycle

temporary UI helper
→ Quickshell / script
```

Keine zufällige Mischung aus:

```text
exec-once
systemd
shell profile
XDG autostart
custom startup script
```

für denselben Prozess.

Wer einen Prozess startet, beendet ihn auch: Hyprlands Session-Lifecycle
startet seine Helper bei `hyprland.start` und beendet sie bei
`hyprland.shutdown` (`session-stop`, roles/hyprland) - solange das
Display noch existiert, zusammen mit den Wayland-gebundenen Portal-Units.
Ohne diesen geordneten Stopp liefen die Helper beim Logout in ihren
Exit-Pfad gegen eine tote Wayland-Verbindung und erzeugten Coredumps.
Reboot/Shutdown aus dem Power-Menü beenden deshalb zuerst die Session
wie ein Logout.

---

# 25. systemd

systemd ist die zentrale Service- und Lifecycle-Infrastruktur.

Keine eigene Service-Verwaltung bauen.

Nutzen:

```text
system services
user services
timers where appropriate
logind
journald
```

Services sollen nur aktiviert werden, wenn sie tatsächlich benötigt werden.

---

# 26. Logging

Systemfehler sollen über etablierte Logging-Infrastruktur nachvollziehbar sein.

Primär:

```text
journalctl
```

Eigene Komponenten dürfen strukturierte Logs schreiben.

Keine eigene komplexe Logging-Plattform.

---

# 27. CLI First-Class

Das System bleibt vollständig als normales Linux-System administrierbar.

Die grafische Shell ist Convenience, kein Gatekeeper.

Beispiele:

```text
systemctl
journalctl
nmcli
ip
wpctl
bluetoothctl
```

sollen weiterhin funktionieren.

---

# 28. Advanced GUI Fallbacks

Nicht jede seltene Einstellung muss in Quickshell implementiert werden.

Für komplexe Spezialfälle dürfen etablierte Tools verwendet werden.

Prinzip:

```text
common workflow
→ integrated shell UI

advanced rare workflow
→ proven administration tool
```

Dadurch bleibt die Shell klein.

---

# 29. IPC Strategy

Für die Kommunikation zwischen Shell und Backend gilt folgende Priorität:

```text
1. native Quickshell integration
2. D-Bus
3. stable IPC/API
4. established CLI
5. small helper script
```

Nicht jede CLI-Nutzung ist schlecht.

Problematisch ist vor allem unnötiges permanentes Prozess-Spawning.

---

# 30. Event-Driven First

Das System soll event-driven arbeiten, wo dies sinnvoll möglich ist.

Bevorzugt:

```text
backend event
     ↓
D-Bus / IPC
     ↓
shell update
```

Vermeiden:

```text
timer
 ↓
spawn process
 ↓
parse output
 ↓
sleep
 ↓
repeat
```

---

# 31. Polling Policy

Polling ist erlaubt, wenn:

- keine sinnvolle Event-Schnittstelle existiert
- die Information nur temporär benötigt wird
- die Frequenz angemessen ist

Polling soll nach Möglichkeit an UI-Sichtbarkeit gebunden werden.

Beispiel:

```text
panel closed
→ monitoring stopped

panel open
→ monitoring active
```

---

# 32. Idle Philosophy

Im Idle soll das System möglichst ruhig sein.

Ziel:

```text
no unnecessary wakeups
no continuous animation
no unnecessary polling
no repeated shell processes
no permanent diagnostics
```

Eine umfangreiche Shell darf existieren, solange sie im Idle kaum Arbeit verursacht.

---

# 33. Performance Measurement

Performance wird gemessen, nicht geraten.

Relevante Größen:

```text
idle CPU usage
idle RAM
GPU utilization
GPU clocks
system wakeups
frame timing
input latency
battery consumption
thermal behavior
```

Optimierungen sollen nach Möglichkeit auf Messungen basieren.

---

# 34. No Performance Cargo Cult

Keine Sammlung zufälliger "Arch performance tweaks" übernehmen.

Jede Optimierung braucht:

```text
problem
measurement
change
measurement
result
```

Wenn kein messbarer oder wahrnehmbarer Vorteil besteht, wird die Änderung verworfen.

---

# 35. Target Hardware

Das System soll insbesondere auf älteren ThinkPad-/Ultrabook-Systemen mit integrierter Intel-Grafik gut funktionieren.

Optimierungsannahmen:

```text
mobile CPU
integrated GPU
limited cooling
battery operation
limited GPU performance
```

Das System darf moderne Hardware nutzen, soll diese aber nicht voraussetzen.

---

# 36. Bare-Metal Validation

VMs dürfen für Entwicklung und schnelle Iteration verwendet werden.

Eine VM ist jedoch nicht die Referenz für:

```text
GPU performance
frame pacing
display behavior
battery life
suspend/resume
thermal behavior
touchpad behavior
Wi-Fi behavior
```

Diese Funktionen müssen regelmäßig auf Bare Metal getestet werden.

---

# 37. Development Environment

Empfohlener Entwicklungsprozess:

```text
Git repository
      │
      ▼
Arch test VM
      │
      ▼
fast iteration
      │
      ▼
bare-metal test
      │
      ▼
commit known-good state
```

Dadurch kann das System schrittweise aufgebaut werden, ohne den produktiven Laptop ständig neu installieren zu müssen.

---

# 38. Reproducibility

Ein frisches Arch-System soll möglichst automatisiert in den gewünschten Zustand gebracht werden können.

Das Repository ist die Source of Truth für:

```text
package selection
configuration
shell
scripts
services
themes
installation steps
```

Keine wichtigen Änderungen sollen ausschließlich manuell dokumentiert sein.

---

# 39. Bootstrap

Langfristiges Ziel:

```text
fresh Arch install
      ↓
clone repository
      ↓
run bootstrap
      ↓
install packages
      ↓
deploy configuration
      ↓
enable required services
      ↓
reboot/login
      ↓
working desktop
```

Der Bootstrap soll verständlich bleiben.

Kein komplexes eigenes Installationsframework, wenn einfache Shell-Skripte ausreichen.

---

# 40. Idempotency

Installations- und Setup-Skripte sollen nach Möglichkeit mehrfach ausführbar sein.

Beispiel:

```text
package already installed
→ skip

service already enabled
→ no problem

config already linked
→ verify/update
```

Ein zweiter Lauf darf das System nicht beschädigen.

---

# 41. Configuration Management

Konfiguration liegt im Git-Repository.

Beispiel:

```text
config/
├── hypr/
├── quickshell/
├── systemd/
├── applications/
└── ...
```

Deployment kann beispielsweise über:

```text
symlinks
stow
small install scripts
```

erfolgen.

Die konkrete Methode soll einfach und transparent bleiben.

---

# 42. User Overrides

Das System soll lokale Anpassungen ermöglichen, ohne dass diese bei Updates überschrieben werden.

Bevorzugtes Muster:

```text
project defaults
      +
optional local overrides
```

Beispiel:

```text
config/hypr/default.conf
~/.config/hypr/local.conf
```

Der genaue Mechanismus wird pro Komponente definiert.

---

# 43. Secrets

Secrets gehören nicht ins Git-Repository.

Dazu gehören:

```text
Wi-Fi passwords
VPN credentials
private keys
API tokens
personal certificates where inappropriate
```

Diese werden durch die zuständigen Systemkomponenten oder Secret Stores verwaltet.

---

# 44. Hardware-Specific Configuration

Hardware-spezifische Einstellungen sollen vom allgemeinen Desktop getrennt bleiben.

Beispiel:

```text
hardware/
├── generic/
├── intel/
└── thinkpad/
```

Nicht jede Hardware benötigt dieselben Tweaks.

---

# 45. Hardware Detection

Automatische Hardware-Erkennung darf verwendet werden, wenn sie einfach und zuverlässig ist.

Keine große Hardware-Abstraktionsschicht bauen.

Wenn drei klare Konfigurationsprofile ausreichen, sind diese einer komplexen Detection Engine vorzuziehen.

---

# 46. Power Management

Power Management soll zunächst mit bewährten Standardkomponenten umgesetzt werden.

Keine parallelen Power-Management-Systeme ohne konkreten Grund.

Auswahl erfolgt anhand von:

```text
hardware compatibility
battery life
performance behavior
suspend reliability
```

Insbesondere GPU- und CPU-Powersaving darf die Desktop-Responsiveness nicht unnötig beeinträchtigen.

---

# 47. Performance vs Battery

Das Ziel ist nicht maximale Benchmark-Performance.

Das Ziel ist:

> maximum useful responsiveness per watt.

Der Laptop soll sich schnell anfühlen, ohne unnötig hohe Taktraten und Leistungsaufnahme zu erzwingen.

Wenn aggressives Powersaving sichtbares Stuttering verursacht, soll ein sinnvoller Mittelweg gewählt werden.

---

# 48. Graphics

Primärer Zielpfad:

```text
Wayland
    ↓
Hyprland
    ↓
Mesa
    ↓
DRM/KMS
    ↓
GPU
```

Native Wayland-Anwendungen werden bevorzugt.

XWayland bleibt als Compatibility Layer für Anwendungen verfügbar, die Wayland nicht nativ unterstützen.

---

# 49. Display Configuration

Display-Konfiguration soll möglichst einfach bleiben.

Besonders beachten:

```text
internal laptop display
external monitors
HiDPI
fractional scaling
refresh rate
docking
```

Performance-intensive Scaling-Konfigurationen sollen auf der tatsächlichen Hardware getestet werden.

---

# 50. Audio

Standard:

```text
PipeWire
WirePlumber
```

Keine eigene Audio-Infrastruktur.

Die Shell stellt lediglich Controls bereit.

Audio muss auch ohne Quickshell vollständig funktionieren.

---

# 51. Networking

Standard:

```text
NetworkManager
```

Netzwerkzuverlässigkeit ist eine Kernanforderung des Systems.

Der Netzwerk-Stack wird nicht aus Minimalismus-Gründen durch eigene Skripte ersetzt.

Detaillierte Netzwerk- und Wi-Fi-Anforderungen gehören in separate Spezifikationen.

---

# 52. Bluetooth

Standard:

```text
BlueZ
```

Die Shell stellt eine Oberfläche bereit.

Pairing und Geräteverwaltung bleiben Aufgabe von BlueZ.

---

# 53. Notifications

Es soll genau eine klare Notification-Architektur geben.

Keine parallel laufenden konkurrierenden Notification-Daemons.

Die konkrete Implementierung wird separat spezifiziert.

Sie muss zum Quickshell-Designsystem passen.

---

# 54. OSD

Volume, Brightness und ähnliche kurzfristige Zustände sollen über eine gemeinsame OSD-Komponente dargestellt werden.

Beispiel:

```text
volume
brightness
microphone
keyboard backlight
```

Keine separate visuelle Implementierung für jede Aktion.

---

# 55. Launcher

Der Launcher soll:

```text
open instantly
search instantly
close instantly
```

Performance hat höhere Priorität als visuelle Effekte.

Keine Startanimation, die die wahrgenommene Öffnungszeit erhöht.

Die genaue Such- und Indexierungsarchitektur wird separat definiert.

---

# 56. Bar

Die Bar soll primär Status und Einstiegspunkte liefern.

Sie darf nicht zum permanenten Systemmonitor werden.

Vermeiden:

```text
high-frequency CPU graphs
high-frequency network graphs
constant sensor polling
```

Temporäre Detailinformationen gehören in Applets.

---

# 57. Fonts and Icons

Fonts und Icons sollen zentral ausgewählt werden.

Keine Applet-spezifischen Icon-Sammlungen.

Ziele:

```text
consistent appearance
good Wayland rendering
good HiDPI behavior
small dependency surface
```

---

# 58. Themes

Das Theme-System soll zentral sein.

Ein Theme definiert mindestens:

```text
background
foreground
accent
muted
error
warning
success
border
```

Quickshell-Komponenten beziehen ihre Farben ausschließlich aus dem zentralen Theme.

---

# 59. Application Theming

Wenn sinnvoll, kann das zentrale Theme auf Anwendungen übertragen werden.

Dies ist jedoch sekundär gegenüber:

```text
reliability
performance
desktop consistency
```

Es soll kein kompliziertes Theme-Framework entstehen, nur um jede Anwendung pixelgenau gleich aussehen zu lassen.

---

# 60. Security

Das System soll Arch-/Linux-Standardmechanismen respektieren.

Keine pauschalen Security-Deaktivierungen zur Performance-Steigerung.

Privilege Escalation soll klar kontrolliert sein.

Systemänderungen, die Root-Rechte benötigen, sollen über etablierte Mechanismen erfolgen.

---

# 61. Privileged Operations

Quickshell selbst soll möglichst nicht mit erhöhten Rechten laufen.

Wenn eine Aktion Root-Rechte benötigt:

```text
Quickshell
    ↓
approved privileged mechanism
    ↓
system action
```

Nicht:

```text
run entire shell as root
```

---

# 62. Failure Isolation

Subsysteme sollen unabhängig ausfallen können.

Beispiele:

```text
Quickshell crash
→ Hyprland continues

Quickshell crash
→ network continues

Quickshell crash
→ audio continues

Bluetooth UI crash
→ Bluetooth backend continues

Launcher crash
→ compositor continues
```

Ein UI-Fehler darf möglichst nicht zum Systemfehler werden.

---

# 63. Debuggability

Das System soll leicht debugbar bleiben.

Ein Entwickler soll nachvollziehen können:

```text
which process owns this?
which service manages this?
where is its config?
where are its logs?
```

Keine versteckten State Machines oder unnötigen Abstraktionslayer.

---

# 64. Documentation

Jedes größere Subsystem erhält eine eigene Spezifikation.

Beispiel:

```text
docs/
├── ARCHITECTURE.md
├── DESIGN_SYSTEM.md
├── WIFI_APPLET.md
├── AUDIO.md
├── BLUETOOTH.md
├── POWER.md
├── LAUNCHER.md
└── ...
```

`ARCHITECTURE.md` definiert die systemweiten Regeln.

Subsystem-Dokumente dürfen diesen Regeln nicht widersprechen.

---

# 65. Repository Structure

Mögliche Ausgangsstruktur:

```text
.
├── README.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DESIGN_SYSTEM.md
│   └── ...
│
├── packages/
│   ├── base
│   ├── desktop
│   ├── audio
│   ├── network
│   └── ...
│
├── config/
│   ├── hypr/
│   ├── quickshell/
│   └── ...
│
├── systemd/
│   ├── system/
│   └── user/
│
├── scripts/
│   ├── install/
│   ├── helpers/
│   └── diagnostics/
│
├── hardware/
│   ├── generic/
│   └── thinkpad/
│
└── bootstrap.sh
```

Diese Struktur ist ein Ausgangspunkt und kein Dogma.

---

# 66. Agent Development Rules

Ein Coding-Agent, der an diesem Repository arbeitet, soll vor Implementierung eines Features:

1. prüfen, ob eine etablierte Linux-Komponente die Funktion bereits bereitstellt
2. prüfen, ob Omarchy Quattro bereits eine geeignete Implementierung besitzt
3. Abhängigkeiten der vorhandenen Lösung verstehen
4. die kleinste robuste Lösung wählen
5. keine parallele State-Verwaltung einführen
6. Event-Schnittstellen gegenüber Polling bevorzugen
7. vorhandene gemeinsame UI-Komponenten verwenden
8. Performance im Idle berücksichtigen
9. bestehende Architekturentscheidungen respektieren

---

# 67. Agent Anti-Patterns

Ein Agent soll nicht ohne ausdrücklichen Grund:

```text
invent a new daemon
invent a new state database
add a framework
add permanent polling
duplicate an existing Linux service
enable unnecessary services
add animations by default
introduce a second package manager
create hidden system state
```

---

# 68. Dependency Review

Neue Dependencies sollen begründet werden.

Vor Hinzufügen:

```text
What problem does it solve?

Is it already available through an installed component?

Is there a standard Arch/Linux solution?

Will it run permanently?

What is its idle cost?

Does it introduce another daemon?

Can it be removed without breaking unrelated features?
```

---

# 69. Feature Development Process

Features werden möglichst vertikal entwickelt.

Beispiel:

```text
define requirement
      ↓
choose backend
      ↓
implement minimal integration
      ↓
verify functionality
      ↓
verify failure behavior
      ↓
measure performance
      ↓
apply shared UI design
      ↓
bare-metal test
```

Nicht zuerst eine große abstrakte Plattform bauen.

---

# 70. Optimization Process

Performance-Optimierung folgt:

```text
measure
  ↓
identify bottleneck
  ↓
change
  ↓
measure again
```

Keine Optimierung aufgrund bloßer Vermutung.

---

# 71. Definition of Done

Ein Systemfeature gilt erst als fertig, wenn:

- die Kernfunktion zuverlässig funktioniert
- der Backend-Owner klar ist
- die Shell keinen unnötigen persistenten State besitzt
- Fehler nachvollziehbar sind
- keine unnötigen permanenten Prozesse entstanden sind
- das Feature mit dem gemeinsamen Designsystem funktioniert
- die Funktion über Reboot/Login hinweg korrekt funktioniert
- die relevanten Konfigurationen im Repository liegen
- die Funktion dokumentiert ist
- die Funktion auf echter Hardware getestet wurde, wenn Hardware relevant ist

---

# 72. System Acceptance Goals

Das fertige System soll sich im Alltag folgendermaßen verhalten:

```text
Boot
 ↓
Login
 ↓
Hyprland appears quickly
 ↓
Quickshell is immediately usable
 ↓
network/audio/Bluetooth are ready
 ↓
launcher opens instantly
 ↓
workspace switching is instantaneous
 ↓
idle system remains quiet
```

Der Benutzer soll möglichst selten bemerken, dass im Hintergrund Desktop-Infrastruktur arbeitet.

---

# 73. Non-Goals

Das Projekt versucht ausdrücklich nicht:

- eine neue Linux-Distribution zu entwickeln
- Arch Linux zu verstecken
- einen eigenen Paketmanager zu bauen
- systemd zu ersetzen
- bestehende Linux-Subsysteme neu zu implementieren
- Omarchy vollständig zu forken
- maximale visuelle Effekte zu liefern
- Benchmark-Rekorde zu erzielen
- jede Linux-Einstellung über eine GUI zugänglich zu machen

---

# 74. Primary Design Trade-Off

Bei Konflikten gilt grundsätzlich:

```text
reliable and simple
        >
clever and custom
```

und:

```text
instant interaction
        >
decorative animation
```

sowie:

```text
proven upstream component
        >
home-grown replacement
```

---

# 75. Guiding Principles

```text
Arch stays Arch.

Hyprland manages windows.

Quickshell manages presentation.

System services manage system state.

Use proven components.

Configure before reinventing.

Keep the shell stateless.

Prefer events over polling.

Do work only when needed.

Animations are opt-in.

Measure performance.

Optimize for real hardware.

Keep everything understandable.

Keep everything replaceable.
```
