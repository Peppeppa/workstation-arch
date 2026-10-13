#!/usr/bin/env python3
"""roles/recovery: the fstab options Ansible writes for /.snapshots (Security
Audit v1, S1). Old snapshots keep old SUID-root binaries (sudo, pkexec, ...);
/.snapshots is world-readable (snapshot-boot slot-list reads info.xml as
the user), so it must be mounted nosuid,nodev. Renders the task's own `opts`
expression for every loop item against a real root fstab line."""
import os, re, sys

import jinja2
import yaml

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tasks = yaml.safe_load(open(os.path.join(repo, "roles/recovery/tasks/main.yml")))
task = next(t for t in tasks if "ansible.posix.mount" in t)
env = jinja2.Environment()
env.tests["match"] = lambda value, pattern: re.match(pattern, value) is not None   # Ansible's `match` test
fstab = "UUID=e7db rw,relatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@"
fails = 0


def ok(name, cond):
    global fails
    if not cond:
        fails += 1
        print("FAIL", name)


for item in task["loop"]:
    opts = env.from_string(task["ansible.posix.mount"]["opts"]).render(
        recovery_root_fstab={"stdout": fstab}, item=item).strip().split(",")
    p = item["path"]
    ok(p + ": own subvolume, root's subvol dropped", "subvol=/" + item["subvol"] in opts and "subvol=/@" not in opts)
    ok(p + ": root's other options kept", all(o in opts for o in ("compress=zstd:3", "ssd", "space_cache=v2")))
    if p == "/.snapshots":
        ok("/.snapshots: nosuid (old SUID binaries in snapshots stay inert)", "nosuid" in opts)
        ok("/.snapshots: nodev", "nodev" in opts)
print("recovery-mounts: all checks passed" if not fails else "recovery-mounts: %d FAILED" % fails)
sys.exit(1 if fails else 0)
