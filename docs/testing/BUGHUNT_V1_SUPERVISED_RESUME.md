# Bug Hunt v1 - supervised resume (critical / blocked tests)

Nothing below was run unattended. Order = increasing risk. Each needs the
user at the laptop; stop at the first unexpected result.

General preconditions: laptop on AC, docked (Ethernet .49) AND Wi-Fi up
(.56) as a second SSH path, `faillock --user medvidec` empty, `main`
deployed, `repo-healthcheck` HEALTHY, a fresh manual snapshot slot (OS menu
-> System -> Create Snapshot) before tests 4-7.

## 1. Real system update through the dialog (SU1 normal path)
- Precondition: at least one pending update (`workstation-checkupdates`).
- Action: OS menu -> System -> Update -> Yes; enter the sudo password.
- Expected: snapshot before pacman, `pacman -Syu`, "boot image check",
  "repo-healthcheck (after)", `RESULT: updated, healthy.`, bar icon gone.
- Failure signals: no RESULT line, UKI warning, healthcheck FAIL.
- Recovery: boot menu "Snapshot (before update) ..." -> test -> restore.
- User: password, watch the terminal.

## 2. Bluetooth popup while the adapter goes away (BT1)
- Action: open the Bluetooth popup; `rfkill block bluetooth` (or unplug a
  USB adapter); wait 5 s; `rfkill unblock bluetooth`.
- Expected: popup closes or shows Off/Blocked; no stuck UI; journal
  (`journalctl --user -t quickshell -n 50`) at most transient warnings.
- Recovery: `rfkill unblock bluetooth`; `qs ipc call shell reload` if stuck.

## 3. Firewall rule change via the UI (not changed by this batch)
- Precondition: second SSH path verified.
- Action: Settings -> Firewall -> disable the SSH rule; from another host
  `ssh -o ConnectTimeout=5 laptop true` (expect refused/timeout for NEW
  connections, the open session survives); enable again; test again.
- Recovery: in the session: Enable / Restore standard rules; from a TTY
  `sudo /usr/local/libexec/workstation/firewall-rules reset`.

## 4. Snapshot boot selection (no restore)
- Action: reboot, pick a "Snapshot (before update) ..." entry, unlock LUKS.
- Expected: snapshot-mode strip, pacman blocked, `/` overlay.
- Recovery: normal reboot -> the default entry.
- User: LUKS password, boot menu.

## 5. Snapshot restore (permanent)
- Only from test 4's snapshot boot: dialog -> Restore permanently -> admin
  password -> Reboot now.
- Expected: @ = snapshot state, `@broken-<date>` kept, /home unchanged.
- Recovery: `sudo system-rollback` back to the previous state or rename
  `@broken-<date>` back (docs/recovery-design.md 22).

## 6. Destructive pacman failure injection
- Action: `sudo touch /var/lib/pacman/db.lck` then OS menu -> Update.
- Expected: preflight refuses ("pacman lock"), nothing changes.
- Recovery: `sudo rm /var/lib/pacman/db.lck` (only the one created here).

## 7. Power interruption / LUKS / bootloader
- Out of scope for this batch (no change touched them); keep for the
  security audit's own plan.

## Follow-up prompt

```
REPO – Bug Hunt v1 supervised resume. I am at the laptop (docked, Wi-Fi up).
Follow docs/testing/BUGHUNT_V1_SUPERVISED_RESUME.md tests 1-6 in order on
main, one at a time: before each, tell me exactly what to do and what I
will see; after each, check the result over SSH, record it with its test
level in docs/testing/BUGHUNT_V1_STATUS.md, and stop at the first
unexpected result. Ask me only for passwords, LUKS, the boot menu or a
physical action. No architecture refactoring or security hardening.
```
