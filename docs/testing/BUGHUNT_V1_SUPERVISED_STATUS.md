# Bug Hunt v1 - supervised integration tests: status / checkpoints

2026-10-13, ThinkPad T440p (`laptop`), controlling machine = the user's
desktop. Plan: `docs/testing/BUGHUNT_V1_SUPERVISED_RESUME.md` (tests 1-7).
Controller: `tests/supervised/testctl.py` (+ `selftest.sh` simulations,
`plan-snapshot-boot.json`). Detailed logs, screenshots and controller state
stay on the controlling machine (session scratchpad), not in Git.

Levels: **simulated** (controller against a fake ssh), **mocked** (repo
tests with stubs), **real** (the laptop).

## Current state

| | |
|---|---|
| main / deployed | `143179a` deployed (laptop checkout clean); docs/harness commits after it change nothing deployed |
| Boot / root | normal boot (default `arch-linux.efi`, no one-shot pending), `/` = `@` |
| SSH | Ethernet (dock) + Wi-Fi paths (same host key) both OK; firewall: 5 rules enabled (SSH included) |
| Health | HEALTHY, 0 failed units, 0 coredumps, faillock 0, 0 pending updates |
| User action | none - batch finished; Coffee is off after the reboots (not persisted, as designed) |
| Safe next step | report: docs/testing/BUGHUNT_V1_SUPERVISED_REPORT.md |

## Log (newest on top)

### 22:28-22:32 - Group D done, Group F final validation

- D1-boot real PASS (22:25 reboot, SSH 22:26 after the user's LUKS unlock):
  cmdline `workstation.snapshot=48`, `/` overlay, chromium 153 (pre-update),
  pacman transaction aborted by the hook ("snapshot mode (snapshot 48):
  package changes are blocked"), Ly login via uinput, snapshotmode IPC
  active/48 + strip layer, faillock 0, no failed units, `/home` = @home.
- D1-return real PASS (22:27 session exit + reboot, SSH 22:27 after LUKS):
  `/` = `@` subvolid 297, chromium 154, Ly login, HEALTHY.
- E restore: DEFERRED by the user (not necessary; real-tested 2026-10-10).
- F: entries #48 #47 #44 #43 + legacy recovery entry unchanged since the
  update, no one-shot left, sshd + firewall active, 5 rules enabled, Wi-Fi
  SSH path OK, 0 coredumps (this boot and the snapshot boot), no test
  processes, test files removed from ~/.cache, HEALTHY.

### 22:24 - Group D started (D1-pre)

- D1-pre real PASS: normal boot, `/` = `@` (subvolid 297), chromium 154;
  entry #48 -> existing UKI copy, snapshot read-only, loader default
  `arch-linux.efi`. D1-boot launched (one-shot entry #48 + reboot).

### 21:46-22:22 - preflight, controller, groups A/B, two fixes deployed

- preflight: main = laptop = `473593a` clean; normal boot on `@`; HEALTHY;
  `/` 207 GB free, RAM 14 GB free, swap 0; entries #47 #46 #44 #43; sshd +
  firewall active; Hyprland/quickshell/hypridle/hyprpolkitagent 1 each, no
  hyprlock; Coffee on; faillock empty; 29 pending updates.
- controller: 20/20 simulations (ssh loss / delayed / permanent ->
  WAITING_FOR_LOCAL_INTERVENTION, kill -9 + resume, duplicate invocation,
  unexpected result, lost replies of a destructive step, reboot needs a new
  boot id, approval gate, sudo password via stdin only, fresh state).
- A1 tests/run.sh: all checks passed (before and after the fixes).
- A2 BT1 real: popup open, `rfkill block` of the ThinkPad switch removes hci0
  -> **defect**: popup came back by itself when the adapter returned, next
  click closed it. Fixed `5498e19` (qml-logic regression), deployed,
  re-tested real: stays closed, click opens, Escape closes, same Quickshell
  pid, no QML errors.
- U6 (pacman lock) real PASS: preflight refused, no snapshot, entries and
  packages unchanged, dialog lastResult code 1. (First attempt: my driver
  missed sudo's prompt, sudo timed out after 5 min -> 1 faillock entry,
  cleared by the next successful sudo; nothing ran.)
- U1 (real update through the dialog) real PASS: 29 packages, snapshot #48,
  `RESULT: updated, healthy.`, icon gone, entries #48 #47 #44 #43. The user
  answered pacman's Y/n (driver could not see the root prompt) and asked for
  `--noconfirm` -> `143179a` (tests/system-update.sh), deployed.
- deploy: dry run = 3 files + pacman sync + 2 handlers; real changed=5,
  second run changed=0; HEALTHY; Coffee on; entries unchanged.
- B polkit real: normal authorization (pkexec /usr/bin/true via the
  hyprpolkitagent dialog) PASS rc 0. **Finding P1**: Cancel (Escape) ends
  the PAM conversation empty -> `pam_authenticate failed`, 1 faillock entry
  per cancel (deny=3 / 15 min by default -> 3 cancels lock the account,
  hyprlock included, 10 min). Not changed (PAM/agent, out of scope).
- B lockscreen real PASS: logind Lock -> hyprlock, correct password via
  uinput unlocks, 0 faillock entries, Coffee/hypridle intact. LockedHint
  stays "no" (cosmetic).
- C firewall SSH test: not repeated - the root helper is unchanged since the
  user's own acceptance (2026-10-10: enable/disable/delete SSH confirmed);
  no firewall state changed in this batch.
