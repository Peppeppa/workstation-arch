# Code Consolidation v1 - audit

2026-10-13, branch `consolidation-v1` from `main` = `54b972c` (deployed code =
`c6960fa`; `54b972c` is documentation only). Laptop: normal boot on `@`,
HEALTHY, faillock 0. Metrics: a script over `git ls-files`, non-blank lines,
without docs/Markdown, images, theme data and the generated
`roles/development/files/data-science/uv.lock` (4178 lines).

## 1. Architecture (as found)

Provisioning: `bootstrap.sh` -> `ansible-playbook local.yml` -> 22 roles.
Runtime: Hyprland (Lua config, `roles/hyprland`) + one Quickshell process
(`roles/quickshell`: bar, popups, OS menu, windows, dialogs, services) +
user-level helpers (theme, screenshot, workstation-pkg, connectivity
helpers) + root helpers behind polkit/sudo (firewall-rules, snapshot-*,
system-update/-rollback, snapshot-boot) + on-demand diagnostics
(repo-healthcheck / repo-diagnose / repo-logs on one library `diaglib.py`).
The ownership table in AGENTS.md matches the code; no runtime path uses
Ansible.

## 2. Metrics (before)

| Language | Lines | Files |
|---|---|---|
| QML | 12703 | 79 |
| Python (incl. Python templates) | 6121 | 22 |
| YAML / Ansible | 4844 | 53 |
| Shell | 3543 | 36 |
| Lua (Hyprland) | 724 | 14 |
| other (scripts without extension, configs) | 254 | 12 |
| templates/other, systemd/hooks/polkit, JSON | 584 | 21 |
| **total** | **28773** | **237** |

By subsystem: quickshell 12825, tests 3708, recovery 2083, diagnostics 1883,
theme 1221, hyprland 1193, scripts 1183, apps 867, firewall 601, others
< 500 each. Largest files: connectivity/Popup.qml 1418, theme.j2 1106,
tests/qml-logic.qml 846, snapshot-boot 651, diaglib.py 552,
bluetooth/Popup.qml 533, repo-healthcheck.j2 528, quickshell/tasks 487.

Performance baseline (laptop, 30 s idle): quickshell 0.00 % CPU, PSS
180 MB; Hyprland 0.03 %, 111 MB; hypridle 0.00 %; swap 0.

## 3. Duplication

Searched: function names defined in more than one file, identical bodies,
retired-component references, Ansible task patterns.

| Finding | Verdict |
|---|---|
| `open/close/state/toggle/closePopup/handleKey` in ~12 QML files | **intended**: the uniform IPC + popup-coordinator interface (BarPopups), not duplicated logic |
| `started_at(pid)` in diaglib.py, repo-healthcheck, repo-diagnose (same /proc logic 3x) | **real** - both tools import diaglib already |
| `run()` / `journal()` / `environ_of()` in diaglib + healthcheck + diagnose | different on purpose (return shapes, json vs text, diagnose filters the environment for privacy) - keep |
| `hoverRow` (pointer moved since open) in PowerMenu, ClipboardHistory, osmenu/RootPage | real but 4 lines each, all three covered by tests/qml-logic `hover()`; a shared component would add a file and coupling for little gain - **accepted repetition** |
| Theme popup `options/selectedId/nameOf/setWallpaper`, connectivity popup `signalIcon`, FirewallWindow `editRow/...` | thin delegation to ThemeModel / Connectivity Model / the lazily loaded FirewallContent (IPC layer) - **intended** |
| `uki_uname`, `snapshot_mode` in snapshot-boot (Python) and recovery-lib (shell) | cross-language twins in the protected recovery area - **document only** |
| `write_atomic` in scratchpad-migrate.py and snapshot-boot | goes away with A2 |
| Ansible: "Ensure ~/.local/libexec/workstation exists" twice (bluetooth, connectivity) | **real**, small |
| `/etc/pam.d/polkit-1` vs system-auth | **intended** security copy with drift check (P1) - never synchronise automatically |

## 4. Dead code / obsolete artifacts

| Candidate | Evidence | Verdict |
|---|---|---|
| `scripts/diagnose-quickshell-autostart.sh` (375 lines) | investigation tool for the solved Quickshell-autostart issue (cause: VirtualBox GL); never deployed; still probes mako; only AGENTS.md history mentions it | **remove** |
| scratchpad migration (`roles/quickshell/files/scratchpad-migrate.py`, its task, `tests/scratchpad-migrate.sh`) | one-time move of the 2026-10-07 four .txt notes; laptop has the `MIGRATED` marker; no other host ever had the notes; still spawns python3 on every bootstrap | **remove** (the folder task stays) |
| "Stop a still-running mako" (`pkill` on every bootstrap) | mako uninstalled since Notifications v1; only a still-running process of that era could match | **remove** (the `mako: absent` guard stays) |
| `absent` tasks for mako / fuzzel / thunar / webcord, "Remove retired Quickshell files" | declarative guards of the one-owner rule / the only way a removed QML file leaves `~/.config/quickshell` (copy never deletes) | **keep** |
| scripts/qs-candidate-check.py, rice-measure.py, sni-test-client.py | documented test tools (RICE baseline, tray) | keep |
| stale comments: screenshot.sh "mako notification", quickshell defaults "fuzzel/mako stay in roles/hyprland", session.lua mako history | describe retired components | **fix** |

## 5. Complexity hotspots

| Hotspot | Assessment |
|---|---|
| connectivity/Popup.qml (1418 lines: Wi-Fi known/other, password, share/QR, VPN, metrics, speedtest) | the one real complexity hotspot; splitting needs GUI regression on hardware (password flow, frozen list during typing, close policy) - **deferred, MEDIUM** |
| theme.j2 (1106, one CLI: discovery, validation, render, import, live apply) | cohesive, functions <= 115 lines (main dispatcher); covered by tests/theme-helper.sh - keep |
| snapshot-boot `sync_once` (78), `slot_set` (51) | protected area - **document only** |
| OsMenu `activate` (77) | one switch over menu entries - readable as is |
| repo-healthcheck `session_checks` (58) | one check per block - fine |

## 6. Dependencies

No unused package found in the role package lists by this audit (each
carries its reason in defaults/main.yml). No new dependency planned.

## 7. Plan

| # | Batch | Risk | Benefit |
|---|---|---|---|
| A1 | remove scripts/diagnose-quickshell-autostart.sh | LOW (never deployed) | medium: 375 dead lines, misleading mako probes |
| A2 | remove the scratchpad migration (task, script, test) | LOW (laptop migrated, marker present) | medium: one python3 spawn per bootstrap, 3 files |
| A3 | remove the mako pkill migration task | LOW | small: one command per bootstrap |
| A4 | fix stale comments | LOW | small: correct documentation in code |
| B1 | repo-healthcheck / repo-diagnose use `diaglib.started_at` | LOW (tests/diaglib.py + healthcheck tests; read-only tools) | medium: one /proc parser instead of three |
| B2 | one "libexec dir" task for bluetooth + connectivity | LOW | small |
| C1 | split connectivity/Popup.qml | MEDIUM | high - **deferred** to a supervised GUI batch |
| R1 | recovery twins (uki_uname, snapshot_mode), snapshot-boot long functions | HIGH (protected) | - **deferred**, documented |

Protected areas (PAM/polkit, SSH, firewall, boot, UKI, snapshot boot/restore,
pacman hooks, root helpers): no change planned beyond comments.
