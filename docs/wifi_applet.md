# Wi-Fi Applet Design & Architecture

## 1. Ziel

Das Wi-Fi Applet ist Teil einer performanten, konsistenten Quickshell-Oberfläche für ein minimalistisches Arch-Linux-/Hyprland-System.

Das Applet soll sich funktional und visuell stark am Netzwerk-Applet von Omarchy Quattro orientieren, da dessen Wi-Fi-Workflow im Alltag bereits zuverlässig funktioniert.

Der Fokus liegt auf:

- zuverlässiger NetworkManager-Integration
- sehr geringer Idle-Last
- klarer und schneller Bedienung
- guter Unterstützung für:
  - normale WPA/WPA2/WPA3-Netzwerke
  - WPA Enterprise / eduroam
  - offene Netzwerke
  - Captive Portals
- Wiederverwendung etablierter Linux-Komponenten
- stateless Shell-Architektur
- einheitlichem UI-Design im gesamten Betriebssystem

Die Shell verwaltet keinen eigenen Netzwerkzustand.

NetworkManager ist die einzige Source of Truth.

---

# 2. Grundprinzipien

## 2.1 Proven software first

Keine Netzwerkfunktionalität neu implementieren, wenn ein bewährtes Systempaket bereits eine robuste Lösung bereitstellt.

Bevorzugte Architektur:

```text
Quickshell
    │
    │ UI / Presentation
    ▼
NetworkManager
    │
    ├── Wi-Fi
    ├── Ethernet
    ├── DHCP
    ├── Static IP
    ├── DNS
    ├── 802.1X
    └── VPN
```

Quickshell soll lediglich:

- Systemzustand darstellen
- NetworkManager-Aktionen auslösen
- NetworkManager-Signale beobachten
- Eingaben an bestehende Tools weitergeben

---

## 2.2 Stateless Shell

Die Shell besitzt keine eigene Datenbank für:

- bekannte WLANs
- Passwörter
- IP-Adressen
- DNS-Konfiguration
- Verbindungsstatus
- VPN-Zustand

Alle dauerhaften Informationen werden durch die jeweiligen Backend-Komponenten verwaltet.

Für Wi-Fi ist dies NetworkManager.

Wenn Quickshell beendet oder ersetzt wird, muss das Netzwerk weiterhin vollständig funktionieren.

---

## 2.3 Event driven first

Polling soll vermieden werden.

Bevorzugt:

```text
NetworkManager
      │
      │ D-Bus signal
      ▼
Quickshell
      │
      ▼
UI update
```

Nicht:

```text
Timer
  ↓
nmcli
  ↓
grep
  ↓
parse
  ↓
repeat every second
```

Polling ist nur für Daten erlaubt, die nicht sinnvoll event-driven verfügbar sind.

---

# 3. Backend

## Required

```text
networkmanager
wpa_supplicant
ca-certificates
```

Optionaler Advanced-Fallback:

```text
nm-connection-editor
```

NetworkManager verwaltet:

- Wi-Fi Scans
- gespeicherte Wi-Fi-Profile
- Credentials
- WPA/WPA2/WPA3
- 802.1X / eduroam
- DHCP
- Connectivity Detection
- Captive Portal State

---

# 4. Applet-Struktur

Das vollständige Netzwerk-Applet besitzt folgende Tabs:

```text
Info | Wi-Fi | IP/DNS | VPN
```

Dieses Dokument beschreibt primär den Wi-Fi-Bereich sowie die gemeinsame Kopfzeile.

---

# 5. Persistent Header

Der Header ist in allen Netzwerk-Tabs identisch.

## Wi-Fi verbunden

```text
┌────────────────────────────────────────────┐
│ [WiFi Signal] eduroam        [QR][⇅][↻][⏻] │
├────────────────────────────────────────────┤
│ Info     Wi-Fi     IP/DNS     VPN           │
└────────────────────────────────────────────┘
```

## Ethernet verbunden

```text
┌────────────────────────────────────────────┐
│ [RJ45] Ethernet (10 Gbit)      [⇅][↻][⏻]  │
├────────────────────────────────────────────┤
│ Info     Wi-Fi     IP/DNS     VPN           │
└────────────────────────────────────────────┘
```

