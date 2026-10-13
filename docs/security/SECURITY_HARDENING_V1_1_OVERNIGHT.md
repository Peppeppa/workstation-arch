# Security Hardening v1.1 - overnight progress log

Branch `hardening-v1.1` from `main` = `ac9ca86`. ThinkPad: normal boot on
`@`, HEALTHY, faillock 0, session unlocked, Docker inactive. Rules for the
night: no reboot/suspend/logout, no sshd/NetworkManager/firewall restart, no
real snapshot deleted, no faillock reset. Newest entry on top.

## Privilege matrix (investigation, before any change)

| Operation | Entry points | Before | Target |
|---|---|---|---|
| Firewall status (list incl. live kernel state) | Firewall window -> `pkexec firewall-rules list` | polkit `firewall.manage`, active session **yes** | own action `firewall.status` on a fixed-argument wrapper `firewall-status` (`list` only), active session **yes** |
| Firewall add/edit/enable/disable/remove/reset | Firewall window -> `pkexec firewall-rules <verb>`; CLI `sudo firewall-rules` | `firewall.manage` active **yes** | `firewall.manage` active **auth_admin_keep** (polkit's own ~5 min retention); sudo unchanged (password) |
| Firewall restore at boot | `workstation-firewall.service` (root) | root | unchanged |
| Manual snapshot create (empty slot) | Create Snapshot dialog -> `pkexec snapshot-create set <slot> <label>`; CLI `sudo system-snapshot --slot` | `snapshot.create` active **yes** | unchanged (yes) - `snapshot-create` only creates; `snapshot-boot slot-set` refuses an occupied slot without `--replace` |
| Manual snapshot overwrite (deletes the old one) | dialog -> `pkexec snapshot-create set <slot> <label> <old>` | `snapshot.create` **yes** | new helper `snapshot-delete <slot> <number> <label>`, action `snapshot.delete` active **auth_admin_keep** |
| Manual snapshot delete | dialog -> `pkexec snapshot-create delete <slot> <n>` | `snapshot.create` **yes** | `snapshot-delete <slot> <number>`, `snapshot.delete` **auth_admin_keep** |
| Snapshot list / metadata | `snapshot-boot slot-list --json`, `status` (user) | no privilege | unchanged |
| Permanent restore | snapshot mode -> `pkexec snapshot-restore` | auth_admin always | unchanged |
| Automatic snapshots + retention | pacman hook (root, inside pacman), system-update (sudo), `snapshot-boot prune`, snapper-cleanup.timer (manual slots are created with no cleanup algorithm) | root | unchanged |
| snapper D-Bus | snapperd | ALLOW_USERS/GROUPS empty | unchanged |
| Direct helper calls | firewall-rules / snapshot-create / snapshot-delete / snapshot-boot without root | refuse (euid check; nft/snapper need root) | unchanged; plus `snapshot-create` refuses delete/replace even as root |
| Docker daemon access | `docker` CLI over /run/docker.sock | user in group **docker** (roles/development) = root while Docker runs | user removed from the group by the role (source of truth); `sudo docker`; nothing passwordless instead |

Alternative paths checked: sudoers = `(ALL) ALL` with password (no
NOPASSWD); polkit rules.d empty; Quickshell IPC (`firewall`, `snapshot`)
only opens windows - every mutation still goes through pkexec; the private
repository adds no group (only shell aliases `d`, `dc`, `lzd` that will need
sudo - the user's dotfiles, not changed).

## Log

### 00:45 - implemented, tested, deployed (branch hardening-v1.1)

- commits `b08e895` S3-A firewall, `2b8f2b3` S3-B snapshots, `0342689` S4
  docker, `48b1942` privilege-matrix test + docs.
- tests: tests/run.sh all passed (new: tests/privileges.py; extended:
  tests/firewall.sh, tests/system-update.sh, tests/qml-logic.qml,
  tests/healthcheck-polkit-pam.py); each new check failed before its change.
- dry run: pacman DB sync, the two helpers, four policies, Quickshell
  (SnapshotDialog, FirewallModel/Window, shell.qml), repo-healthcheck; no
  ruleset/unit/sshd/PAM/boot change, no firewall reload handler.
- deploy: run 1 changed=10, run 2 changed=0; Quickshell reloaded in place
  (pid 1502). Live state vs. before: nft ruleset hash, rules.json, snapper
  list, boot entries, Docker data + units identical; `docker` group now
  empty; new firewall-status / snapshot-delete + their actions present.
