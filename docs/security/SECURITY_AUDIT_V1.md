# Security Audit v1 - inventory and threat model

2026-10-13/14, branch `security-v1` from `main` = `208048b`; target ThinkPad
T440p (`laptop`), normal boot on `@`, HEALTHY. All inventory read-only
(one sudo per script, password on stdin only). Results:
`SECURITY_AUDIT_V1_REPORT.md`.

## 1. Inventory (as found on the laptop)

| Area | State |
|---|---|
| Accounts | root (password locked `L`, no `/root/.ssh` keys), medvidec (1000); groups wheel, video, docker, vboxusers |
| sudo | `/etc/sudoers.d/00_medvidec`: `(ALL) ALL` with password; `secure_path`; no NOPASSWD anywhere |
| polkit | no local rules (`/etc/polkit-1/rules.d` empty); repo actions: `org.workstation.firewall.manage` and `.snapshot.create` = **allow_active yes** (any/inactive = auth_admin), `.snapshot.restore` = auth_admin everywhere; each bound to one helper via `exec.path` |
| PAM | pambase stack unmodified (`pacman -Qkk`), faillock defaults (deny 3 / 15 min, unlock 600 s); `/etc/pam.d/polkit-1` = P1 override |
| SSH | sshd 22 on 0.0.0.0 + ::; key-only (Password/KbdInteractive no), PermitRootLogin prohibit-password, MaxAuthTries 6, X11 no, Tunnel no; TCP/agent/streamlocal forwarding allowed; 1 authorized key |
| Listening | only sshd (tcp 22, v4+v6) |
| Firewall | table `inet workstation`: input policy drop; lo, established, ICMP/ICMPv6 essentials, docker0/br-* accepted; repo_rules = DHCP, DHCPv6 (link-local source), LocalSend UDP (multicast only) + TCP 53317, SSH 22 - on every interface; forward policy accept (ip_forward 0 unless Docker runs) |
| Kernel | ptrace_scope 1, protected_* 1, dmesg_restrict 1, unprivileged_bpf_disabled 2, syncookies, no source routing, ICMP redirects off (repo); kptr_restrict 0, kexec_load_disabled 0, sysrq 16, unprivileged userns on (Arch defaults) |
| SUID | Arch defaults + chromium/electron sandboxes, VirtualBox; none of our own |
| Root-owned code | /usr/local/{bin,lib/workstation,libexec/workstation} root:root 0755/0644; /var/lib/workstation root 0644; nothing world-writable, nothing user-owned executed by root |
| systemd | enabled: NM, sshd, bluetooth, power-profiles, timesyncd, workstation-firewall, snapshot-boot-resync (conditional), snapper-cleanup.timer; docker disabled (socket absent); no avahi, cups, resolved |
| Packages | SigLevel Required/DatabaseOptional (default), LocalFileSigLevel Optional (default); foreign: networkmanager-fortisslvpn + yay (pinned AUR commits, makepkg as user), claude-code (user-installed); pacman hook: pre-transaction snapshot (root, AbortOnFail) |
| LUKS | LUKS2, aes-xts-plain64, argon2id (1 GiB, t=35), 1 keyslot, no token; `encrypt` hook |
| Boot | systemd-boot, UKI, **Secure Boot off, no TPM2**, ESP vfat fmask 0177 / dmask 0077; loader editor at its default (enabled); snapshot entries via loader `options` (works only with SB off - documented) |
| Snapshots | snapper `root`: ALLOW_USERS/GROUPS empty; `/.snapshots` 0755, mounted **without nosuid** (finding S1) |
| User state | ~/.config/workstation, ~/.local/{bin,libexec,share}/workstation: user-owned, 0644/0755 |

## 2. Trust boundaries

1. user -> root: sudo (password), pkexec + polkit (three actions), pacman
   hook (inside root transactions), systemd units triggered by snapper.
2. network -> host: sshd (keys), firewall-opened ports (LocalSend when the
   app runs), DHCP clients, NetworkManager, Bluetooth (bluetoothd, pairing
   only through the user's agent).
3. foreign data -> user session: imported theme repositories (git over
   https), notifications, wallpapers/images, captive portal pages, cloned
   AUR build trees.
4. physical -> boot chain: firmware, unencrypted ESP, LUKS prompt.
5. public repo -> private repo: phase 2 handover only (Bitwarden SSH agent).

## 3. Attacker models

| Model | Realistic here? | What the design can do |
|---|---|---|
| Malicious process as the desktop user | yes (browser/app compromise) | it already owns the session (same uid: IPC, files, Hyprland Lua config); must not gain root or weaken network exposure without a password - see S3/S4 |
| Unprivileged other local user | no other user exists | - |
| Malicious theme / imported data | yes (user imports repos) | parsers must not execute or break config - see S2 |
| LAN / public Wi-Fi attacker | yes (campus, cafes) | only sshd (keys) + LocalSend while running |
| Compromised package / mirror | low (signed repos) | pacman signatures; AUR builds pinned by commit + PKGBUILD checksums |
| Temporary physical access | yes (laptop) | LUKS protects data at rest; **no** protection against boot-chain tampering (evil maid) without Secure Boot/TPM - hardware/firmware work, out of scope |
| Administrative error | yes | snapshots, recovery boot, healthcheck, idempotent provisioning |

## 4. Out of scope / not mitigable here

Evil-maid attacks on the unencrypted ESP / UKI (needs Secure Boot with own
keys, optionally TPM2 - the T440p has no TPM2 support in systemd's view),
firmware, DMA attacks, cold boot, compromise of the Arch signing
infrastructure, browser-internal security.
