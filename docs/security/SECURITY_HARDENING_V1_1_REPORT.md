# Security Hardening v1.1 - report

2026-10-14 (overnight, unattended). Implements the decisions on findings
S3 and S4 of `SECURITY_AUDIT_V1_REPORT.md`. Branch `hardening-v1.1`, merged
into `main` (`b75a76b`) and deployed to the ThinkPad T440p. Progress log:
`SECURITY_HARDENING_V1_1_OVERNIGHT.md`.

## 1. Privilege matrix

| Operation | Before | After |
|---|---|---|
| Firewall: read the rule list (incl. live kernel state) | `pkexec firewall-rules list`, `firewall.manage` active **yes** | `pkexec firewall-status` (fixed `firewall-rules list`, no arguments), `firewall.status` active **yes** |
| Firewall: add / edit / enable / disable / remove / reset | `firewall.manage` active **yes** | `firewall.manage` **auth_admin_keep** (password, kept ~5 min) |
| Manual snapshot: create into an empty slot | `snapshot.create` active **yes** | unchanged (**yes**), `snapshot-create set` only |
| Manual snapshot: overwrite (deletes the old one) | `snapshot-create set <slot> <label> <n>`, **yes** | `snapshot-delete replace`, `snapshot.delete` **auth_admin_keep** |
| Manual snapshot: delete | `snapshot-create delete`, **yes** | `snapshot-delete delete`, `snapshot.delete` **auth_admin_keep** |
| Snapshot list / metadata | user, no privilege | unchanged |
| Permanent restore | auth_admin always | unchanged |
| Automatic snapshots, retention, snapper cleanup, boot entries | root (pacman hook, system-update, snapper timer, snapper plugin) | unchanged |
| Docker daemon | user in `docker` = root while Docker runs | not in the group; `sudo docker` |
| Remote / inactive sessions | auth_admin for every action | unchanged |
| sudo | `(ALL) ALL` with password | unchanged |

## 2. Authorization mechanism

Standard polkit only - no rules file, no own credential cache. pkexec maps
one program to one action (`org.freedesktop.policykit.exec.path`), so every
privilege level has its own program:

- `firewall-status` (new, 8 lines): `[ $# -eq 0 ]`, then `exec
  firewall-rules list` - nothing a caller passes reaches the helper.
- `snapshot-create` and `snapshot-delete`: ONE file installed under both
  names; the installed name decides the allowed verbs (`snapshot-create`:
  `set` into an empty slot; `snapshot-delete`: `delete`, `replace`).
  pkexec runs exactly the root-owned path from the policy; a renamed copy
  has no root. `snapshot-boot slot-set` itself refuses an occupied slot
  without `--replace`, so the passwordless path cannot remove a snapshot.
- **Cache**: polkit's `auth_admin_keep` = a temporary authorization for
  that action and subject; with pkexec the subject is the calling process
  (Quickshell, long-lived), so a series of changes asks once. Measured:
  authorized 00:34:47, required again at 00:39:46 (~5 min). The cache is
  per action - a firewall password never authorizes a snapshot deletion.
- Cancellation / failure: pkexec returns 126/127 and never starts the
  helper. P1 (`/etc/pam.d/polkit-1`) keeps a cancel out of faillock.
