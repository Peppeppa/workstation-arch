# Security Audit & Hardening v1 - report

2026-10-13/14. Branch `security-v1` from `main` = `208048b`, deployed to the
ThinkPad T440p and then fast-forwarded into `main`. Inventory and threat
model: `docs/security/SECURITY_AUDIT_V1.md`.

## 1. Executive summary

No critical or high-severity vulnerability was found. The privileged
helpers validate strictly (regex/fullmatch, argv lists, no shell
interpolation, atomic state, locks), the network exposure is one key-only
sshd behind a default-drop firewall, sudo always needs the password, and
nothing user-writable is executed by root. Two confirmed weaknesses were
fixed, tested and deployed: **S1** old SUID-root binaries stayed executable
with root rights from every retained snapshot, and **S2** theme validators
accepted a trailing newline that broke generated Lua. Two
**design decisions** with real security impact are left for the user
(S3 passwordless polkit actions in the active session, S4 docker group =
root while Docker runs); the remaining items are low / informational or
need hardware features (Secure Boot, TPM2) out of scope.

## 2. Threat model

See the audit document, section 3. The realistic attackers: a malicious
process running as the desktop user, a malicious imported theme, a LAN /
public Wi-Fi attacker, temporary physical access. The boot chain gives
**no** cryptographic protection against tampering (Secure Boot off, no
TPM2): LUKS protects data at rest only.

## 3. Scope

Sudo/polkit/pkexec helpers (firewall-rules, snapshot-create,
snapshot-restore, system-update(-root), system-rollback, system-snapshot,
snapshot-boot, pre-transaction hook), PAM incl. the P1 override, sshd,
firewall + listening sockets + sysctls, LUKS/boot/ESP/snapshot mounts,
pacman configuration, AUR builds, Flatpak remote, theme import and
compiler, notifications, Quickshell IPC/pkexec use, user state files,
systemd units, secrets in the tree and the whole Git history (313
commits).

## 4. Findings

