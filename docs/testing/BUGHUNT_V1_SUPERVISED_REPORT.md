# Bug Hunt v1 - supervised integration tests: report

2026-10-13, 21:46-22:32, ThinkPad T440p (`laptop`), from `main` = `473593a`
(Bug Hunt v1, HEALTHY). Plan: `docs/testing/BUGHUNT_V1_SUPERVISED_RESUME.md`.
Checkpoints: `docs/testing/BUGHUNT_V1_SUPERVISED_STATUS.md`.

Levels: **simulated** = the test controller against a fake ssh (no host),
**mocked** = repository tests with stubs, **real** = the laptop's actual
system and desktop.

## 1. Executive summary

Every safely executable test of the resume plan ran on the real laptop,
including the first real update through the dialog and a full snapshot boot
round trip (two reboots). Two product changes came out of it, both deployed
and idempotent: a real Bluetooth popup defect (BT1, now fixed) and the
user's request for an update without pacman's Y/n question. One
authentication finding (P1: cancelling a polkit dialog counts as a failed
login) is documented, not changed. The permanent restore was deferred by the
user. The laptop ends in normal boot on `@`, reachable over both SSH paths,
HEALTHY, faillock empty.

## 2. Tests executed

| ID | Test (resume plan #) | Level | Result |
|---|---|---|---|
| CTL | test controller: 20 simulations (ssh loss / delayed / permanent, kill -9 + resume, duplicate invocation, unexpected result, lost replies of a destructive step, reboot needs a new boot id, approval gate, sudo password via stdin only, fresh state) | simulated | 20/20 PASS |
| A1 | `tests/run.sh` (before and after the fixes) | mocked | PASS |
| A2 | preflight / final read-only checks | real | PASS |
| BT1 | Bluetooth popup open while the adapter vanishes (#2): ThinkPad `rfkill` switch removes hci0 | real | **defect found**, fixed, re-test PASS |
| U6 | pacman lock injection (#6): stale `db.lck` -> dialog -> Yes | real | PASS: preflight refused, nothing changed |
| U1 | real update through the dialog (#1), 29 packages | real | PASS: snapshot #48, `RESULT: updated, healthy.`, icon gone |
| DEP | deployment of the two changes (dry run, real, second run) | real | PASS: changed=5, then 0 |
| B1 | polkit normal authorization (`pkexec /usr/bin/true` from the session, hyprpolkitagent) | real | PASS (rc 0) |
| B2 | polkit cancel (Escape) | real | PASS functionally (rc 127, nothing ran) - **finding P1** |
| B3 | lockscreen: logind Lock -> hyprlock -> correct password | real | PASS, 0 faillock entries |
| B4 | Coffee after component restart | real (Bug Hunt v1, RICE) + today | not repeated; survived today's in-place Quickshell reload |
| C1 | firewall SSH rule via the UI (#3) | - | NOT REPEATED (see 5) |
| D1 | snapshot boot (#4): one-shot entry #48, verify, back to normal | real | PASS (pre / boot / return) |
| E1 | permanent restore (#5) | - | DEFERRED by the user |
| F | final validation | real | PASS |

## 3. Passed

CTL, A1, A2, U6, U1, DEP, B1, B2 (behaviour), B3, D1 (D1-pre, D1-boot,
D1-return), F, BT1 after the fix.

D1 evidence: snapshot boot = cmdline `workstation.snapshot=48`, `/` overlay,
chromium 153 (the pre-update version), pacman aborted by the hook ("snapshot
mode (snapshot 48): package changes are blocked"), Quickshell snapshot mode
active (IPC `active:true, number:48`, strip layer), `/home` = `@home`, no
failed units, faillock 0; normal boot afterwards = `/` `@` (subvolid 297),
chromium 154, HEALTHY. SSH came back 45-50 s after each reboot (LUKS by the
user).

## 4. Failed

None at the end. BT1 failed before its fix (see 11).

## 5. Blocked / deferred / not repeated

- **E1 permanent restore: DEFERRED** (user's decision). Already real-tested
  2026-10-10 (#32). Remaining gap: `workstation-snapshot-boot-resync.service`
  after a real restore (added after that test; logic-tested only).
- **C1 firewall SSH rule: NOT REPEATED.** The root helper `firewall-rules` is
  unchanged since `00240a2`, which the user accepted on real hardware
  (enable / disable / delete SSH); later commits touched only the window's
  presentation. No firewall state was changed in this batch, so the
  independent-rollback precondition never applied.
- **#7 power loss / LUKS / bootloader**: out of scope (resume plan).

## 6. User interactions

7 in total: 1 batch of 4 decisions (password mode, real update yes, reboot
go, restore defer), the password once in chat (used only through stdin),
1 pacman Y/n answer (the driver could not see the root prompt - see 13),
2 LUKS unlocks. No boot menu or dialog operation by the user.

## 7. Recovery events

- U6 first attempt: the driver missed sudo's prompt in the update terminal;
  sudo timed out after 5 min (`timed out reading password`), nothing ran,
  1 faillock entry, cleared by the next successful sudo (no manual reset).
  The leftover terminal was closed and the test's `db.lck` removed.
- U1: the driver could not see pacman's prompt (root process, `wchan`
  unreadable); the user answered it, the driver was stopped and the result
  collected by hand.
- No SSH loss beyond the two planned reboots; no WAITING_FOR_LOCAL_INTERVENTION.

## 8. Boot and root state (final)

Normal boot, loader default `arch-linux.efi`, no one-shot pending, `/` = `@`.
Entries: #48 #47 (update), #44 #43 (manual) + the legacy "before update"
recovery entry; #46 left by retention during U1, as designed.

## 9. SSH / firewall

sshd + `workstation-firewall` active, chain `repo_rules` with the 5 standard
rules, all enabled (SSH included); both SSH paths (dock Ethernet, Wi-Fi)
answer with the same host key.

## 10. Authentication findings

- **P1 (medium, upstream behaviour, not changed)**: Escape in the
  hyprpolkitagent dialog ends the PAM conversation empty ->
  `pam_authenticate failed` and **one `pam_faillock` entry per cancel**.
  With the Arch defaults (deny=3 in 15 min, unlock 10 min), three cancels -
  or two cancels and a typo - lock the account, hyprlock included. A
  successful authentication clears the tally. Options for a later security
  batch: report upstream; or a polkit-specific PAM stack without
  `pam_faillock` (a PAM change - out of scope here).
- normal polkit auth, sudo, hyprlock and Ly login: no failure entries.
- faillock was never reset by hand; final state: empty.
- logind's `LockedHint` stays "no" while hyprlock is up (cosmetic).

## 11. New bugs

| ID | Severity | Defect |
|---|---|---|
| BT1 | low-medium | The Bluetooth popup's Loader unloaded when the adapter vanished, but `popupOpen` stayed set: the bar coordinator kept an invisible popup, the popup reappeared by itself when the adapter came back, and the next click closed instead of opened. (Bug Hunt v1 suspected only transient warnings.) |
| P1 | medium | see 10 (not a repository defect) |

## 12. Fixes and regression coverage

| Commit | Change | Test |
|---|---|---|
| `5498e19` | Bluetooth widget closes its popup when the adapter goes away | `tests/qml-logic.qml` (fails without the fix); real re-test PASS |
| `143179a` | `system-update`: `pacman -Syu --noconfirm` (user request; a conflict still aborts - pacman's default there is No); dialog text, README, recovery design | `tests/system-update.sh` (fails without the change) |

The `--noconfirm` path has not yet run a real update (none pending after U1).

## 13. Git / deployment

`main`: `5498e19`, `143179a` (product, deployed: dry run = 3 files + the
known pacman sync + 2 handlers; real changed=5; second run changed=0;
HEALTHY), then this batch's harness and documentation commits (nothing
deployed). The laptop's checkout is `143179a`, clean.

Harness: `tests/supervised/` (`testctl.py`, `selftest.sh`, stubs,
`plan-snapshot-boot.json`). Lessons for the next supervised run: a
prompt-detection by `/proc/<pid>/wchan` works for user processes only (root
processes read `0`); `pgrep`/`pkill -f` patterns must not match the
caller's own command line.

## 14. Remaining risks

- P1 lockout through polkit cancels (until handled in the security batch).
- Restore + resync unit after a real restore: not on hardware.
- The `--noconfirm` update path: mocked only so far; its first real use is
  the next real update.
- Driving terminals by `wchan` cannot see root prompts.

## 15. Recommended next step

The planned security audit / hardening batch, starting with P1 (polkit
cancel -> faillock), then the deferred restore + resync test when a restore
is actually wanted; L1 (German strings) in a polish batch.
