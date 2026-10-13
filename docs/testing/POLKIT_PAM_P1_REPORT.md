# P1 - polkit cancel counted as a failed login: report

2026-10-13. Found in the supervised integration tests
(`docs/testing/BUGHUNT_V1_SUPERVISED_REPORT.md`, finding P1); fixed in
`c6960fa`, deployed to the ThinkPad T440p (`laptop`).

## Symptom

Cancelling a polkit password dialog (hyprpolkitagent, Escape / Cancel) added
one `pam_faillock` entry. With Arch's defaults (deny=3 within 15 min,
unlock_time 600 s) three cancels - or two cancels and one typo - locked the
account for 10 minutes: polkit, sudo, Ly and hyprlock refused even the
correct password.

## Root cause (verified)

| Step | Component | Evidence |
|---|---|---|
| 1 | polkit 127 runs the agent helper as a **socket-activated root unit** (`polkit-agent-helper.socket`, `Accept=yes`, `polkit-agent-helper@.service`); the binary is no longer setuid | laptop: unit files, `-rwxr-xr-x polkit-agent-helper-1`, journal `polkit-agent-helper@0-1-...service` |
| 2 | On Cancel the agent calls `polkit_agent_session_cancel()` -> `kill_helper()`, which in socket mode can only **close the socket**; the `SIGTERM` + `waitpid` path exists only for the old setuid child | polkit `src/polkitagent/polkitagentsession.c` `kill_helper()` (master, 2026-10-07) |
| 3 | The helper is blocked in its PAM conversation; `fgets()` on the socket returns NULL -> the conversation returns `PAM_CONV_ERR` | `polkitagenthelper-pam.c` `conversation_function()`; journal `pam_unix(polkit-1:auth): conversation failed` |
| 4 | `pam_get_authtok()` turns the failed conversation into `PAM_AUTHTOK_ERR` ("We want to abort"); pam_unix logs "auth could not identify password" | linux-pam 1.7.3 `libpam/pam_get_authtok.c`, `modules/pam_unix/pam_unix_auth.c`; journal `pam_authenticate failed: Authentication token manipulation error` |
| 5 | PAM service **polkit-1** (`/usr/lib/pam.d/polkit-1` = `include system-auth`): `auth [success=1 default=bad] pam_unix.so` -> `auth [default=die] pam_faillock.so authfail` **records a failure** | pambase `system-auth` (unmodified on the laptop, `pacman -Qkk pambase`) |
| 6 | The lockscreen is affected because hyprlock -> `login` -> `system-local-login` -> `system-login` -> `system-auth`, whose `pam_faillock preauth` refuses a locked user before any password check; the tally is per user, shared by every service | `/etc/pam.d/hyprlock`, `login`, `system-*` |

With the old setuid helper the agent killed the helper mid-conversation, so
`authfail` was never reached - the bug came with socket activation. It is
**not** specific to this repository or to hyprpolkitagent: every agent goes
through the same libpolkit-agent cancel path. Sandbox reproduction: one
cancel = tally 1, three cancels = correct password refused.

