# Bug Hunt v1 - report

2026-10-11, branch `bughunt-v1` from `main` = `5c60635` (RICE v1, deployed,
HEALTHY). Test machine: ThinkPad T440p (`laptop`). Checkpoints:
`docs/testing/BUGHUNT_V1_STATUS.md`; remaining supervised work:
`docs/testing/BUGHUNT_V1_SUPERVISED_RESUME.md`.

Test levels used below: **static** (review / linters), **mocked** (stubs in
temporary directories), **isolated** (a separate `quickshell -p` instance or
temp files on the laptop, the desktop untouched), **real** (the laptop's
running desktop / system), **not tested**.

## 1. Executive summary

Four confirmed defects found and fixed, each with a regression test; no
defect in the security-relevant root helpers (firewall, snapshot slots,
restore) beyond cosmetic language. One consolidated deployment: dry run
(4 files, nothing touching SSH/firewall/PAM/boot/storage), rc 0, re-run
changed=0, HEALTHY, GUI close-policy 66/66 and tier-3 combinations 20/20 on
the real desktop afterwards, no idle CPU/swap regression, no memory leak
over 400 overlay openings. Nothing critical was executed unattended.

## 2. Components audited

Bootstrap scripts, Ansible deployment (dry run + real), all shell and
Python helpers (shellcheck + pyflakes on rendered templates), root helpers
(firewall-rules, snapshot-create, snapshot-restore, system-update(+root),
pre-transaction hook, recovery-lib, snapshot-boot), theme helper, Quickshell
(overlays, close policy, fonts/colors data, scratchpad persistence,
Bluetooth/power null handling, display-scale writer), Hyprland session
helpers (session-stop, focus-or-launch), connectivity helpers (wifi-qr,
portal-login), screenshot helper, update check, healthcheck, git-sync.

## 3. Methodology

Read-only first; risky behaviour reproduced in mocks or isolated
instances; a fix only after a failing reproduction; one deployment for all
fixes; GUI tests with the user-authorised one-shot uinput device; Coffee
kept on (the session never locked during the run; no unlock was needed).
Linters ran from a venv in the session scratchpad (the host unchanged).

## 4. Coverage matrix

| Area / combination | Level | Result |
|---|---|---|
| Linters (shellcheck -S warning, pyflakes) on all helpers | static | no real defect (false positives: `done` as a string, `~` in a message) |
| Root helpers input validation, atomic writes, locks | static | ok |
| firewall-rules (existing tests/firewall.sh 77 checks) | mocked | pass |
| Updates: none / one / two / offline / error / lock / snapshot fail / pacman fail / parallel / no sudo | mocked | pass |
| Update: step after pacman fails | mocked | **defect SU1, fixed** |
| checkupdates interrupted (kill -9 mid-sync, private DB) | isolated | no stale lock, next run ok |
| Snapshots: zero/full/duplicate slots, overwrite failures, Secure Boot, missing UKI, snapshot mode refusals (tests/snapshot-boot.py) | mocked | pass |
| Half-written info.xml in the slot list | static | skipped, never fails the list |
| pacman hook in a snapshot boot | mocked | aborts, no snapshot (new test) |
| Theme × font size × screen, dark/light × 9/11/12/18 | isolated (RICE audit) + real | pass |
| Theme switch × open dialog; text size 18 × open Appearance | real | pass |
| Missing / malformed colors.json | isolated | handled, warning only |
| Invalid text_size in colors.json | isolated | **defect F1 (all text 0 px), fixed** |
| Imported theme's wallpaper in the healthcheck | mocked | **defect HC1, fixed** |
| Wallpaper file name with a line break (foreign theme data) | mocked | **defect TH1 (state injection), fixed** |
| Concurrent theme commands (8 × 20 parallel toggles) | mocked | pass (existing) |
| Quickshell restart × Coffee (B1, fixed in RICE) | real | pass (earlier today) |
| Rapid repeated IPC toggles / Super+Space / focus between overlays | real | pass |
| Clipboard × launcher | real | one surface at a time |
| Close policy (Escape / Super+Q / outside click, 66 checks) | real | pass, before and after deployment |
| FileView watch: rename-replace ×2, delete+recreate, missing at start | isolated | pass - scratchpad safe |
| focus-or-launch: garbage / failing hyprctl / invalid regex | mocked | pass (new test) |
| Session helpers parentage after RICE `env -u`; logout coredumps | real | direct children of Hyprland; none |
| wifi-qr escaping, portal-login policy keys, display-scale writer | static | ok |
| Bluetooth adapter vanishing while its popup is open | not tested | suspected transient warnings only |
| Polkit cancel / denied / helper failure in the UI | mocked (qml-logic, existing) | pass |
| Memory over 400 overlay openings | real | plateau 277-285 MB, no leak |

