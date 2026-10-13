# Code Consolidation v1 - report

2026-10-13, branch `consolidation-v1` from `main` = `54b972c`, validated on
the ThinkPad, then fast-forwarded into `main` (= `d44b2f7`). Audit and
plan: `docs/architecture/CODE_CONSOLIDATION_V1_AUDIT.md`.

## 1. Executive summary

The audit found a codebase with little real logic duplication: most
same-named functions are a deliberate uniform interface (IPC
open/close/state, the popup coordinator) or thin delegation to a shared
model. The real problems were dead code and obsolete one-time
migrations, one /proc parser kept in three copies, a duplicated Ansible
task and stale comments. Six low-risk batches removed them (-564 source
lines, -3 files, two subprocess spawns less per bootstrap) with no
behaviour change; protected areas (PAM/polkit, SSH, firewall, boot, UKI,
snapshot boot/restore, pacman hooks, root helpers) were not touched. One
deployment: changed=7, second run changed=0, HEALTHY. The one real
complexity hotspot (connectivity/Popup.qml) is deferred to a supervised GUI
batch.

## 2. Original architecture and metrics

See the audit, sections 1-2: 28773 non-blank source lines in 237 files
(without docs, images, theme data and the generated uv.lock); QML 12703,
Python 6121, YAML 4844, Shell 3543, Lua 724.

## 3. Confirmed problems

| Problem | Kind |
|---|---|
| scripts/diagnose-quickshell-autostart.sh: 375-line diagnostic of a long-solved issue, still probing the retired mako | dead code |
| scratchpad migration (task + script + test) done everywhere it could apply, still spawning python3 on every bootstrap | obsolete compatibility layer |
| "stop a still-running mako" (`pkill` on every bootstrap) | obsolete migration |
| `started_at(pid)` in diaglib, repo-healthcheck and repo-diagnose | duplicated logic |
| two identical "libexec directory" tasks in roles/quickshell | duplicated deployment task |
| comments describing mako / fuzzel as current (screenshot.sh, quickshell defaults, session.lua) | stale documentation in code |

## 4. Changes by subsystem

| Subsystem | Change | Commit |
|---|---|---|
| scripts | diagnose-quickshell-autostart.sh removed; AGENTS.md history line reworded | `1c76a52` |
| quickshell (Ansible, QML comment), tests, README, feature-architecture | scratchpad migration removed (task, `files/scratchpad-migrate.py`, `tests/scratchpad-migrate.sh`, run.sh step); folder task and the format tests in qml-logic stay | `b0909f2` |
| desktop, hyprland, quickshell defaults | mako pkill task removed (the `mako: absent` guard stays); stale comments rewritten | `3e822c1` |
| diagnostics | healthcheck + diagnose use `diaglib.started_at`; new checks in tests/diaglib.py | `4fb2009` |
| quickshell (Ansible) | one libexec directory task for bluetooth/connectivity | `d44b2f7` |

## 5. Removed duplication

- `started_at`: 3 copies -> 1 (diaglib.py; both tools already imported it).
- "Ensure ~/.local/libexec/workstation exists": 2 tasks in one role -> 1.

Checked and deliberately **kept** (audit section 3): the IPC/popup
interface functions, `run/journal/environ_of` (different on purpose),
`hoverRow` x3 (4 lines each, all covered by tests/qml-logic `hover()`; a
component would add more than it removes), delegating wrappers, the
recovery Python/shell twins (protected), and the `/etc/pam.d/polkit-1`
security copy of system-auth (P1, drift-checked by repo-healthcheck).

## 6. Removed dead code

scripts/diagnose-quickshell-autostart.sh (424 lines incl. blanks),
roles/quickshell/files/scratchpad-migrate.py (116), tests/scratchpad-migrate.sh
(52), the migration and pkill tasks. Every candidate was verified: no
caller in tasks/templates/QML/Hyprland binds/runtime calls; the scratchpad
migration's state checked on the laptop (`MIGRATED` marker present).
Kept although unreferenced by code: the documented test tools
(qs-candidate-check.py, rice-measure.py, sni-test-client.py) and theme
backgrounds (found by directory scan).

## 7. New or improved abstractions

None new. The existing shared library diaglib.py is now actually the one
source for process start times.

## 8. Before / after metrics (measured, same script)

| | Before | After |
|---|---|---|
| Source lines (non-blank, without uv.lock) | 28773 | 28209 (-564) |
| Source files | 237 | 234 (-3) |
| Shell | 3543 | 3122 |
| Python | 6121 | 6011 |
| YAML / Ansible | 4844 | 4813 |
| QML | 12703 | 12701 |
| repo-healthcheck.j2 / repo-diagnose.j2 | 528 / 439 | 519 / 429 |
| roles/quickshell/tasks/main.yml | 487 | 466 |
| Ansible tasks per bootstrap (ok, run 2) | 217 | 215 |
| Dependencies | unchanged | unchanged |