- UI: the Firewall window and the snapshot dialog are overlays that would
  cover the polkit agent's window and keep the keyboard. They hide while a
  password may be asked (firewall: every change; dialog: overwrite/delete
  only) and return with the result; `open()` is ignored meanwhile. The
  firewall window keeps its content (and the helper's Process) loaded
  while hidden.

## 3. Docker

`roles/development` no longer adds the user; it removes the membership
(`getent` + `gpasswd --delete`, only when a member - idempotent). The
private provisioning repository adds no group (it has shell aliases `d`,
`dc`, `lzd` that now need `sudo`; the user's dotfiles were not changed).
Docker data, units (disabled, inactive) and configuration unchanged; nothing
passwordless replaces the group. `repo-healthcheck` "docker access": FAIL
when the user is in the group, WARN while the login session still has it.

**Session status**: the account database and every new login (SSH) are
without `docker`; the running desktop session (Quickshell's process) still
carries gid 960 until the next login - a terminal opened from the desktop
can still use the Docker socket while Docker runs. Not forced (no logout).

## 4. Regression tests

| Test | What | Before the change |
|---|---|---|
| tests/privileges.py (new) | every polkit action rendered: who without password, which one program; firewall-status = one exec of `list`; no task adds `docker`; the removal's condition for 6 getent shapes; no NOPASSWD | 11 FAIL |
| tests/firewall.sh (+7) | firewall-status = list; 6 argument sets refused, kernel + state unchanged | template missing |
| tests/system-update.sh (+~20) | snapshot-create refuses replace/delete; snapshot-delete argv for delete/replace, label one element, 10 malformed calls + 4 bad labels refused, other installed names refused | 7 FAIL |
| tests/qml-logic.qml (+4) | dialog argv per action, `needsPassword` | new functions |
| tests/healthcheck-polkit-pam.py (+3) | docker access PASS / FAIL / WARN | new function |

`tests/run.sh`: all passed (before deployment and after the fix in 5).
shellcheck (`snapshot-create`) and pyflakes clean.

## 5. Live validation on the ThinkPad (real, through the real polkit agent)

| Check | Result |
|---|---|
| direct calls without root: firewall-rules add/enable, firewall-status, snapshot-create, snapshot-delete, snapshot-boot slot-delete | all refused |
| pkexec from an SSH session (not the active seat) | no agent -> refused, also for reading |
| Firewall window opens, list loads | no polkit prompt |
| change -> Cancel (x3, also two cycles in one window) | prompt; window hidden, back with "Not authorized - the firewall was not changed."; nft table hash identical; faillock 0 |
| change -> ONE wrong password -> Cancel | faillock 1 (wrong password counted), nothing changed |
| change -> correct password | LocalSend TCP disabled; faillock back to 0 (authsucc); `pkcheck` authorized |
| next change within 5 min | **no prompt**, rule enabled again; nft table hash = the pre-test baseline |
| after ~5 min (00:39:46) | prompt again; a reopen via IPC during the prompt ignored; Cancel -> unchanged |
| snapshot dialog: list | no prompt |
| `pkexec snapshot-create set 4 x` from the session | no prompt, the helper ran and refused slot 4 (passwordless path reached the helper; nothing created) |
| dialog Delete (slot 1, #43) -> Cancel | dialog hidden, prompt, back with "Not authorized ... nothing was changed"; slots unchanged; faillock 0 |
| dialog Overwrite (slot 1) -> Cancel | same; slots unchanged |
| safety | before every deletion attempt `pkcheck` confirmed no cached snapshot.delete authorization; no password was ever typed for a deletion; **no snapshot deleted** |
| close policy, both windows (Escape, Super+Q, click outside) | 8/8 |
| lock -> correct password -> unlock | pass, faillock 0 |
| Docker: socket `root:docker 0660`; `docker version` as the user | permission denied; the refused connect did not start the daemon |
| resources (30 s idle) | quickshell 0.00 % CPU, PSS 229 MB (same pid since before; Bug Hunt v1 plateau ~280 MB); Hyprland 0.00 %, 111 MB; swap 0 |

**Defect found by the GUI test and fixed (`697dae7`)**: the firewall window
cleared `hiddenForAuth` before showing itself again, so its Loader went
inactive for that moment and the content was recreated; the next change in
the same window then stayed visible over the prompt and ended closed. Now
visible first; re-test: two cycles in one window pass.

Not tested live: a deletion/overwrite that actually completes (would delete
a real snapshot; covered by the mocked helper tests and the unchanged
`snapshot-boot` paths), automatic retention (no package transaction was
run; code paths unchanged), GUI login (no logout).

## 6. Deployment

Branch deployed first (dry run: two helpers, four policies, Quickshell, the
healthcheck - no ruleset/unit/sshd/PAM/boot change, no firewall reload),
run 1 changed=10, run 2 changed=0; after the fix changed=0 (the live-copied
QML matched). Final deployment from `main` `b75a76b`: changed=9, then 0.
Rollback: switch to the previous `main` and bootstrap (the old role restores
everything incl. the group), or `git revert`.

## 7. Incidents during the night (all mine, all recovered)

1. **Old main deployed for ~10 min**: `git switch main` failed on an
   uncommitted log file, the chain stopped before merge/push, and the laptop
   bootstrapped the old `main` - the hardening was reverted and the user put
   back into `docker`. Re-deployed from the correct `main` immediately; the
   final state is verified (section 8).
2. **Docker daemon started by the test**: `sudo docker version --format`
   still queries the server, so the socket started dockerd, which set
   `ip_forward=1` and created its own nft tables. Stopped again;
   `ip_forward` reset to 0 - and the kernel then switched
   `conf.all.accept_redirects` to 1 (`inet_forward_change`); repo-healthcheck
   reported it (UNHEALTHY), the configured 0 was restored. Docker's tables
   stay until the next boot (Docker owns them; FORWARD policy drop); the
   `inet workstation` table was never touched (hash identical).
3. `sudo -n` inside `$( )` failed four times ("a password is required")
   while hashing - no authentication attempt, no faillock entry.

## 8. Final state

No reboot (up since 2026-10-13 22:27), normal boot on `@`, HEALTHY,
faillock 0, SSH over Ethernet and Wi-Fi, `inet workstation` table =
baseline, rules.json, snapper list and boot entries = baseline, no package
transaction, Docker inactive/disabled, no test process or test file left,
session unlocked (Coffee on).

## 9. Remaining risks / user actions

- **Log out and back in once**: the running desktop session still has the
  `docker` group (healthcheck from that session: WARN). Optionally prefix
  the private aliases `d`, `dc`, `lzd` with `sudo`.
- A cached firewall authorization (~5 min) also covers other processes'
  pkexec calls only if they run under the same subject (Quickshell) -
  standard polkit behaviour.
- Docker's leftover nft tables until the next reboot (inert).
- Pre-existing, unrelated: a transient `Scratchpad.qml[18:5]` binding
  warning at every Quickshell config reload (since 2026-10-13).
- SSH remains open (postponed by the user until release acceptance);
  LocalSend exposure accepted.
