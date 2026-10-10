#!/usr/bin/env python3
"""roles/recovery snapshot-boot against a fake root (run by tests/run.sh).

No real ESP, snapper or UKI: SNAPSHOT_BOOT_TEST_ROOT points every path into a
temporary directory; objcopy / lsinitcpio are stubs, snapper is a stateful
stub (list/create/modify/delete, info.xml + snapshot tree per snapshot).
A fake "UKI" is a text file whose lines are its sections (UNAME=, HOOK=yes).

  capture       stores the main UKI per kernel, refuses one without the hook
  menu          2 update (upgrade=yes / update=) + the 3 manual slots, only
                bootable ones, reasons for the others, entry text
  retention     prune: newest 2 update (+ the newest bootable one if those
                cannot boot), newest 2 other; never slots/baseline/legacy slots
  slots         create into an empty slot, overwrite only with the confirmed
                number, failures while creating / checking / assigning leave
                the slot as it was, sync failure keeps the slot, delete with
                the confirmed number, reuse, duplicates, snapshot mode refused
  UKI dedup     shared copies stay while any entry uses them
  rollback      state file gone -> a sync rebuilds the same menu
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
CMDLINE = "cryptdevice=PARTUUID=x:root root=/dev/mapper/root rootflags=subvol=@ rw resume=UUID=abc resume_offset=1 zswap.enabled=0\n"


def w(path, text, mode=None):
    p = os.path.join(R, path.lstrip("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)
    if mode:
        os.chmod(p, mode)
    return p


def stub(name, body, lang="sh"):
    p = os.path.join(BIN, name)
    with open(p, "w") as f:
        f.write(("#!/bin/sh\n" if lang == "sh" else "#!/usr/bin/env python3\n") + body + "\n")
    os.chmod(p, 0o755)


# objcopy -O binary --only-section=.<name> <in> <out>: the fake UKI's line NAME=value
stub("objcopy", 'sec=""; for a; do case $a in --only-section=.*) sec=${a#--only-section=.};; esac; done\n'
                'eval "in=\\${$(($#-1))}"; eval "out=\\${$#}"\n'
                'case $sec in uname) sed -n "s/^UNAME=//p" "$in" | tr -d "\\n" > "$out";;\n'
                '  initrd) grep "^HOOK=" "$in" > "$out" || : > "$out";; *) : > "$out";; esac')
stub("lsinitcpio", 'grep -q "^HOOK=yes" "$2" && echo "hooks/workstation-snapshot-overlay"; echo "init"')

# The stateful snapper: state in $T/snapper.json, snapshots under $R/.snapshots.
# "<what>-fails" files in $T inject failures; $T/kernel and $T/support set
# what the next created snapshot contains.
stub("snapper", r'''
import json, os, shutil, sys
T, R = %r, %r
st = os.path.join(T, "snapper.json")
d = json.load(open(st)) if os.path.exists(st) else {"next": 40, "snaps": []}
a = sys.argv[1:]
log = open(os.path.join(T, "log"), "a")
def save(): json.dump(d, open(st, "w"))
def fail(what):
    if os.path.exists(os.path.join(T, what + "-fails")):
        print("snapper: injected %%s failure" %% what, file=sys.stderr); sys.exit(1)
def xml(n, date, desc, cleanup, ud):
    uds = "".join("<userdata><key>%%s</key><value>%%s</value></userdata>" %% kv for kv in (ud or {}).items())
    open(os.path.join(R, ".snapshots", str(n), "info.xml"), "w").write(
        "<snapshot><type>single</type><num>%%d</num><date>%%s</date><description>%%s</description><cleanup>%%s</cleanup>%%s</snapshot>"
        %% (n, date, desc, cleanup, uds))
def make(n, desc, ud, cleanup, kernel, support):
    snap = os.path.join(R, ".snapshots", str(n), "snapshot")
    os.makedirs(os.path.join(snap, "usr/lib/modules", kernel), exist_ok=True)
    open(os.path.join(snap, "usr/lib/modules", kernel, "vmlinuz"), "w").write("k")
    os.makedirs(os.path.join(snap, "etc/kernel"), exist_ok=True)
    open(os.path.join(snap, "etc/kernel/cmdline"), "w").write(%r)
    if support:
        os.makedirs(os.path.join(snap, "usr/local/lib/workstation"), exist_ok=True)
        open(os.path.join(snap, "usr/local/lib/workstation/snapshot-boot-support"), "w").write("# m\n%%d\n" %% support)
    date = "2026-10-10 10:%%02d:00" %% (n %% 60)
    xml(n, date, desc, cleanup, ud)
    d["snaps"].append({"number": n, "date": date, "description": desc, "userdata": ud or None, "cleanup": cleanup})
def opt(name, default=None):
    return a[a.index(name) + 1] if name in a else default
def parse_ud(s):
    return dict(kv.split("=", 1) for kv in s.split(",") if kv)
if "list" in a:
    fail("list")
    print(json.dumps({"root": [{"number": 0, "date": "", "description": "current", "userdata": None}]
                              + sorted(d["snaps"], key=lambda s: s["number"])}))
elif "create" in a:
    fail("create")
    n = d["next"]; d["next"] += 1
    kf, sf = os.path.join(T, "kernel"), os.path.join(T, "support")
    kernel = open(kf).read().strip() if os.path.exists(kf) else "7.2.9"
    support = int(open(sf).read()) if os.path.exists(sf) else 2
    make(n, opt("--description", ""), parse_ud(opt("--userdata", "")), opt("--cleanup-algorithm", "number"), kernel, support)
    log.write("create %%d cleanup=%%r %%s\n" %% (n, opt("--cleanup-algorithm"), opt("--userdata")))
    save(); print(n)
elif "modify" in a:
    fail("modify")
    n = int(a[-1]); new = parse_ud(opt("--userdata", ""))
    for s in d["snaps"]:
        if s["number"] == n:
            ud = s["userdata"] or {}
            for k, v in new.items():
                if v == "":
                    ud.pop(k, None)
                else:
                    ud[k] = v
            s["userdata"] = ud or None
            xml(n, s["date"], s["description"], s["cleanup"], ud)
    log.write("modify %%d %%s\n" %% (n, opt("--userdata"))); save()
elif "delete" in a:
    fail("delete")
    nums = [int(x) for x in a[a.index("delete") + 1:]]
    d["snaps"] = [s for s in d["snaps"] if s["number"] not in nums]
    for n in nums:
        shutil.rmtree(os.path.join(R, ".snapshots", str(n)), ignore_errors=True)
    log.write("delete %%s\n" %% " ".join(map(str, nums))); save()
''' % (T, R, CMDLINE), lang="py")

env = dict(os.environ, SNAPSHOT_BOOT_TEST_ROOT=R, PATH=BIN + ":" + os.environ["PATH"], TZ="UTC")


def uki(path, uname, hook=True):
    return w(path, "UNAME=%s\nHOOK=%s\nKERNEL\n" % (uname, "yes" if hook else "no"))


def tool(*args):
    r = subprocess.run([sys.executable, TOOL] + list(args), env=env, capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout, r.stderr


def jtool(*args):
    rc, out, err = tool(*args)
    try:
        return rc, json.loads(out.strip().splitlines()[-1]), err
    except (ValueError, IndexError):
        return rc, None, err


def snapper_create(ud, desc="x", cleanup=""):
    r = subprocess.run(["snapper", "-c", "root", "create", "--type", "single", "--print-number", "--cleanup-algorithm", cleanup,
                        "--description", desc, "--userdata", ud], env=env, capture_output=True, text=True)
    return int(r.stdout.strip())


def snaps():
    return {s["number"]: s for s in json.load(open(os.path.join(T, "snapper.json")))["snaps"]}


def entries():
    d = os.path.join(R, "boot/loader/entries")
    return sorted(f for f in os.listdir(d) if f.startswith("workstation-snapshot-")) if os.path.isdir(d) else []


def entry(n):
    return open(os.path.join(R, "boot/loader/entries/workstation-snapshot-%d.conf" % n)).read()


def slots():
    rc, d, err = jtool("slot-list", "--json")
    return {r["slot"]: (None if r["empty"] else r["number"]) for r in d["slots"]}


def state():
    return json.load(open(os.path.join(R, "var/lib/workstation/snapshot-boot.json")))


def flag(name, on=True):
    p = os.path.join(T, name + "-fails")
    if on:
        open(p, "w").close()
    elif os.path.exists(p):
        os.unlink(p)


def kernel(k):
    p = os.path.join(T, "kernel")
    if k:
        open(p, "w").write(k)
    elif os.path.exists(p):
        os.unlink(p)


def ukis():
    return sorted(os.listdir(os.path.join(R, "boot/EFI/workstation/snapshots")))


try:
    w("/proc/cmdline", "root=/dev/mapper/root rootflags=subvol=@\n")
    w("/proc/stat", "cpu 0\nbtime 1\n")
    os.makedirs(os.path.join(R, "boot/loader/entries"))
    w("/boot/loader/entries/workstation-recovery-before-update.conf", "title legacy slot\n")   # never ours

    # ---- capture
    uki("/boot/EFI/Linux/arch-linux.efi", "7.2.9", hook=False)
    rc, out, err = tool("capture")
    eq("capture refuses a main UKI without the hook", (rc, "no workstation-snapshot-overlay hook" in err), (1, True))
    uki("/boot/EFI/Linux/arch-linux.efi", "7.2.9")
    rc, out, err = tool("capture")
    eq("capture stores the main UKI per kernel", (rc, ukis()), (0, ["7.2.9.efi"]))

    # ---- untouchables
    base = snapper_create("baseline=yes", "baseline")
    legacy = snapper_create("auto=pre-transaction,slot=before-update,update=1", "system-update (legacy slot)")
    old_manual = snapper_create("important=yes", "unslotted manual", cleanup="number")

    # ---- retention: the third update snapshot removes the oldest; others: 2; untouchables stay
    u1 = snapper_create("auto=pre-transaction,upgrade=yes", "pacman: 10 packages")
    o1 = snapper_create("auto=pre-transaction", "pacman: cowsay")
    u2 = snapper_create("auto=pre-transaction,update=1791644651", "system-update (repo x)")
    o2 = snapper_create("auto=pre-transaction", "pacman: hello")
    tool("prune")
    eq("prune: 2 update + 2 other -> nothing", sorted(snaps()), sorted([base, legacy, old_manual, u1, o1, u2, o2]))
    u3 = snapper_create("auto=pre-transaction,upgrade=yes", "pacman: 3 packages")
    o3 = snapper_create("auto=pre-transaction", "pacman: vim")
    rc, out, err = tool("prune")
    eq("prune: third update removes the oldest update, third other the oldest other", (rc, sorted(snaps())),
       (0, sorted([base, legacy, old_manual, u2, u3, o2, o3])))
    # the newest 2 update snapshots cannot boot (kernel without UKI): the last bootable one stays
    kernel("6.0.0")
    u4 = snapper_create("auto=pre-transaction,upgrade=yes", "pacman: broken kernel 1")
    u5 = snapper_create("auto=pre-transaction,upgrade=yes", "pacman: broken kernel 2")
    kernel(None)
    tool("prune")
    eq("prune: newest 2 unbootable -> the newest bootable (u3) kept too, u2 goes",
       sorted(n for n in snaps() if n in (u2, u3, u4, u5)), [u3, u4, u5])
    u6 = snapper_create("auto=pre-transaction,upgrade=yes", "pacman: good again")
    tool("prune")
    eq("prune: a bootable new one -> back to 2", sorted(n for n in snaps() if n in (u3, u4, u5, u6)), [u5, u6])
    eq("prune: baseline, legacy slot, unslotted manual untouched", all(n in snaps() for n in (base, legacy, old_manual)), True)

    # ---- slots: create into an empty slot
    rc, res, err = jtool("slot-set", "1", "Vor Kernel-Test")
    eq("slot-set empty slot: ok", (rc, res and res["slot"], res and res["replaced"]), (0, 1, None))
    s1 = res["number"]
    eq("slot snapshot: cleanup '' (snapper's cleanup never sees it), mslot=1, important",
       (snaps()[s1]["cleanup"], snaps()[s1]["userdata"]), ("", {"important": "yes", "mslot": "1"}))
    eq("slot-list", slots(), {1: s1, 2: None, 3: None})
    e = entry(s1)
    eq("slot entry title", e.splitlines()[1], "title    Slot 1: Vor Kernel-Test - 2026-10-10 10:%02d (#%d)" % (s1 % 60, s1))
    opts = [l for l in e.splitlines() if l.startswith("options")][0].split()[1:]
    eq("slot entry options", ["rootflags=subvol=@snapshots/%d/snapshot" % s1 in opts, "noresume" in opts,
                              "workstation.snapshot=%d" % s1 in opts, any(o.startswith("resume") for o in opts)],
       [True, True, True, False])
    eq("update entry title", entry(u6).splitlines()[1], "title    Update snapshot 2026-10-10 10:%02d - pacman: good again (#%d)" % (u6 % 60, u6))
    eq("menu: u5 not offered (no UKI for 6.0.0), u6 + slot 1", entries(),
       sorted(["workstation-snapshot-%d.conf" % n for n in (u6, s1)]))
    eq("u5 skipped with a reason", any(x["number"] == u5 and x["reason"].startswith("no stored UKI") for x in state()["skipped"]), True)
    eq("legacy slot snapshot not offered twice", any(x["number"] == legacy for x in state()["entries"]), False)

    # ---- occupied slot: refused without the confirmed number (cancel = this call never happens)
    before = sorted(snaps())
    rc, out, err = tool("slot-set", "1", "Ohne Bestaetigung")
    eq("occupied slot without --replace: refused, nothing created",
       (rc, sorted(snaps()), "overwrite it only after confirming" in err), (1, before, True))
    rc, out, err = tool("slot-set", "1", "Falsche Nummer", "--replace", "999")
    eq("--replace with another number: refused", (rc, sorted(snaps())), (1, before))

    # ---- overwrite: new first, then the old one goes
    rc, res, err = jtool("slot-set", "1", "Neuer Stand", "--replace", str(s1))
    s1b = res["number"]
    eq("overwrite: ok, replaced the old", (rc, res["replaced"], s1 in snaps(), slots()[1]), (0, s1, False, s1b))
    eq("overwrite: entry follows", ("workstation-snapshot-%d.conf" % s1b in entries(), "workstation-snapshot-%d.conf" % s1 in entries()),
       (True, False))

    # ---- failures while creating: the slot stays
    flag("create")
    rc, out, err = tool("slot-set", "1", "Kaputt", "--replace", str(s1b))
    flag("create", False)
    eq("create failure: slot unchanged", (rc, slots()[1], s1b in snaps(), "could not create" in err), (1, s1b, True, True))
    kernel("6.0.0")
    n_before = set(snaps())
    rc, out, err = tool("slot-set", "1", "Nicht bootfaehig", "--replace", str(s1b))
    kernel(None)
    eq("new snapshot cannot boot: removed again, slot unchanged",
       (rc, slots()[1], set(snaps()) == n_before, "cannot boot" in err), (1, s1b, True, True))
    flag("modify")
    rc, out, err = tool("slot-set", "1", "Zuordnung scheitert", "--replace", str(s1b))
    flag("modify", False)
    eq("assign failure: new one removed, slot unchanged", (rc, slots()[1], set(snaps()) == n_before), (1, s1b, True))

    # ---- sync failure: the slot is set, the warning says the menu is not synced
    d = os.path.join(R, "boot/loader/entries")
    os.chmod(d, 0o500)
    rc, res, err = jtool("slot-set", "2", "Sync scheitert")
    os.chmod(d, 0o700)
    s2 = res["number"] if res else None
    eq("sync failure: slot 2 assigned, warning", (rc, slots()[2] == s2, any("not synced" in x for x in res["warnings"])),
       (0, True, True))
    tool("sync")
    eq("next sync: entry there", "workstation-snapshot-%d.conf" % s2 in entries(), True)

    # ---- UKI dedup: slots 1+2 (and u6) share the 7.2.9 copy; a new kernel gets its own
    uki("/boot/EFI/Linux/arch-linux.efi", "7.3.0")
    kernel("7.3.0")
    rc, res, err = jtool("slot-set", "3", "Neuer Kernel")
    kernel(None)
    s3 = res["number"]
    eq("UKI copies: 7.2.9 shared, 7.3.0 for slot 3", ukis(), ["7.2.9.efi", "7.3.0.efi"])
    eq("menu: 1 update + 3 slots", len(entries()), 4)

    # ---- delete: only the confirmed number; then the slot is free again
    rc, out, err = tool("slot-delete", "2", str(s1b))
    eq("delete with the wrong number: refused", (rc, slots()[2]), (1, s2))
    rc, res, err = jtool("slot-delete", "2", str(s2))
    eq("delete: slot 2 empty, snapshot + entry gone",
       (rc, slots()[2], s2 in snaps(), "workstation-snapshot-%d.conf" % s2 in entries()), (0, None, False, False))
    eq("delete: the shared 7.2.9 copy stays (slot 1 + u6 use it)", "7.2.9.efi" in ukis(), True)
    rc, res, err = jtool("slot-set", "2", "Wiederverwendet")
    eq("empty slot reused", (rc, slots()[2] == res["number"]), (0, True))
    jtool("slot-delete", "2", str(res["number"]))

    # ---- slots survive many updates; classes stay bounded
    for i in range(4):
        snapper_create("auto=pre-transaction,upgrade=yes", "pacman: run %d" % i)
        snapper_create("auto=pre-transaction", "pacman: other %d" % i)
        tool("prune")
    eq("many updates later: slots 1 and 3 untouched", (slots()[1], slots()[3], s1b in snaps(), s3 in snaps()), (s1b, s3, True, True))
    ud = [s["userdata"] or {} for s in snaps().values()]
    eq("update class bounded to 2, other to 2",
       (sum(1 for u in ud if u.get("auto") and (u.get("upgrade") or u.get("update")) and not u.get("slot")),
        sum(1 for u in ud if u == {"auto": "pre-transaction"})), (2, 2))
    tool("sync")
    eq("menu: 2 update + 3 slots at most", (len(entries()) <= 5,
                                            sum(1 for f in entries() if "Update snapshot" in entry(int(f[21:-5])))), (True, 2))
    eq("7.2.9 copy kept: slot 1 still has that kernel", "7.2.9.efi" in ukis(), True)

    kernel("7.3.0")                     # the running system has 7.3.0 now: new snapshots carry it
    # ---- an interrupted overwrite left a second holder: the newest holds the slot, the next overwrite cleans both
    dup = snapper_create("important=yes,mslot=3", "second holder")
    eq("duplicate: the newest number holds the slot", slots()[3], dup)
    rc, res, err = jtool("slot-set", "3", "Aufgeraeumt", "--replace", str(dup))
    eq("overwrite removes the other holder too", (rc, s3 in snaps(), dup in snaps(), slots()[3] == res["number"]), (0, False, False, True))
    s3 = res["number"]
    # a pending one (crash between create and assign) is removed by the next slot-set of that slot
    pend = snapper_create("important=yes,mslot-new=3", "pending")
    rc, res, err = jtool("slot-set", "3", "Nach Absturz", "--replace", str(s3))
    eq("pending leftover removed", (rc, pend in snaps()), (0, False))
    s3 = res["number"]

    kernel(None)
    # ---- a kernel no kept snapshot has any more: its copy goes
    uki("/boot/EFI/workstation/snapshots/6.9.0.efi", "6.9.0")
    tool("sync")
    eq("unused kernel copy (6.9.0) removed, used ones kept", ukis(), ["7.2.9.efi", "7.3.0.efi"])
    # ---- rollback: the restored system's state file is gone -> one sync rebuilds the same menu
    before = entries()
    os.unlink(os.path.join(R, "var/lib/workstation/snapshot-boot.json"))
    tool("sync")
    eq("after a rollback (no state): same entries, same slots", (entries(), slots()), (before, {1: s1b, 2: None, 3: s3}))

    # ---- snapshot mode: no slot changes, no retention
    w("/proc/cmdline", "rootflags=subvol=@snapshots/%d/snapshot workstation.snapshot=%d\n" % (s1b, s1b))
    rc, out, err = tool("slot-delete", "1", str(s1b))
    eq("snapshot mode: delete refused", (rc, slots()[1]), (1, s1b))
    rc, out, err = tool("slot-set", "2", "im Snapshot")
    eq("snapshot mode: create refused", (rc, slots()[2]), (1, None))
    n_before = sorted(snaps())
    tool("prune")
    eq("snapshot mode: no retention", sorted(snaps()), n_before)
    w("/proc/cmdline", "rootflags=subvol=@\n")

    # ---- Secure Boot on: no entries; snapper failure: entries kept
    w("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c", "\x06\x00\x00\x00\x01")
    rc, out, err = tool("sync")
    eq("secure boot: no entries, error", (rc, entries(), "Secure Boot" in " ".join(state()["errors"])), (1, [], True))
    eq("secure boot: UKI copies NOT cleaned up (snapshots stay bootable later)", ukis(), ["7.2.9.efi", "7.3.0.efi"])
    os.unlink(os.path.join(R, "sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"))
    tool("sync")
    kept = entries()
    eq("Secure Boot off again: the entries are back", len(kept), 4)
    flag("list")
    rc, out, err = tool("sync")
    flag("list", False)
    eq("snapper failure: entries kept, ok=false", (rc, entries(), state()["ok"]), (1, kept, False))

    # ---- slot-list text form, usage, file modes
    rc, out, err = tool("slot-list")
    eq("slot-list text", ("slot 2  empty" in out, "Neuer Stand" in out), (True, True))
    rc, out, err = tool("slot-set", "4", "x")
    eq("usage: slot 4", rc, 2)
    eq("entry files root-only", oct(stat.S_IMODE(os.stat(os.path.join(R, "boot/loader/entries", entries()[0])).st_mode)), "0o600")
finally:
    shutil.rmtree(T)

print("snapshot-boot: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