---

# 6. Header Connection Indicator

## Wi-Fi

Links befindet sich ein Wi-Fi-Piktogramm.

Das Piktogramm zeigt gleichzeitig die aktuelle Signalstärke.

Beispiele:

```text
Wi-Fi weak
Wi-Fi medium
Wi-Fi strong
```

Daneben ausschließlich die SSID:

```text
[WiFi] eduroam
```

Keine IP-Adresse und kein zusätzlicher Online-Text im Header.

---

## Ethernet

Bei Ethernet:

```text
[RJ45] Ethernet (10 Gbit)
```

Beispiele:

```text
Ethernet (100 Mbit)
Ethernet (1 Gbit)
Ethernet (2.5 Gbit)
Ethernet (10 Gbit)
```

Wenn die Link-Speed nicht verfügbar ist:

```text
Ethernet
```

---

# 7. Header Actions

Header-Aktionen werden ausschließlich durch Piktogramme dargestellt.

Reihenfolge:

```text
[QR] [Speedtest] [Restart Network] [Network Power]
```

Der QR-Button wird nur angezeigt, wenn aktuell eine Wi-Fi-Verbindung besteht.

---

# 8. Wi-Fi QR Sharing

QR-Sharing existiert ausschließlich für das aktuell verbundene WLAN.

Klick auf das QR-Icon öffnet ein Overlay.

Beispiel:

```text
┌─────────────────────────────┐
│                             │
│          QR CODE            │
│                             │
│       SSID: HomeWiFi        │
│       Password: foo123      │
│                             │
│           [ Close ]         │
└─────────────────────────────┘
```

Der QR-Code enthält das standardisierte Wi-Fi-QR-Format.

Unter dem QR-Code werden angezeigt:

```text
SSID
Password
```

Das Passwort soll damit auch manuell übertragbar sein, falls das andere Gerät keinen QR-Scanner besitzt.

Credentials dürfen nicht dauerhaft von Quickshell gespeichert werden.

Das Passwort wird ausschließlich bei Bedarf vom bestehenden NetworkManager-Profil abgefragt.

---

# 9. Wi-Fi Tab

Der Wi-Fi Tab besteht aus zwei klar getrennten Bereichen:

```text
KNOWN NETWORKS

OTHER NETWORKS
```

---

# 10. Known Networks

Known Networks sind vorhandene NetworkManager-Wi-Fi-Profile.

Beispiel:

```text
KNOWN NETWORKS

[signal] eduroam                       [portal] [lock]
         connected

[signal] HomeWiFi                               [lock]
         saved

[signal] Phone Hotspot                          [lock]
         saved
```

---

# 11. Known Network Row Layout

Jede Zeile besitzt:

```text
[signal] SSID                         [portal] [lock]
```

Reihenfolge:

1. Signalstärke
2. SSID
3. Captive-Portal-Symbol, falls relevant
4. Security-/Lock-Symbol ganz rechts

Das Lock-Symbol befindet sich immer am äußersten rechten Rand.

---

# 12. Signal Indicator

Das Signal-Piktogramm steht links vor der SSID.

Es zeigt die aktuelle Scan-Signalstärke.

Beispiel:

```text
[▂] Home
[▂▄] Office
[▂▄▆] eduroam
[▂▄▆█] Hotspot
```

Die konkrete Icon-Darstellung soll dem global verwendeten Icon-Set entsprechen.

---

# 13. Known Network Interaction

## Klick auf nicht verbundenes Known Network

```text
click
  ↓
disconnect current Wi-Fi if necessary
  ↓
activate selected NetworkManager connection profile
```

Beispiel:

Aktuell:

```text
eduroam
```

User klickt:

```text
HomeWiFi
```

Ergebnis:

```text
eduroam disconnected
HomeWiFi connected
```

---

## Klick auf aktuell verbundenes Wi-Fi

Klick auf das aktuell aktive Netzwerk:

```text
disconnect
```

Es wird nicht automatisch ein alternatives Netzwerk verbunden.

---

# 14. Forget Network Interaction

Das Security-Symbol ganz rechts übernimmt zusätzlich die Forget-Funktion.

