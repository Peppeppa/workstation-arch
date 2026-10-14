#!/usr/bin/env python3
"""repo-healthcheck pacman_lock_status(): a db.lck without a running pacman
is stale (a restored pacman-hook snapshot left one - Hardware Acceptance v2).
Pure function; nothing of the system is read."""
import os, sys, types

import jinja2

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(repo, "roles/diagnostics/templates/repo-healthcheck.j2")).read()
env = jinja2.Environment(undefined=jinja2.ChainableUndefined)
env.filters["bool"] = lambda x: x is True or str(x).lower() in ("true", "yes", "1", "on")
m = types.ModuleType("hc")
m.__dict__["__name__"] = "hc"
exec(compile(env.from_string(src).render(playbook_dir=repo, diagnostics_lib_dir=os.path.join(repo, "roles/diagnostics/files")),
             "repo-healthcheck", "exec"), m.__dict__)

fails = 0
for name, args, want in [
        ("no lock -> PASS", (False, {"bash"}), True),
        ("lock held by pacman -> PASS", (True, {"bash", "pacman"}), True),
        ("lock, no pacman -> FAIL (stale)", (True, {"bash", "Hyprland"}), False),
]:
    ok, detail = m.pacman_lock_status(*args)
    if ok != want:
        fails += 1
        print("FAIL", name, "->", ok, detail)
print("healthcheck-pacman-lock: all checks passed" if not fails else "healthcheck-pacman-lock: %d FAILED" % fails)
sys.exit(1 if fails else 0)
