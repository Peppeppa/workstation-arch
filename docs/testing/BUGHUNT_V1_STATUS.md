# Bug Hunt v1 - status / checkpoints

Branch `bughunt-v1` from `main` = `5c60635` (known-good, deployed on the
laptop, HEALTHY). Newest log entry on top. Evidence (logs, screenshots,
JSON) stays on the controlling machine (session scratchpad), not in Git.

## Current state

| | |
|---|---|
| Branch / HEAD | bughunt-v1 / see `git log` |
| Known-good | `5c60635` (main, deployed 2026-10-11 08:30, changed=0, HEALTHY) |
| Completed groups | - |
| Bugs found / fixed / deferred | - |
| Deployment | not yet |
| Session / SSH | unlocked, Coffee on / reachable (08:56) |
| Next safe action | Tier 1 static review |

## Log

### 08:56 - preflight

- repo: main = origin/main = 5c60635, clean
- laptop: checkout 5c60635 clean; Hyprland/quickshell/hypridle/
  hyprpolkitagent 1 each, no hyprlock, Coffee on, faillock 0, graphical
  session c2 (seat0, tty2), no pending updates, swap 0,
  `repo-healthcheck` HEALTHY