Normal:

```text
HomeWiFi                      [lock]
```

Hover über Lock:

```text
HomeWiFi                      [red X]
```

Klick auf das rote X:

```text
delete corresponding NetworkManager connection profile
```

Das Netzwerk verschwindet anschließend aus:

```text
KNOWN NETWORKS
```

Wenn es weiterhin in Reichweite ist, kann es unmittelbar unter:

```text
OTHER NETWORKS
```

erscheinen.

---

# 15. Other Networks

Other Networks enthält aktuell sichtbare Wi-Fi-Netzwerke, für die kein gespeichertes Profil existiert.

Beispiel:

```text
OTHER NETWORKS

[signal] BayernWLAN

[signal] CafeWiFi                         [lock]

[signal] HotelGuest                       [lock]
```

Offene Netzwerke besitzen kein Lock-Icon.

Es wird bewusst kein zusätzliches "unlocked"-Icon angezeigt.

---

# 16. Open Network Interaction

Klick auf ein offenes Netzwerk:

```text
click
  ↓
NetworkManager creates temporary/saved connection
  ↓
connect
```

Beispiel:

```text
[signal] BayernWLAN
```

Klick verbindet unmittelbar.

Falls anschließend ein Captive Portal erkannt wird, wird die Zeile entsprechend aktualisiert.

---

# 17. Protected Network Interaction

Klick auf ein nicht bekanntes geschütztes Netzwerk erweitert die Zeile inline.

Vorher:

```text
[signal] CafeWiFi                         [lock]
```

Nach Klick:

```text
[signal] CafeWiFi                         [lock]

         ┌─────────────────────────────┐
         │ Password                    │
         └─────────────────────────────┘

                         [ Connect ]
```

Optional:

```text
[show/hide password]
```

Es soll immer nur ein Passwort-Editor gleichzeitig geöffnet sein.

Klick auf ein anderes Netzwerk schließt den vorherigen Editor.

---

# 18. Connecting State

Während NetworkManager verbindet:

```text
[signal] CafeWiFi                         [lock]
         connecting…
```

Die UI soll NetworkManager nicht blockieren.

State-Änderungen kommen aus dem Backend.

Mögliche Zustände:

```text
saved
connecting
connected
authentication required
failed
portal
```

---

# 19. Captive Portal Detection

Keine eigene Portal-Heuristik implementieren.

NetworkManager Connectivity Detection verwenden.

Relevante Zustände:

```text
unknown
none
portal
limited
full
```

Nur bei:

```text
portal
```

wird ein Captive-Portal-Zustand dargestellt.

---

# 20. Captive Portal UI

Wenn das aktuell verbundene Wi-Fi als Portal erkannt wird:

```text
[signal] BayernWLAN             [portal]
         connected · portal
```

Bei einem geschützten Netzwerk:

```text
[signal] GuestWiFi              [portal] [lock]
         connected · portal
```

Das Portal-Symbol befindet sich links vom Lock-Symbol.

Beispiel:

```text
SSID                        portal  lock
```

nicht:

```text
SSID                        lock  portal
```

Grund:

Das Lock-Symbol ist ein konsistenter Bestandteil der rechten Kante.

Das Portal-Symbol ist ein optionaler Status.

---

# 21. Captive Portal Action

Klick auf das Portal-Piktogramm:

```text
open captive portal login
```

Die Aktion soll nur verfügbar sein, wenn NetworkManager tatsächlich:

```text
Connectivity = portal
```

meldet.

Nach erfolgreichem Login soll NetworkManager erneut einen Connectivity Check durchführen können.

---

# 22. Captive Portal im Info Tab

Zusätzlich zur Wi-Fi-Zeile kann der Info-Tab anzeigen:

```text
Connectivity
────────────────────
Captive portal

[ Open login page ]
```

Der Button erscheint ausschließlich bei erkanntem Portal.

Bei:

```text
limited
```

wird stattdessen beispielsweise angezeigt:

```text
Limited connectivity
```

ohne Portal-Login-Button.

---

# 23. Info Tab

Der Info-Tab enthält die technischen Verbindungsinformationen.

Beispiel:

