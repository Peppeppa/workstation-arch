# RICE v1 overnight batch - status / checkpoints

Branch `rice-v1-overnight` (from `main` = `2a74425`). Updated after every
stage; the newest entry is at the top of "Log". Large artifacts
(screenshots, benchmark JSON) stay outside Git (controlling machine:
the session scratchpad).

## Current state

| | |
|---|---|
| Branch / HEAD | rice-v1-overnight / see `git log` |
| Completed phases | harness, 2 (bar/popups), 3 (dialog scaffold, menus/windows, English UI) |
| Last known-good deployment | `2a74425` (main, deployed 2026-10-11 ~00:15, bootstrap changed=0, HEALTHY) |
| SSH / healthcheck | reachable / HEALTHY (00:27) |
| Open bugs | - |
| Next safe action | phase 4 (launcher / small widgets) |

## Log

### 00:45 - phases 2 + 3

- `scripts/qs-candidate-check.py`: renders the candidate's QML over a copy
  of the deployed config, loads it in an isolated bounded `quickshell -p`
  (no D-Bus owners, tray off, 4 GB AS limit, hard timeout), optionally
  opens read-only overlays over IPC (`--pid`) and screenshots them (never
  when hyprlock runs). Verified it reports an injected ReferenceError.
- phase 2 (`0b40189`): BarStyle on Style, 9 bar popups on spacing/radius/
  type tokens; default-size look unchanged (test: BarStyle at 9/11/12/18).
- phase 3 (`0a76eb1`): ui/DialogFrame/DialogText/DialogButtons; updater,
  snapshot slots, snapshot mode, firewall question/form, theme import on it;
  menus/windows on tokens; PopupButton.muted instead of opacity; German UI
  text -> English (+ README/docs). Candidate load: 0 errors; overlays
  osmenu (5 pages), power menu, appearance, cheatsheet, clipboard, snapshot
  slots, updater opened on the laptop test instance: 0 QML errors,
  screenshots of power menu + snapshot slots checked by eye (correct).
- tests/run.sh: all passed after each phase. Nothing deployed yet.

### 00:27 - preflight

- repo: main = origin/main = 2a74425, clean tree
- laptop: rebooted 5 min ago, normal boot (`rootflags=subvol=@`), Hyprland 1,
  Quickshell 1, hypridle 1, hyprpolkitagent 1, no hyprlock (Coffee on),
  repo checkout 2a74425 clean, no pending updates, theme retro-82 dark,
  text size 12, faillock 0, swap 0, load 0.01
- `repo-healthcheck`: HEALTHY
