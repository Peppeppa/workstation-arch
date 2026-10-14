#!/usr/bin/env python3
"""Clean install (Release Acceptance v1). Static: nothing on this machine is
read or changed.

1. Base state the laptop had only from its archinstall choices is owned by
   the roles: zram swap (roles/power), the systemd-boot menu timeout
   (roles/recovery).
2. docs/release/CLEAN_INSTALL_PLAN.md - the archinstall checklist - asks for
   exactly what the roles assume: Btrfs @ / @home @log @pkg, LUKS with the
   busybox encrypt hook, systemd-boot + the UKI path of recovery-lib, a
   hostname with host_vars, a wheel user; and it names no disk serial."""
import os, re, subprocess, sys

import yaml

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fails = 0


def ok(name, cond):
    global fails
    if not cond:
        fails += 1
        print("FAIL", name)


def load(path):
    with open(os.path.join(repo, path)) as f:
        return f.read()


# 1. roles
power_d = yaml.safe_load(load("roles/power/defaults/main.yml"))
power_t = yaml.safe_load(load("roles/power/tasks/main.yml"))
ok("power: zram-generator package", "zram-generator" in (power_d.get("power_zram_packages") or []))
ok("power: zram0 with zstd", re.search(r"^\[zram0\]\ncompression-algorithm = zstd$", power_d.get("power_zram_config", ""), re.M) is not None)
zr = [t for t in power_t if (t.get("ansible.builtin.copy") or {}).get("dest") == "/etc/systemd/zram-generator.conf"]
ok("power: deploys /etc/systemd/zram-generator.conf (core, no when:)", len(zr) == 1 and "when" not in zr[0])
rec_d = yaml.safe_load(load("roles/recovery/defaults/main.yml"))
rec_t = yaml.safe_load(load("roles/recovery/tasks/main.yml"))
loader = {t["ansible.builtin.lineinfile"]["regexp"]: t["ansible.builtin.lineinfile"]["line"]
          for t in rec_t if (t.get("ansible.builtin.lineinfile") or {}).get("path") == "/boot/loader/loader.conf"}
ok("recovery: loader.conf default arch-linux.efi", loader.get(r"^default\s") == "default arch-linux.efi")
ok("recovery: loader.conf timeout from recovery_boot_menu_timeout > 0",
   loader.get(r"^timeout\s") == "timeout {{ recovery_boot_menu_timeout }}" and int(rec_d.get("recovery_boot_menu_timeout", 0)) > 0)

# 2. the checklist
plan = load("docs/release/CLEAN_INSTALL_PLAN.md")
rows = {m.group(1).strip(): m.group(2) for m in re.finditer(r"^\| ([^|]+) \| ([^|]+) \|", plan, re.M)}


def row(name, *needles):
    text = rows.get(name, "")
    ok("checklist %s: %s" % (name, ", ".join(needles)), text and all(n in text for n in needles))


row("Disk configuration -> Partitioning", "best-effort default partition layout", "only", "LITEONIT LCS-256M6S", "btrfs",
    "default structure?\" **Yes**", "Use compression")
row("Disk configuration -> Btrfs snapshots", "none")
row("Disk configuration -> Disk encryption", "**LUKS**", "**btrfs** partition only", "no FIDO2/HSM")
row("Swap", "**Yes**", "zstd")
row("Bootloader", "**Systemd-boot**", "Unified kernel images **Enabled**", "Plymouth off")
row("Kernels", "`linux` only")
row("Authentication", "`medvidec`", "**superuser: yes**", "Passwordless sudo: **no**")
row("Profile", "**Minimal**")
row("Network configuration", "Network Manager (default backend)")
row("Additional packages", "git", "ansible")
host = re.search(r"\| Hostname \| `([^`]+)` \|", plan)
ok("checklist hostname has host_vars", host is not None and os.path.exists(os.path.join(repo, "host_vars", host.group(1) + ".yml")))
ok("checklist: the Fedora disk only as never select",
   re.search(r"MicroFrom[^\n]*never select", plan) is not None and "MicroFrom" not in rows.get("Disk configuration -> Partitioning", ""))