```text
Connection
────────────────────────
Interface       wlp0s20f3
SSID            eduroam
Link            866 Mbit/s

IPv4            10.20.31.44/20
Gateway         10.20.16.1
DNS             10.20.0.53

IPv6            2001:...
```

---

# 24. Live Traffic Monitoring

Traffic-Metriken laufen ausschließlich, solange der Info-Tab sichtbar ist.

Wenn Info geschlossen:

```text
traffic monitoring OFF
```

Wenn Info geöffnet:

```text
traffic monitoring ON
```

Beispiel:

```text
Traffic
────────────────────
↓ 12.4 Mbit/s
↑  1.8 Mbit/s
```

Dafür sollen Interface-Counter verwendet werden.

Beispielprinzip:

```text
RX bytes t0
    ↓
1 second
    ↓
RX bytes t1

rate = delta / interval
```

Kein externer Speedtest für Live-Traffic.

Empfohlene Aktualisierungsrate:

```text
1 Hz
```

---

# 25. Live Latency

Solange Info geöffnet ist, darf zusätzlich eine leichte Latency-Messung laufen.

Beispiel:

```text
Latency
────────────────────
Gateway       2 ms
Internet     14 ms
```

Der Prozess wird beendet, sobald der Info-Tab verlassen oder das Applet geschlossen wird.

Keine permanente Ping-Messung im Hintergrund.

---

# 26. Speedtest

Der Speedtest ist unabhängig von der Live-Traffic-Anzeige.

Unterschied:

```text
Live Traffic
= tatsächlich aktuell übertragene Daten
```

```text
Speedtest
= maximal erreichbarer Throughput
```

Der Speedtest wird ausschließlich explizit über den Header-Button gestartet.

Währenddessen:

```text
Ping          …
Download      …
Upload        …
```

Nach Abschluss:

```text
Ping          13 ms
Download      184 Mbit/s
Upload         72 Mbit/s
```

Kein automatischer vollständiger Speedtest beim Öffnen des Applets.

---

# 27. Network Restart

Der Header besitzt einen Restart-Button.

Piktogramm:

```text
↻
```

Die konkrete Implementierung soll die etablierte Systemkonfiguration verwenden.

Beispiel:

```text
restart NetworkManager
```

Da diese Aktion alle Netzwerkverbindungen einschließlich VPN kurz unterbrechen kann, soll eine unbeabsichtigte Aktivierung erschwert werden.

Mögliche UX:

```text
short confirmation
```

oder:

```text
press-and-hold
```

Kein komplexer eigener Recovery-Mechanismus.

---

# 28. Network Power

Der Header besitzt einen globalen Netzwerk-On/Off-Button.

Beispiel:

```text
⏻
```

Funktion:

```text
NetworkManager networking enabled / disabled
```

Die Shell führt lediglich die bestehende NetworkManager-Funktion aus.

---

# 29. eduroam / WPA Enterprise

Das Applet implementiert keinen eigenen 802.1X-Stack.

NetworkManager übernimmt:

```text
802.1X
EAP
certificates
credentials
```

Für komplexe initiale Konfiguration können verwendet werden:

```text
eduroam CAT
```

oder:

```text
nm-connection-editor
```

Nach erfolgreicher Konfiguration erscheint eduroam anschließend wie jedes andere bekannte Wi-Fi-Profil im Applet.

Beispiel:

```text
KNOWN NETWORKS

[signal] eduroam                         [lock]
         connected
```

---

# 30. Password Handling

Passwörter werden nicht von Quickshell dauerhaft gespeichert.

Neue Wi-Fi-Passwörter werden an NetworkManager übergeben.

Gespeicherte Credentials verbleiben im jeweiligen NetworkManager Connection Profile bzw. dessen Secret Storage.

QR-Sharing fragt vorhandene Credentials nur bei Bedarf ab.

---

# 31. D-Bus vs CLI

Bevorzugt:

```text
NetworkManager D-Bus API
```

für:

- Verbindungsstatus
- Scan-Ergebnisse
- Connection activation
- Connection deactivation
- Connectivity state
- Signalstärke
- Interface state
- bekannte Verbindungen

CLI-Aufrufe wie:

```text
nmcli
```