Largest files unchanged at the top (connectivity/Popup.qml 1418, theme.j2
1106).

## 9. Regression tests

`tests/run.sh` after every batch: all checks passed (incl. qml-logic,
theme helper, firewall, snapshot/system-update/rollback, pam-polkit,
healthcheck tests, diaglib). New: tests/diaglib.py `started_at` (own
process, string pid, gone/junk pid). Removed with its code:
tests/scratchpad-migrate.sh. Static: pyflakes on the rendered healthcheck /
diagnose (clean), YAML parse, `ansible-playbook --syntax-check`,
`--list-tasks --tags quickshell` (one libexec task).

## 10. Performance (laptop, 30 s idle, same script)

| | Before | After deploy |
|---|---|---|
| quickshell CPU / PSS | 0.00 % / 180 MB | 0.00 % / 209 MB |
| Hyprland CPU / PSS | 0.03 % / 111 MB | 0.03 % / 111 MB |
| hypridle | 0.00 % / 1 MB | 0.00 % / 1 MB |
| swap | 0 | 0 |

The Quickshell PSS rise is the known in-place reload effect (same pid; Qt
keeps caches - Bug Hunt v1 M1: 182-213 MB fresh, ~280 MB plateau); the only
QML change was a comment. Bootstrap: one python3 and one pkill spawn fewer
per run.

## 11. Deployment and healthcheck

Branch deployed first (`git switch consolidation-v1` on the laptop). Dry
run: pacman DB sync (known cosmetic), session.lua, screenshot,
repo-diagnose, repo-healthcheck, the Quickshell core config. Real run rc 0
changed=7 (the six + handlers: hypridle restart - the designed reaction to
a session.lua change, new hypridle again a child of Hyprland - and the
in-place Quickshell reload, same pid); second run changed=0. Afterwards:
HEALTHY (all PASS), Hyprland/quickshell/hypridle/hyprpolkitagent 1 each,
no new QML warnings, repo-diagnose rc 0, feature helpers present, boot
entries unchanged, faillock 0, SSH over Ethernet and Wi-Fi. Then `main`
fast-forwarded and the laptop switched back to `main` (clean). Rollback:
`git revert` of the batch commits + bootstrap (each batch is one commit).

## 12. Commits

`74001e7` audit, `1c76a52` A1, `b0909f2` A2, `3e822c1` A3/A4, `4fb2009` B1,
`d44b2f7` B2, plus this report.

## 13. Deferred high-risk / supervised improvements

| Item | Risk | Why deferred |
|---|---|---|
| Split connectivity/Popup.qml (Wi-Fi known/other, password with frozen list, share/QR, VPN, metrics, speedtest) | MEDIUM | needs hardware GUI regression (password flow, close policy, metrics lifecycle) |
| Recovery twins `uki_uname`, `snapshot_mode` (snapshot-boot Python vs recovery-lib shell); `sync_once` (78 lines), `slot_set` (51) | HIGH (protected) | boot/restore semantics; restore not yet hardware-validated |
| `run()` signature differences in diagnostics | LOW benefit | changing return shapes touches every call site for little gain |

## 14. Remaining technical debt

- L1 (from Bug Hunt v1): German strings in terminal diagnostics and
  firewall-rules while the UI is English.
- AGENTS.md "Current Status" carries long historical narrative (e.g. the
  earliest milestones still describe fuzzel/mako/Thunar as current in their
  own paragraphs); a documentation pass could condense it.
- The `polkit-1` PAM copy must be updated by hand when pambase changes
  (healthcheck WARNs).
- `--check` does not show handlers (snapshot-boot sync, hypridle restart)
  - known Ansible behaviour, documented in the reports.

## 15. Recommendations for the security audit

- Root helpers (firewall-rules, snapshot-create/-restore, system-update-root,
  snapshot-boot): input validation was reviewed statically in Bug Hunt v1;
  a focused review of their polkit actions and argument parsing is the
  highest-value next step.
- Re-check `/etc/pam.d/polkit-1` against upstream polkit (helper EOF
  handling) and remove it once polkit fixes the socket cancel path.
- Review sshd (key-only, `ssh_server_enabled`) and the firewall's standard
  rules on the workstation host before its first deployment.
- The THWS PAC names a plain-HTTP proxy (AGENTS.md note) - out of this
  repository's control, worth stating in the audit.
