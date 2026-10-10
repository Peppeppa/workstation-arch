# RICE v1 overnight batch - status / checkpoints

Branch `rice-v1-overnight` (from `main` = `2a74425`). Updated after every
stage; the newest entry is at the top of "Log". Large artifacts
(screenshots, benchmark JSON) stay outside Git (controlling machine:
the session scratchpad).

## Current state

| | |
|---|---|
| Branch / HEAD | `rice-v1-overnight` (pushed; NOT merged into main) |
| Completed phases | harness, 2, 3, 4, 5, 6, 6b, 7 (audit + performance), bug hunt (2 fixes + 1 unvalidated) |
| Deployed on the laptop | `486e819` (branch checkout `rice-v1-overnight`), bootstrap rc 0 changed=16, second run changed=0, HEALTHY |
| Last known-good main | `2a74425` (unchanged) |
| SSH / healthcheck | reachable / HEALTHY (01:17) |
| Session | LOCKED by hypridle at 01:21 (idle timeout after the deploy restart, see bug B1) - not bypassed |
| Open bugs | B1 Coffee not inhibiting after a Quickshell restart (fix on branch `rice-v1-coffee-restart-fix`, unvalidated) |
| Not run | Tier 5 GUI input tests (uinput blocked by the permission classifier), toast visual (session locked) |
| Next safe action | SUPERVISED_RESUME_PLAN below |

## SUPERVISED_RESUME_PLAN

Preconditions: the user is at the laptop, unlocks it (password typed by the
user), Coffee on, `faillock --user medvidec` empty.

1. Bug B1 (Coffee after restart): `git checkout rice-v1-coffee-restart-fix`
   on the laptop, `./bootstrap.sh` (Quickshell restarts: Bar.qml changed),
   Coffee on, do not touch input for 6 min -> session must stay unlocked.
   Control: the same on `rice-v1-overnight` reproduces the lock (optional).
   Pass -> merge `rice-v1-coffee-restart-fix` into `rice-v1-overnight`.
2. GUI close policy (Tier 5): run the uinput close-policy script (Escape /
   Super+Q / outside click on OS menu, power menu, clipboard, timer popup,
   firewall + question (only cancelled), Appearance, updater, snapshot
   slots, cheatsheet, scratchpad); needs an explicit permission for the
   one-shot uinput device or the user's hands. Expected: all PASS, firewall
   rules and scratchpad hashes unchanged.
3. Visual check by eye on the real desktop: toast (`notify-send test`),
   window gaps/rounding with 2+ tiled windows, dialogs in English, a Qt app
   (Anki or Nextcloud) dark in the dark theme and light after a
   Light/Dark switch (live), cursor the same over Ghostty, Chromium, a Qt
   app and an XWayland app. Lockscreen: input-field radius 4 (lock with
   Super+Delete, unlock by the user).
4. After the next real login (Ly): `systemctl --user show-environment |
   grep -E "QT_QPA|XCURSOR"` shows the three variables; polkit dialog works
   (e.g. Create Snapshot cancel path or firewall toggle).
5. All pass -> fast-forward `main` to `rice-v1-overnight`, push, laptop
   `git checkout main && git pull --ff-only`, bootstrap (changed=0
   expected), healthcheck. Any failure -> stay on the branch or roll back:
   `git checkout main && ./bootstrap.sh` (main = `2a74425`).

Tier 6 (critical, never unattended): real system update through the dialog,
snapshot boot + restore, firewall SSH rule changes - unchanged by RICE,
not needed for this merge.

## Log

### 01:16-01:30 - deployment + validation

- dry run (`--check --diff`): 13 changes, only Hyprland conf modules,
  hyprlock look, Quickshell files - no PAM/SSH/firewall/boot/storage.
  No pending updates (pacman -Syu = DB sync only).
- deployment of `486e819`: rc 0, ok=220 changed=16; Quickshell restarted
  (new QML files), hypridle restarted; second bootstrap changed=0.
- live: 1 Hyprland / quickshell / hypridle / hyprpolkitagent / wl-paste,
  no Hyprland config errors, gaps 4/8 + rounding 4 active, Quickshell
  without QT_QPA_PLATFORMTHEME, healthcheck HEALTHY (QML errors only in the
  old pid 1441 while files were copied - history).
- production idle (60 s settle, 60 s window): quickshell PSS 182 MB /
  RSS 221 MB / CPU 0 %, Hyprland CPU 0.03 %, swap 0 (fresh baseline 213 /
  227 MB).
- Tier 5 GUI (uinput) blocked by the permission classifier - not run, not
  worked around.
- 01:21:11 hypridle locked the session (5 min after its restart) although
  Coffee was "on" -> bug B1, fix prepared on `rice-v1-coffee-restart-fix`
  (unvalidated). Lockscreen not bypassed; toast/visual checks stopped.
- Decision: main NOT merged (GUI regression and B1 open).

### 01:00 - phase 7 + bug hunt

- visual audit dark/light x text 9/11/12/18 on the isolated test instance
  (colors.json rendered by the real theme helper in a sandbox, user state
  untouched): 0 QML errors; found padding sums drifting from token margins
  (toast/power menu 4 px short at default size) and fixed 34 px launcher
  rows -> fixed `80f1b4d`, design lint added to tests/run.sh.
- performance: isolated PSS median 130.5 MB deployed vs 127.1 MB candidate,
  CPU ~0 (docs/RICE_PERFORMANCE_BASELINE.md).
- bug hunt: polkit agent kept out of the Qt platform theme (`486e819`).

### 00:55 - phases 4, 5, 6, 6b

- 4 `2b0a55c` launcher/menus rows/insets/type; 5 `3d41d5a` Hyprland gaps
  4/8, border 1, rounding 4; 6 `389d3ca` toasts + hyprlock radius;
  6b `5dc0ef5` Qt apps follow light/dark via the portal platform theme
  (probe: before colorScheme unknown + light palette in dark mode, after
  colorScheme 2 + dark palette), explicit Adwaita 24 cursor.

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