dürfen als pragmatischer Fallback verwendet werden, sollen aber nicht die Basis für dauerhaftes Polling bilden.

Bestehende Omarchy-Skripte dürfen übernommen werden, wenn sie:

- stabil sind
- bereits gut funktionieren
- keine unnötige Komplexität erzeugen

---

# 32. UI Design

Der visuelle Stil orientiert sich stark an Omarchy Quattro.

Omarchy wird nicht visuell künstlich weiter reduziert.

Designziele:

- ruhiges Interface
- kompakte Darstellung
- klare Hierarchie
- keine unnötigen Beschriftungen
- Icons für häufige Aktionen
- konsistente Hover-States
- geringe visuelle Ablenkung
- keine langen Animationen

---

# 33. Systemweites Design System

Das Network Applet darf keine eigene isolierte Designsprache besitzen.

Alle Shell-Komponenten sollen dieselben Basiskomponenten verwenden.

Beispielstruktur:

```text
shell/
├── theme/
│   ├── Colors.qml
│   ├── Typography.qml
│   ├── Spacing.qml
│   ├── Metrics.qml
│   └── Icons.qml
│
├── components/
│   ├── Panel.qml
│   ├── TabBar.qml
│   ├── IconButton.qml
│   ├── Toggle.qml
│   ├── ListRow.qml
│   ├── Section.qml
│   ├── StatusBadge.qml
│   ├── InlineInput.qml
│   └── Dialog.qml
│
└── applets/
    ├── network/
    ├── bluetooth/
    ├── audio/
    ├── power/
    └── …
```

---

# 34. Performance Requirements

Das Applet soll im geschlossenen Zustand praktisch keine aktive Arbeit durchführen.

Nicht erlaubt:

```text
permanent Wi-Fi scan loops
permanent ping processes
permanent speedtest
frequent shell polling
animations that continuously redraw
```

Bevorzugt:

```text
D-Bus events
lazy loading
on-demand diagnostics
visibility-bound monitoring
```

---

# 35. Suggested Quickshell Structure

```text
applets/network/
├── NetworkApplet.qml
├── NetworkHeader.qml
├── NetworkTabs.qml
│
├── info/
│   ├── InfoTab.qml
│   ├── ConnectionInfo.qml
│   ├── TrafficMonitor.qml
│   └── LatencyMonitor.qml
│
├── wifi/
│   ├── WifiTab.qml
│   ├── KnownNetworks.qml
│   ├── OtherNetworks.qml
│   ├── WifiNetworkRow.qml
│   ├── WifiPasswordInput.qml
│   ├── WifiQrDialog.qml
│   └── CaptivePortalIndicator.qml
│
├── ip/
│   └── IpDnsTab.qml
│
├── vpn/
│   └── VpnTab.qml
│
└── services/
    ├── NetworkManagerService.qml
    ├── WifiService.qml
    ├── ConnectivityService.qml
    └── TrafficService.qml
```

Die endgültige Struktur darf vereinfacht werden, wenn Quickshell bereits bessere Patterns für Singleton Services oder D-Bus-Integration bietet.

---

# 36. Backend Abstraction

Empfohlen:

```text
UI components
      │
      ▼
WifiService
      │
      ▼
NetworkManagerService
      │
      ▼
NetworkManager D-Bus
```

UI-Komponenten sollten NetworkManager nicht an vielen Stellen direkt ansprechen.

Beispiel:

```text
WifiNetworkRow.qml
       │
       │ connect()
       ▼
WifiService.qml
       │
       ▼
NetworkManager
```

Das erleichtert:

- Tests
- Refactoring
- Fehlerbehandlung
- spätere Backend-Anpassungen

---

# 37. Important State Model

Beispiel für eine Netzwerkrepräsentation in der UI:

```text
ssid
signalStrength
security
known
connected
connecting
portal
connectionProfileId
device
```

Dieser State ist nur eine Darstellung des Backend-Zustands.

Er darf nicht als persistente eigene Datenquelle verwendet werden.

---

# 38. Known vs Other Network Classification

```text
scan result
   │
   ├── matching saved NM profile
   │       ↓
   │   Known Networks
   │
   └── no matching profile
           ↓
       Other Networks
```

