#!/usr/bin/env python3
"""The privilege matrix (docs/security/SECURITY_HARDENING_V1_1_REPORT.md) as
deployed by the roles: every polkit action of this repository rendered from
its template - who may do what without a password, and which ONE program
each action runs - plus the sources of other privileges (docker group,
sudoers). Static: nothing on this machine is read or changed."""
import glob, os, re, sys
import xml.etree.ElementTree as ET

import jinja2
import yaml

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fails = 0


def ok(name, cond):
    global fails
    if not cond:
        fails += 1
        print("FAIL", name)


def defaults(role):
    with open(os.path.join(repo, "roles", role, "defaults", "main.yml")) as f:
        return yaml.safe_load(f) or {}


v = {}
for role in ("firewall", "recovery"):
    v.update(defaults(role))
env = jinja2.Environment()
actions = {}
for role in ("firewall", "recovery"):
    for tpl in glob.glob(os.path.join(repo, "roles", role, "templates", "*.policy.j2")):
        root = ET.fromstring(env.from_string(open(tpl).read()).render(**v).encode())
        for a in root.iter("action"):
            d = a.find("defaults")
            path = [x.text for x in a.iter("annotate") if x.get("key") == "org.freedesktop.policykit.exec.path"]
            actions[a.get("id")] = {k: d.find(k).text for k in ("allow_any", "allow_inactive", "allow_active")}
            actions[a.get("id")]["path"] = path[0] if path else None

# Who may do what (active local session; remote / inactive = admin always).
want = {
    "org.workstation.firewall.status": ("yes", v.get("firewall_status_helper")),
    "org.workstation.firewall.manage": ("auth_admin_keep", v.get("firewall_helper")),
    "org.workstation.snapshot.create": ("yes", v.get("recovery_snapshot_helper")),
    "org.workstation.snapshot.delete": ("auth_admin_keep", v.get("recovery_snapshot_delete_helper")),
    "org.workstation.snapshot.restore": ("auth_admin", v.get("recovery_restore_helper")),
}
ok("exactly the expected polkit actions: %s" % sorted(actions), sorted(actions) == sorted(want))
for aid, (active, path) in want.items():
    a = actions.get(aid, {})
    ok(aid + ": active session = " + active, a.get("allow_active") == active)
    ok(aid + ": remote/inactive = auth_admin", a.get("allow_any") == "auth_admin" and a.get("allow_inactive") == "auth_admin")
    ok(aid + ": runs exactly " + str(path), path is not None and a.get("path") == path)
paths = [a["path"] for a in actions.values()]
ok("one program per action", len(paths) == len(set(paths)))

# The passwordless firewall action is a fixed `list`, nothing else.
st = os.path.join(repo, "roles/firewall/templates/firewall-status.j2")
if os.path.exists(st):
    text = env.from_string(open(st).read()).render(**v)
    execs = [l.strip() for l in text.splitlines() if l.strip().startswith("exec ")]
    ok("firewall-status: one exec of `firewall-rules list`", execs == ["exec %s list" % v["firewall_helper"]])
else:
    ok("firewall-status template exists", False)

# Docker: no role puts a user into `docker`; the development role takes the
# invoking user out (the group is root-equivalent while Docker runs).
adds = []
for path in glob.glob(os.path.join(repo, "roles", "*", "tasks", "*.yml")):
    for t in yaml.safe_load(open(path)) or []:
        u = t.get("ansible.builtin.user") or t.get("user")
        if isinstance(u, dict) and "docker" in str(u.get("groups", "")):
            adds.append(path)
ok("no task adds a user to the docker group: %s" % adds, not adds)
dev = open(os.path.join(repo, "roles/development/tasks/main.yml")).read()
ok("development role removes the invoking user from docker", re.search(r"gpasswd, --delete", dev) is not None)

# The removal's condition, rendered for every shape getent can return.
dtasks = yaml.safe_load(open(os.path.join(repo, "roles/development/tasks/main.yml")))
rm = next(t for t in dtasks if "docker group (sudo docker" in t.get("name", ""))
cond = env.from_string("{{ " + " ".join(rm["when"].split()) + " }}")
for members, want_rm in [("medvidec", True), ("alice,medvidec,bob", True), ("", False),
                         ("alice", False), ("medvidec2", False), (None, False)]:
    facts = {"user_id": "medvidec", "getent_group": {} if members is None else {"docker": ["x", "960", members]}}
    got = cond.render(ansible_facts=facts) == "True"
    ok("docker removal when members=%r -> %s" % (members, want_rm), got == want_rm)

# sudo: nothing passwordless anywhere in the roles.
nopw = [p for p in glob.glob(os.path.join(repo, "roles", "**", "*"), recursive=True)
        if os.path.isfile(p) and "NOPASSWD" in open(p, errors="ignore").read()]
ok("no NOPASSWD in the roles: %s" % nopw, not nopw)

print("privileges: all checks passed" if not fails else "privileges: %d FAILED" % fails)
sys.exit(1 if fails else 0)
