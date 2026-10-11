# Bug Hunt v1 - status / checkpoints

Branch `bughunt-v1` from `main` = `5c60635` (known-good, deployed on the
laptop, HEALTHY). Newest log entry on top. Evidence (logs, screenshots,
JSON) stays on the controlling machine (session scratchpad), not in Git.

## Current state

| | |
|---|---|
| Branch / HEAD | bughunt-v1, fast-forwarded into main after validation |
| Known-good before | `5c60635` |
| Completed groups | tier 1, tier 2, tier 3 (safe parts), deployment, post-deploy GUI + idempotency + performance |
| Bugs found / fixed / deferred | 4 / 4 / 3 (L1 language, BT1 suspected, M1 observation) |
| Deployment | deployed on the laptop, changed=0 on re-run, HEALTHY |
| Session / SSH | unlocked, Coffee on / reachable |
| Next safe action | supervised resume: docs/testing/BUGHUNT_V1_SUPERVISED_RESUME.md |

## Log

### 10:40 - deployment + validation

- dry run: repo-healthcheck, system-update, ~/.local/bin/theme, Fonts.qml
  (+ pacman DB sync); nothing for SSH/firewall/PAM/boot/storage.
- deploy rc 0 changed=6; handler snapshot-boot sync ran (not shown by the
  dry run) - entries identical before/after (#47 #46 #44 #43).
- +30 s: SSH, all session processes, Coffee on, no lock, faillock 0,
  HEALTHY; Quickshell reloaded in place (pid 34842).
- real: close policy 66/66, tier-3 combinations 20/20; second bootstrap
  changed=0; idle CPU 0 %, swap 0.
- memory: 10 rounds x 40 overlay openings: 262 -> 277-285 MB plateau, no
  linear growth (M1, observation).
- report: docs/testing/BUGHUNT_V1_REPORT.md; supervised:
  docs/testing/BUGHUNT_V1_SUPERVISED_RESUME.md.

### 10:05 - more tier 2/3

- FIXED TH1 `7c0d967` (mocked): a wallpaper file name with a line break
  (imported theme = foreign data) injected a key into theme-state.
- coverage only (behaviour already correct): focus-or-launch failure paths
  (tests/session-helpers.sh), pacman hook aborts in a snapshot boot.
- static, no defect: wifi-qr escaping/payload, portal-login vs. the
  Chromium policy keys, display-scale.lua writer (whitelisted names),
  snapshot-boot skips a half-written info.xml, git-sync never discards,
  screenshot.sh temp/trap handling, terminal argv (split) for launchers.
- deferred (cosmetic): German text still in terminal diagnostics
  (repo-logs, log analysis), screenshot notifications, firewall-rules
  messages + factory labels.
- suspected, not tested: Bluetooth popup open while the adapter vanishes
  -> transient binding warnings during teardown (no functional effect
  expected; needs a supervised adapter removal).

### 09:40 - tier 1 + first tier 2/3 groups

- linters (scratchpad venv: shellcheck 0.x, pyflakes; rendered templates):
  no real defect - SC1010 `done` as a string value, SC2088 `~` in a
  message, unused variables (fixed with HC1).
- static review of the root helpers (firewall-rules, snapshot-create,
  snapshot-restore, pre-transaction hook, recovery-lib, system-update):
  input validation strict, atomic writes, locks - no defect except below.
- FIXED HC1 `6a55374` (mocked): healthcheck reported an imported theme's
  own wallpaper as "file gone".
- FIXED SU1 `bc5982f` (mocked): system-update skipped the boot image and
  health checks when the step after pacman failed (set -e).
- FIXED F1 (isolated integration test on the laptop): invalid text_size
  in colors.json -> Fonts.size 0 (all shell text 0 px); now default 11.
- not reproduced: interrupted checkupdates leaving a stale lock
  (kill -9 mid-sync, private DB: next run rc 2) - no defect.
- not a defect: FileView watch survives rename-replace x2, delete +
  recreate, missing at start (isolated instance) - scratchpad safe.
- real ThinkPad: helper parentage after RICE `env -u` (all direct children
  of Hyprland), logout 08:22 without coredumps; GUI tier 3 20/20 (rapid
  toggles, focus, theme switch / text size 18 with dialogs open, no QML
  errors, same Quickshell pid); missing/malformed colors.json handled.
- deferred (cosmetic): firewall-rules messages + factory labels German
  while the UI is English (root helper; rules.json keeps user labels).

### 08:56 - preflight

- repo: main = origin/main = 5c60635, clean
- laptop: checkout 5c60635 clean; Hyprland/quickshell/hypridle/
  hyprpolkitagent 1 each, no hyprlock, Coffee on, faillock 0, graphical
  session c2 (seat0, tty2), no pending updates, swap 0,
  `repo-healthcheck` HEALTHY
