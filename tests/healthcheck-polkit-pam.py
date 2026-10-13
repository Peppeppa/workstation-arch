#!/usr/bin/env python3
"""repo-healthcheck polkit_pam_status() (P1, docs/testing/POLKIT_PAM_P1_REPORT.md):
the repository's /etc/pam.d/polkit-1 against Arch's stock system-auth
(tests/fixtures). Pure function on texts; nothing of the system is read."""
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

stock = open(os.path.join(repo, "tests/fixtures/pambase-system-auth")).read()
ours = open(os.path.join(repo, "roles/desktop/files/polkit-1.pam")).read()
vendor = "#%PAM-1.0\n\nauth include system-auth\naccount include system-auth\n"
fails = 0
for name, args, want in [
        ("repository file in sync with stock system-auth", (stock, ours), (True, False)),
        ("file missing -> FAIL", (stock, None), (False, False)),
        ("vendor stack (include system-auth) -> FAIL", (stock, vendor), (False, False)),
        ("system-auth changed (e.g. deny=5 added) -> WARN", (stock.replace("authfail", "authfail deny=5"), ours), (False, True)),
]:
    got = m.polkit_pam_status(*args)[:2]
    if got != want:
        fails += 1
        print("FAIL", name, got)
print("healthcheck-polkit-pam: all checks passed" if not fails else "healthcheck-polkit-pam: %d FAILED" % fails)
sys.exit(1 if fails else 0)