| ID | Severity | Component | Finding | Status |
|----|----------|-----------|---------|--------|
| S1 | MEDIUM | recovery (/.snapshots mount) | old SUID-root binaries in snapshots executable with root rights (no `nosuid`, directory 0755) | **FIXED** (deployed) |
| S2 | LOW | theme helper | validators used `re.match` with `$`: a trailing newline passed and broke generated Lua (DoS of theme/Neovim/Hyprland config) | **FIXED** (deployed) |
| S3 | MEDIUM | polkit actions firewall.manage, snapshot.create | active session runs them without a password: a malicious user process can open inbound ports or replace/delete the manual recovery snapshots silently | **FIXED** in Hardening v1.1 (firewall changes + snapshot overwrite/delete need the password) |
| S4 | MEDIUM | docker group membership | while Docker runs, any user process gets root without a password (`docker run -v /:/host`) | **FIXED** in Hardening v1.1 (user removed; `sudo docker`; takes full effect after the next login) |
| S5 | LOW | sshd | TCP / agent / stream-local forwarding allowed (only for the key holder) | DEFERRED (SSH change needs approval; low value) |
| S6 | LOW | firewall | one rule set for every network: SSH 22 and LocalSend 53317 open on public Wi-Fi too | ACCEPTED (key-only SSH; LocalSend only while the app runs, asks per transfer) - zone-specific rules would be a feature |
| S7 | INFORMATIONAL | boot chain | Secure Boot off, no TPM2, unencrypted ESP, loader editor enabled: evil-maid tampering possible with physical access | ACCEPTED (needs own SB keys - separate supervised hardware batch) |
| S8 | INFORMATIONAL | LUKS | one keyslot, no header backup documented | OPEN (availability, not confidentiality) |
| S9 | INFORMATIONAL | AUR builds | built as the user, installed by root during a bootstrap: a user-level attacker could swap the package between build and `pacman -U` | ACCEPTED (same trust domain as the user's sudo password prompt) |
| S10 | INFORMATIONAL | P1 polkit override | drift from system-auth is detected by repo-healthcheck (also run by system-update after every update), but a changed pam_unix return-code semantics would not be | ACCEPTED (tests/pam-polkit.sh re-checks the semantics against the installed modules) |
| S11 | INFORMATIONAL | notifications | an image URL other than file:/image: from a local sender is passed to Qt as is | ACCEPTED (only a local same-uid process can send it; it can reach the network anyway) |
| S12 | INFORMATIONAL | kernel | kptr_restrict 0, kexec_load_disabled 0 (Arch defaults) | ACCEPTED |
| - | - | secrets | no credential in the tree or in the Git history (keys, tokens, passwords; matches were variable names, docs and the public github.com host key) | verified |
| - | - | pacman `--noconfirm` (system-update) | defaults: replacements Y, conflicts N (abort), key import Y but an unknown key is still untrusted -> the transaction fails; signatures stay Required | verified, no change |

Verified properties (evidence in section 5): no NOPASSWD; root password
locked, no root SSH keys; only sshd listening; firewall input policy drop on
IPv4+IPv6; sshd key-only; no world-writable or user-owned file in a root
execution path; snapper has no non-root users; theme import runs git with
hooks, symlinks, submodules, credential helpers and non-https protocols
off; notification text is plain text; pkexec helpers take argv lists and
validate every argument; firewall labels never reach the nft script.

## 5. Evidence

- **S1**: `ls -l /.snapshots/48/snapshot/usr/bin/{sudo,pkexec}` = `-rwsr-xr-x`;
  `findmnt /.snapshots` without nosuid; running the snapshot's sudo
  reached the password prompt (effective uid 0). After the fix: mount
  `rw,nosuid,nodev,...`, the same call says "effective uid is not 0 ... nosuid".
- **S2**: a theme.yml with `plugin: "owner/repo\n"` or `"#00172E\n"`
  validated as a correct theme (tests/theme-helper.sh before the fix);
  `'"%s"' % value` puts the newline into a Lua string literal.
- **S3**: `/usr/share/polkit-1/actions/org.workstation.{firewall.manage,
  snapshot.create}.policy` `<allow_active>yes`; `pkexec firewall-rules add
  <label> <port> tcp` + `enable` opens the port (the UI does exactly this).
- **S4**: `id` shows `docker`; Docker's socket is root-equivalent by design.
- **S5/S6**: `sshd -T`, `nft list ruleset` (audit document).

## 6. Fixes implemented

| ID | Change | Commit |
|---|---|---|
| S1 | `/.snapshots` mounted `nosuid,nodev` (roles/recovery mount task, per-item extra options) | `4b31d94` |
| S2 | theme helper validators use `fullmatch` | `b184d69` |

## 7. Tests added

- `tests/recovery-mounts.py`: renders the mount task's own `opts`
  expression for each loop item; fails without S1.
- `tests/theme-helper.sh`: plugin and color with a trailing newline make
  the theme invalid (with a guard that the fixture really changed); fail
  without S2.

## 8. Tests passed

`tests/run.sh` after each change: all checks passed (incl. pam-polkit,
firewall, snapshot-boot, system-update, theme helper, qml-logic). On the
laptop: fstab `findmnt --verify` clean; snapper create/delete of a plain
snapshot on the nosuid mount worked (#49, then its empty directory removed);
`snapshot-boot slot-list` as the user still works; boot entries unchanged.

## 9. Deployment results

Branch deployed: dry run = pacman DB sync, the /.snapshots mount, the theme
helper (changed=3); real run changed=2, second run changed=0. Afterwards:
HEALTHY, SSH over Ethernet and Wi-Fi, normal boot on `@` (no reboot was
needed or done), faillock 0, boot entries #48 #47 #44 #43.

**Incident during the audit (operator error, recovered)**: one inventory
run fed the password and the script over the same stdin; `sudo -S` read
script text -> 2 faillock entries (below the deny=3 threshold). The next
correct sudo authentication cleared them through `pam_faillock authsucc`;
no manual reset. Afterwards every script was copied first and got only the
password on stdin.

## 10. Deferred risky fixes (prepared decisions)

- **S3** options: (a) keep (current, documented convenience); (b)
  `auth_admin_keep` for both actions - one password per 5 minutes for
  firewall changes and manual snapshots; the firewall window then needs a
  non-root way to read its list (rules.json is world-readable; the live
  check needs nft) - a small UI/helper change; cancelling is safe since P1.
  Recommendation: (b) for firewall.manage (network exposure), (a) or (b)
  for snapshot.create.
- **S4** options: remove the user from `docker` and use `sudo docker` (or
  rootless Docker). Recommendation: rootless Docker or sudo if containers
  are rare.
- **S5**: `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`
  (keep TCP forwarding for `ssh -L` to Jupyter) - SSH change, needs an
  approved, rollback-protected deployment.
- **S7**: Secure Boot with own keys (sbctl, signed UKIs + snapshot UKI
  copies; snapshot entries then lose their cmdline override - recovery
  design 22 must change) - separate supervised boot batch.
- **S8**: a second LUKS keyslot (recovery passphrase) and an offline header
  backup - user action.

## 11. Accepted risks

S6, S7 (until a boot batch), S9, S10, S11, S12 - reasons in the table.

## 12. Remaining attack surface

sshd (keys), LocalSend while running, Bluetooth pairing (agent only while
the user pairs), NetworkManager/DHCP, Chromium + web apps, Qt image
decoders for wallpapers/notification images, imported theme data (strictly
parsed), the user session itself (same-uid IPC, Hyprland Lua config,
display-scale.lua - all same trust domain), physical boot chain.

## 13. Commits

`4b31d94` S1, `b184d69` S2, plus the audit/report documentation commit.

## 14. Current system health

Normal boot on `@`, HEALTHY (all checks PASS), faillock 0, SSH over
Ethernet and Wi-Fi, no pending updates, bootstrap idempotent.

## 15. Next steps

1. User decision on S3 and S4 (then a small supervised batch).
2. S8: second LUKS keyslot + header backup (user, offline).
3. A Secure Boot batch (S7) with the recovery design update.
4. Still open from earlier: the hardware test of a permanent restore and
   its resync unit.