**Upstream**: no fix. polkit master (2026-10-07) unchanged in both files; no
issue or PR for cancel/faillock (searched); related socket-mode regressions
exist (#695 pam_unix under the socket helper, #622 pam_u2f) with other
symptoms. Red Hat documents the same class for GDM dialogs
(access.redhat.com/node/2455971).

## Fix

`/etc/pam.d/polkit-1` (roles/desktop, `roles/desktop/files/polkit-1.pam`;
takes precedence over polkit's `/usr/lib/pam.d/polkit-1`, owned by no
package): the auth section of `system-auth`, line for line, with ONE
control value added on pam_unix:

```
auth  [success=1 authtok_err=die default=bad]  pam_unix.so  try_first_pass nullok
```

`authtok_err=die` ends authentication immediately as a failure (returning
`PAM_AUTHTOK_ERR`) without running `pam_faillock authfail`.
account/password/session stay `include system-auth`.

**Why it is security-equivalent**: in pam_unix's *auth* path
`PAM_AUTHTOK_ERR` comes only from `pam_get_authtok()` when no password was
obtained (all other `PAM_AUTHTOK_ERR` returns in pam_unix are in the
account/password-change code). Every submitted password - wrong or empty -
is checked by `_unix_verify_password()` and returns `PAM_AUTH_ERR`, which
still reaches `authfail`. So a guess always counts; only "no guess" does not.
`preauth` (refusing a locked account), `deny`, `unlock_time`, `authsucc`
(reset on success) and `pam_systemd_home` are unchanged; no other PAM
service (sudo, login, hyprlock, sshd, Ly) is touched. A cancel still fails
the authorization (pkexec 127) - nothing is granted.

## Alternatives rejected

| Option | Why not |
|---|---|
| Upstream fix | none exists |
| Fix in the agent (hyprpolkitagent) | impossible: the cancel path is libpolkit-agent's; an agent cannot stop a root helper unit |
| setuid helper again (`chmod u+s`, helper fallback) | re-introduces a SUID root binary Arch deliberately removed; pacman would reset it |
| patched polkit (helper exits on EOF without failing PAM) | own package build / fork - against the package source policy, maintenance |
| raise `deny`, drop `pam_faillock`, reset the tally automatically | weakens lockout - forbidden |
| change `system-auth` itself | affects every service; out of scope |

## Tests and evidence

| Test | Level | Result |
|---|---|---|
| `tests/pam-polkit.sh`: host's real pam_unix / pam_faillock in a bwrap user namespace (own /etc, /run, throwaway user), stock `system-auth` fixture | isolated | 17/17: stock reproduces P1 (cancel counted, 3 cancels lock); fixed: cancel fails but not counted, 6 cancels then correct password succeeds, wrong and empty passwords counted, wrong/cancel/cancel/wrong = 2, success resets, 3 wrong still lock, locked + cancel still refused, `system-auth` unchanged; /etc precedence over /usr/lib |
| same test against the vendor stack | isolated | 5 checks FAIL (proves the test catches the bug) |
| `tests/healthcheck-polkit-pam.py` | mocked | in sync PASS, missing / vendor FAIL, system-auth drift WARN |
| `tests/run.sh` | mocked/isolated | all checks passed |
| shellcheck -S warning, pyflakes | static | only SC2034 false positives (variables used in `eval` strings) |

Note: the host has pam 1.7.2, the laptop 1.7.3 - the relevant code paths
(pam_get_authtok, pam_unix auth, pam_faillock) are identical.

## Deployment

Dry run: pacman DB sync (known cosmetic), `/etc/pam.d/polkit-1` (new),
`repo-healthcheck`. Real run changed=3, second run changed=0. Healthcheck
"polkit PAM stack" PASS, HEALTHY.

## Live hardware acceptance (ThinkPad, real)

| Step | Result |
|---|---|
| faillock at start (also after sudo) | 0 |
| cancel #1 (hyprpolkitagent dialog, Escape) | pkexec rc 127, helper `pam_authenticate failed`, faillock **0** |
| cancel #2 (only because #1 stayed 0) | rc 127, faillock **0** |
| normal authorization (password typed into the dialog) | rc 0, faillock 0 |
| logind Lock -> hyprlock -> correct password | unlocked, faillock 0 |
| SSH (Ethernet + Wi-Fi) | ok; sshd key-only (PASS) |
| final | normal boot on `@`, HEALTHY, faillock 0, no test processes/files |

No incorrect password was submitted on the laptop; wrong-password accounting
is proven in the sandbox only (by design).

## Remaining risks

- **Drift**: a future `pambase` change to `system-auth` is not followed by
  the copy automatically. `repo-healthcheck` WARNs ("polkit PAM stack") and
  names the file to update.
- Other services keep the general behaviour (an aborted conversation counts
  there too); not reachable by a dialog cancel today (sudo is killed by
  Ctrl+C before PAM returns, hyprlock/Ly have no cancel).
- When polkit fixes the helper upstream (exit on EOF), the override becomes
  redundant but stays harmless; remove it then.