## 5./6. Confirmed and fixed bugs

| ID | Severity | Defect | Fix | Test |
|---|---|---|---|---|
| SU1 | medium | `system-update`: with `set -e`, a failing root step after pacman (e.g. sudo's timestamp expired during a long run and the new prompt was refused) ended the script right after pacman - **no boot image check** (the warning before rebooting into a broken UKI), no health check, no RESULT | failure recorded, remaining checks run, RESULT names it, exit stays non-zero (`bc5982f`) | mocked, tests/system-update.sh `POST_FAIL` |
| F1 | medium (rare trigger) | `Fonts.size` took a non-numeric `text_size` from colors.json: binding failed, size 0, **every shell text 0 px** (isolated instance: textSize 0) | `Fonts.sizeFrom()` 6..48 else default (`7c23e8c`) | qml-logic + isolated instance now 11 |
| TH1 | low-medium | a background file name with a line break (imported theme repository) injected a key into `theme-state` (sandbox: rc 0, state changed) -> malformed state, every theme command refused | names with control characters are not offered (`7c0d967`) | mocked, tests/theme-helper.sh |
| HC1 | low | healthcheck reported an imported theme's own wallpaper as "file gone" (WARN) | looks in bundled + compiled dirs like the helper (`6a55374`) | mocked, tests/healthcheck-theme.py |

## 7./8. Deferred findings

| ID | Severity | Finding | Proposal |
|---|---|---|---|
| L1 | cosmetic | German text left while the UI is English: firewall-rules error messages and factory labels ("LocalSend – Geräteerkennung"), screenshot/OCR notifications, repo-logs headers, log analysis notes | one language pass in a later polish batch; firewall factory labels change only for new/reset states (rules.json keeps the user's) |
| BT1 | low, suspected | Bluetooth popup open while the adapter disappears: transient binding warnings during teardown expected | supervised: remove a USB adapter / `rfkill` with the popup open, read the journal |
| M1 | observation | Quickshell PSS plateau ~280 MB after heavy use vs. 182-213 MB fresh (Qt keeps caches); no growth over 400 openings | none needed; watch in the RICE baseline |

No security boundary was weakened; no PAM/sudoers/polkit/SSH/firewall
policy/boot/storage change was made.

## 9. Regression tests added

tests/healthcheck-theme.py (new), tests/session-helpers.sh (new), cases in
tests/system-update.sh (post failure), tests/theme-helper.sh (control
characters in a wallpaper name), tests/recovery-snapshots.sh (snapshot
boot), tests/qml-logic.qml (`Fonts.sizeFrom`). All run by tests/run.sh.

## 10. Performance

After deployment, 60 s idle + 2 x 30 s windows: quickshell CPU 0.0 %,
Hyprland 0.0 %, swap 0 (bounded; no synthetic stress). Memory: see M1.

## 11./12. Deployment and healthcheck

`--check --diff`: repo-healthcheck, system-update, ~/.local/bin/theme,
Fonts.qml + the pacman DB sync. Real run rc 0, ok=219 changed=6; handlers:
Quickshell reload (same pid 34842), snapshot-boot sync (entries identical
before/after: #47, #46, #44, #43 - the dry run had not shown this handler).
After 30 s: SSH ok, Hyprland/quickshell/hypridle/hyprpolkitagent/wl-paste 1
each, Coffee on, no lock, faillock 0, `repo-healthcheck` HEALTHY. Second
bootstrap changed=0.

## 13. Commits

`6a55374` HC1, `bc5982f` SU1, `7c23e8c` F1, `7c0d967` TH1, `3cdfb38` tests,
plus status/report commits.

## 14. Unresolved risks

- The real update path (`system-update` through the dialog) and the other
  critical tests stay supervised (resume document).
- `system-update`'s normal path is unchanged; the fix touches only the
  error path, verified by mock.
- BT1 not exercised.

## 15. Next steps

Supervised resume (critical tests), then the planned architecture
refactoring and security audit (not started here); L1 in a polish batch.