Doppelte SSIDs müssen sauber behandelt werden.

Die konkrete Zuordnung soll möglichst NetworkManager selbst überlassen werden.

---

# 39. Sorting

## Known Networks

Empfohlene Reihenfolge:

```text
1. currently connected
2. currently available saved networks
3. unavailable saved networks
```

Innerhalb der Gruppen bevorzugt nach:

```text
signal strength
```

bzw. sinnvollem NetworkManager-Prioritätsverhalten.

---

## Other Networks

Sortierung:

```text
strongest signal first
```

Doppelte BSSIDs derselben logischen SSID sollen in der UI nach Möglichkeit zusammengefasst werden.

---

# 40. Error Handling

Fehler sollen lokal und knapp dargestellt werden.

Beispiel:

```text
CafeWiFi
Authentication failed
```

Nicht:

```text
large modal error dialog
```

wenn dies nicht notwendig ist.

Mögliche Fehler:

```text
wrong password
authentication timeout
connection failed
network disappeared
802.1X failure
NetworkManager unavailable
```

Komplexe Fehler dürfen optional eine:

```text
Details
```

Aktion anbieten.

---

# 41. Acceptance Criteria

## Wi-Fi

- bekannte Netzwerke werden korrekt angezeigt
- verfügbare unbekannte Netzwerke werden separat angezeigt
- Signalstärke ist sichtbar
- bekannte Netzwerke können per Klick verbunden werden
- aktive Verbindung kann per Klick getrennt werden
- bekannte Profile können über Lock → red X vergessen werden
- neue geschützte Netzwerke bieten Inline-Passworteingabe
- offene Netzwerke verbinden ohne Passwortdialog
- eduroam funktioniert über bestehendes NetworkManager-Profil

## Captive Portal

- Portal wird über NetworkManager Connectivity Detection erkannt
- Portal-Symbol erscheint nur bei echtem Portal-State
- `connected · portal` wird beim verbundenen WLAN angezeigt
- Portal-Login kann gezielt geöffnet werden
- BayernWLAN-/Hotel-/Gastnetz-Workflows funktionieren zuverlässig

## QR Sharing

- QR erscheint nur bei verbundenem Wi-Fi
- QR-Code kann von Mobilgeräten gelesen werden
- SSID wird zusätzlich als Text angezeigt
- Passwort wird zusätzlich als Text angezeigt
- Credentials werden nicht separat von Quickshell gespeichert

## Header

- Wi-Fi zeigt Signalicon + SSID
- Ethernet zeigt RJ45-Icon + Link Speed
- QR nur bei Wi-Fi
- Speedtest vorhanden
- Restart vorhanden
- Network Power vorhanden
- keine IP-Adresse im Header
- kein redundanter Online-Text

## Performance

- keine dauerhaften Diagnoseprozesse bei geschlossenem Applet
- kein permanenter Ping
- kein permanenter Speedtest
- Live-Traffic läuft nur bei sichtbarem Info-Tab
- Live-Latency läuft nur bei sichtbarem Info-Tab
- NetworkManager-Events bevorzugt über D-Bus
- praktisch keine relevante Idle-CPU-Last

---

# 42. Non-Goals

Das Wi-Fi Applet soll ausdrücklich nicht:

- NetworkManager ersetzen
- einen eigenen DHCP-Client implementieren
- einen eigenen DNS-Resolver implementieren
- WPA/802.1X selbst implementieren
- Wi-Fi-Passwörter in einer eigenen Datenbank speichern
- Netzwerkzustand parallel zu NetworkManager verwalten
- permanente Diagnostik betreiben
- eine vollständige Network-Administration-Suite werden

Es ist eine schnelle, hochwertige Desktop-Oberfläche für bewährte Linux-Netzwerkkomponenten.

---

# 43. Guiding Principle

```text
Reliable backend.
Thin shell.
Fast interaction.
No duplicated state.
```

Omarchy Quattro dient als Referenz für den bewährten Wi-Fi-Workflow und die visuelle Designsprache.

Eigene Implementierungen werden nur dort ergänzt, wo ein konkreter zusätzlicher Workflow benötigt wird.
