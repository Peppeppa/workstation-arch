#!/usr/bin/env python3
"""roles/recovery snapshot-boot against a fake root (run by tests/run.sh).

No real ESP, snapper or UKI: SNAPSHOT_BOOT_TEST_ROOT points every path into a
temporary directory, and objcopy / lsinitcpio / snapper are stubs on PATH. A
fake "UKI" is a text file whose lines are its sections (UNAME=..., HOOK=yes).

  - capture: stores the main UKI per kernel, refuses one without the hook
  - selection: newest 2 update (auto=pre-transaction) + newest 2 manual
    (important=yes) that can boot; class from userdata, not the description
  - not offered (with a reason): no support marker, writable, no UKI for its
    kernel, two kernels, UKI without the hook, no rootflags=subvol=@
  - entry text: snapshot root, resume dropped, noresume, workstation.snapshot=<n>
  - deleted snapshots lose their entry; unused UKI copies go, the main kernel's stays
  - Secure Boot on: no entries; snapshot mode: nothing changes
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TOOL = os.path.join(ROOT, "roles/recovery/files/snapshot-boot")
fails = 0


def eq(what, got, want):
    global fails
    if got != want:
        fails += 1
        print("FAIL %s: %r != %r" % (what, got, want))


T = tempfile.mkdtemp()
R = os.path.join(T, "root")
BIN = os.path.join(T, "bin")
os.makedirs(BIN)


def w(path, text, mode=None):
    p = os.path.join(R, path.lstrip("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)
    if mode:
        os.chmod(p, mode)
    return p


def stub(name, body):
    p = os.path.join(BIN, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(p, 0o755)


# objcopy -O binary --only-section=.<name> <in> <out>: the fake UKI's line NAME=value
stub("objcopy", 'sec=""; for a; do case $a in --only-section=.*) sec=${a#--only-section=.};; esac; done\n'
                'eval "in=\\${$(($#-1))}"; eval "out=\\${$#}"\n'
                'case $sec in uname) sed -n "s/^UNAME=//p" "$in" | tr -d "\\n" > "$out";;\n'
                '  initrd) grep "^HOOK=" "$in" > "$out" || : > "$out";; *) : > "$out";; esac')
stub("lsinitcpio", 'grep -q "^HOOK=yes" "$2" && echo "hooks/workstation-snapshot-overlay"; echo "init"')
stub("snapper", 'cat "%s/snapper.json"' % T)
env = dict(os.environ, SNAPSHOT_BOOT_TEST_ROOT=R, PATH=BIN + ":" + os.environ["PATH"])

CMDLINE = "cryptdevice=PARTUUID=x:root root=/dev/mapper/root rootflags=subvol=@ rw resume=UUID=abc resume_offset=1 zswap.enabled=0\n"


def uki(path, uname, hook=True):
    return w(path, "UNAME=%s\nHOOK=%s\nKERNEL\n" % (uname, "yes" if hook else "no"))


def snap(n, kernels=("7.2.9",), support=2, writable=False, cmdline=CMDLINE):
    base = "/.snapshots/%d/snapshot" % n
    for k in kernels:
        w(base + "/usr/lib/modules/%s/vmlinuz" % k, "k")
    w(base + "/etc/kernel/cmdline", cmdline)
    if support:
        w(base + "/usr/local/lib/workstation/snapshot-boot-support", "# marker\n%d\n" % support)
    if writable:
        w(base + ".rw", "")


def snapper(entries):
    rows = [{"number": 0, "date": "", "description": "current", "userdata": None}]
    for n, cls, date, desc in entries:
        ud = {"update": {"auto": "pre-transaction"}, "manual": {"important": "yes"},
              "baseline": {"baseline": "yes"}, "update-slot": {"auto": "pre-transaction", "slot": "before-update"}}[cls]
        rows.append({"number": n, "date": date, "description": desc, "userdata": ud})
    with open(os.path.join(T, "snapper.json"), "w") as f:
        json.dump({"root": rows}, f)


def tool(*args):
    r = subprocess.run([sys.executable, TOOL] + list(args), env=env, capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout + r.stderr


def entries():
    d = os.path.join(R, "boot/loader/entries")
    return sorted(f for f in os.listdir(d) if f.startswith("workstation-snapshot-")) if os.path.isdir(d) else []


def state():
    return json.load(open(os.path.join(R, "var/lib/workstation/snapshot-boot.json")))


try:
    w("/proc/cmdline", "root=/dev/mapper/root rootflags=subvol=@\n")
    w("/proc/stat", "cpu 0\nbtime 1\n")
    os.makedirs(os.path.join(R, "boot/loader/entries"))
    w("/boot/loader/entries/workstation-recovery-before-update.conf", "title slot\n")   # not ours: never touched

    # --- capture
    uki("/boot/EFI/Linux/arch-linux.efi", "7.2.9", hook=False)
    rc, out = tool("capture")
    eq("capture refuses a main UKI without the hook", (rc, "no workstation-snapshot-overlay hook" in out), (1, True))
    uki("/boot/EFI/Linux/arch-linux.efi", "7.2.9")
    rc, out = tool("capture")
    eq("capture stores the main UKI per kernel", (rc, os.path.isfile(os.path.join(R, "boot/EFI/workstation/snapshots/7.2.9.efi"))), (0, True))
    rc, out = tool("capture")
    eq("capture again: already stored", "already stored" in out, True)
    # a second kernel's UKI from an earlier capture
    uki("/boot/EFI/workstation/snapshots/7.1.0.efi", "7.1.0")
    uki("/boot/EFI/workstation/snapshots/6.9.0.efi", "6.9.0")

    # --- snapshots
    snap(21, kernels=("7.1.0",))                 # update, older kernel - its UKI copy exists
    snap(23, support=0)                          # manual, before support
    snap(24, support=1)                          # manual, support version 1 (restore broken in a snapshot boot)
    snap(25)                                     # update
    snap(27)                                     # update
    snap(28)                                     # manual
    snap(29, kernels=("7.0.0",))                 # manual, kernel without UKI
    snap(30, kernels=("7.2.9", "7.3.0"))         # manual, two kernels
    snap(31, writable=True)                      # update, writable
    snap(32, cmdline="root=/dev/sda2 rw\n")      # manual, no subvol=@
    snap(13)                                     # baseline: no class
    snapper([(13, "baseline", "2026-10-08 15:40:13", "baseline"),
             (21, "update", "2026-10-01 09:00:00", "pacman: linux"),
             (23, "manual", "2026-10-10 13:19:15", "Test Updater"),
             (24, "manual", "2026-10-10 13:20:00", "support v1"),
             (25, "update", "2026-10-10 13:39:59", "pacman: 7 packages"),
             (27, "update-slot", "2026-10-10 17:04:11", "system-update (repo 3276cfd)"),
             (28, "manual", "2026-10-10 17:42:50", "test (repo b655739)\twith a tab"),
             (29, "manual", "2026-10-10 18:00:00", "old kernel"),
             (30, "manual", "2026-10-10 18:10:00", "two kernels"),
             (31, "update", "2026-10-10 18:20:00", "pacman: writable"),
             (32, "manual", "2026-10-10 18:30:00", "no subvol")])
    rc, out = tool("sync")
    eq("sync rc", rc, 0)
    eq("entries: newest 2 bootable update (25, 21 - 27 is a recovery slot) + manual (28 only bootable one)", entries(),
       ["workstation-snapshot-21.conf", "workstation-snapshot-25.conf", "workstation-snapshot-28.conf"])
    st = state()
    reasons = {s["number"]: s["reason"] for s in st["skipped"]}
    want = {27: "already in the boot menu as recovery slot before-update", 23: "taken before snapshot boot support",
            24: "snapshot boot support version 1 inside, 2 needed", 29: "no stored UKI for its kernel 7.0.0",
            30: "needs exactly one kernel", 31: "snapshot is writable", 32: "its /etc/kernel/cmdline has no rootflags"}
    eq("skip reasons", {n: reasons.get(n, "").startswith(t) for n, t in want.items()}, {n: True for n in want})
    e28 = open(os.path.join(R, "boot/loader/entries/workstation-snapshot-28.conf")).read()
    opts = [l for l in e28.splitlines() if l.startswith("options")][0].split()[1:]
    eq("entry: snapshot root", "rootflags=subvol=@snapshots/28/snapshot" in opts and "rootflags=subvol=@" not in opts, True)
    eq("entry: no resume, noresume, marker, remount-fs masked",
       [any(o.startswith("resume") for o in opts), "noresume" in opts, "workstation.snapshot=28" in opts,
        "systemd.mask=systemd-remount-fs.service" in opts], [False, True, True, True])
    eq("entry: title with date + cleaned description", [l for l in e28.splitlines() if l.startswith("title")][0],
       "title    Snapshot 2026-10-10 17:42 - test (repo b655739) with a tab")
    eq("entry: uki path + sort key", [l.split(None, 1)[1] for l in e28.splitlines() if l.startswith(("uki", "sort-key"))],
       ["zz-workstation-snapshot-9999971", "/EFI/workstation/snapshots/7.2.9.efi"])
    e25 = open(os.path.join(R, "boot/loader/entries/workstation-snapshot-25.conf")).read()
    eq("update entry title", e25.splitlines()[1], "title    Snapshot (before update) 2026-10-10 13:39 - pacman: 7 packages")
    e21 = open(os.path.join(R, "boot/loader/entries/workstation-snapshot-21.conf")).read()
    eq("older kernel: its own UKI copy", "uki      /EFI/workstation/snapshots/7.1.0.efi" in e21, True)
    eq("state readable by everyone", oct(stat.S_IMODE(os.stat(os.path.join(R, "var/lib/workstation/snapshot-boot.json")).st_mode)), "0o644")
    eq("entry file root-only", oct(stat.S_IMODE(os.stat(os.path.join(R, "boot/loader/entries/workstation-snapshot-28.conf")).st_mode)), "0o600")
    eq("unused UKI copies removed (6.9.0), used + main kept", sorted(os.listdir(os.path.join(R, "boot/EFI/workstation/snapshots"))), ["7.1.0.efi", "7.2.9.efi"])
    eq("slot entry not touched", os.path.isfile(os.path.join(R, "boot/loader/entries/workstation-recovery-before-update.conf")), True)

    # --- deletion: 21 goes -> its entry and its kernel's UKI copy go
    snapper([(25, "update", "2026-10-10 13:39:59", "pacman: 7 packages"),
             (28, "manual", "2026-10-10 17:42:50", "test")])
    shutil.rmtree(os.path.join(R, ".snapshots/21"))
    rc, out = tool("sync")
    eq("after deletion", entries(), ["workstation-snapshot-25.conf", "workstation-snapshot-28.conf"])
    eq("UKI copy of the deleted snapshot's kernel removed", sorted(os.listdir(os.path.join(R, "boot/EFI/workstation/snapshots"))), ["7.2.9.efi"])

    # --- a stored UKI that lost the hook (e.g. copied by hand) is not offered
    uki("/boot/EFI/workstation/snapshots/7.2.9.efi", "7.2.9", hook=False)
    uki("/boot/EFI/Linux/arch-linux.efi", "7.2.9")     # main has it: capture replaces the copy
    rc, out = tool("sync")
    eq("copy without hook replaced from main", entries(), ["workstation-snapshot-25.conf", "workstation-snapshot-28.conf"])

    # --- Secure Boot on: no entries at all, error in the state
    w("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c", "\x06\x00\x00\x00\x01")
    rc, out = tool("sync")
    eq("secure boot: no entries, error", (rc, entries(), "Secure Boot" in " ".join(state()["errors"])), (1, [], True))
    os.unlink(os.path.join(R, "sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"))
    tool("sync")

    # --- snapshot mode: sync changes nothing
    w("/proc/cmdline", "rootflags=subvol=@snapshots/28/snapshot workstation.snapshot=28\n")
    snapper([])
    rc, out = tool("sync")
    eq("snapshot mode: entries untouched", (rc, entries()), (0, ["workstation-snapshot-25.conf", "workstation-snapshot-28.conf"]))
    w("/proc/cmdline", "rootflags=subvol=@\n")

    # --- snapper failing: old entries kept, error recorded
    stub("snapper", "echo boom >&2; exit 1")
    rc, out = tool("sync")
    eq("snapper failure: entries kept, ok=false", (rc, entries(), state()["ok"]), (1, ["workstation-snapshot-25.conf", "workstation-snapshot-28.conf"], False))

    rc, out = tool("status")
    eq("status names the error", "snapper list failed" in out, True)
    rc, out = tool("bogus")
    eq("usage", rc, 2)
finally:
    shutil.rmtree(T)

print("snapshot-boot: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