# what archinstall 4.5 produces = what roles/recovery checks (its layout guard)
guard = next(t for t in rec_t if "ansible.builtin.assert" in t)["ansible.builtin.assert"]["that"]
ok("recovery guard still wants subvol=/@ + rootflags=subvol=@ + vfat /boot",
   any("'subvol=/@'" in c for c in guard) and any("rootflags=subvol=@" in c for c in guard) and any("'vfat'" in c for c in guard))
ok("checklist check: cmdline with rootflags=subvol=@ and cryptdevice=PARTUUID",
   re.search(r"cmdline\s+# cryptdevice=PARTUUID=\S+ root=/dev/mapper/root .*rootflags=subvol=@ ", plan) is not None)
ok("checklist check: busybox encrypt hook after keymap",
   re.search(r"keymap consolefont block encrypt filesystems", plan) is not None)
ok("checklist check: fstab subvolumes @ @home @log @pkg, /boot vfat",
   all(s in plan for s in ("subvol=/@,", "/@home", "/@log", "/@pkg", "/boot vfat")))
main_uki = re.search(r"^MAIN_UKI=(\S+)", load("roles/recovery/templates/recovery-lib.sh.j2"), re.M).group(1)
ok("checklist: UKI = recovery-lib MAIN_UKI (%s)" % main_uki, main_uki in plan and os.path.basename(main_uki) + " only" in plan)
ok("checklist: fallback UKI removed (only arch-linux.efi is rebuilt by a restore)",
   "PRESETS=('default')" in plan and "rm -f /boot/EFI/Linux/arch-linux-fallback.efi" in plan)
ok("checklist: no NOPASSWD", "NOPASSWD" not in plan)

# 3. the CLI tools docs/system_architecture.md promises ("Die grafische Shell ist
# Convenience") come from a package archinstall's base or a role installs - the
# clean install had no bluetoothctl (Clean Install Acceptance v1).
arch = load("docs/system_architecture.md")
block = re.search(r"Beispiele:\n\n```text\n([^`]*)```\n\nsollen weiterhin funktionieren", arch)
tools = block.group(1).split() if block else []
provider = {"systemctl": "base", "journalctl": "base", "ip": "base", "nmcli": "networkmanager",
            "wpctl": "wireplumber", "bluetoothctl": "bluez-utils"}
pkgs = {"base"}
for f in __import__("glob").glob(os.path.join(repo, "roles/*/defaults/main.yml")):
    for k, v in (yaml.safe_load(open(f)) or {}).items():
        if k.endswith("_packages") and isinstance(v, list):
            pkgs |= {p for p in v if isinstance(p, str)}
ok("system_architecture CLI list found", len(tools) >= 5)
for t in tools:
    ok("CLI %s: provided by an installed package (%s)" % (t, provider.get(t, "unknown - add it to this map")),
       provider.get(t) in pkgs)

# no disk serials in tracked files (public repository)
# (a column list for `lsblk -o` in an instruction names no serial)
hits = subprocess.run(["git", "-C", repo, "grep", "-nE", r"ata-[A-Za-z0-9]+_[A-Za-z0-9_-]+_[A-Z0-9]{8,}|lsblk[^\n]*SERIAL",
                       "--", ":!tests/clean-install.py"],
                      capture_output=True, text=True).stdout.splitlines()
tracked = sorted({h.split(":", 1)[0] for h in hits
                  if not re.search(r"lsblk -o [A-Z,]*SERIAL[A-Z,]*", h) or re.search(r"ata-[A-Za-z0-9]+_", h)})
ok("no disk serial / by-id disk name in tracked files: %s" % tracked, not tracked)

print("clean-install: all checks passed" if not fails else "clean-install: %d FAILED" % fails)
sys.exit(1 if fails else 0)
