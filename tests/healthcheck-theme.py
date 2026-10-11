#!/usr/bin/env python3
"""repo-healthcheck theme_checks() against a temporary HOME (Bug Hunt v1, HC1).

A theme imported at runtime lives in ~/.local/share/workstation/themes/
compiled/<id>/ (theme helper), not in the repo's themes/. Its chosen
wallpaper must not be reported as "file gone". The healthcheck is rendered
from its template and loaded as a module; `theme status --json` is a stub.
Safe anywhere: nothing outside the temporary directory is read or written
except the template."""
import json, os, sys, tempfile, types

import jinja2

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp(prefix="hc-theme-")
fails = []


def ok(name, cond):
    if not cond:
        fails.append(name)
        print("FAIL", name)


themes = os.path.join(tmp, "themes")
compiled = os.path.join(tmp, "data", "workstation", "themes", "compiled")
for d in (os.path.join(themes, "bundled", "backgrounds"), os.path.join(compiled, "imported", "backgrounds"),
          os.path.join(tmp, "home", ".local", "bin"), os.path.join(tmp, "cfg", "workstation", "theme")):
    os.makedirs(d)
open(os.path.join(themes, "bundled", "backgrounds", "b.png"), "w").close()
open(os.path.join(compiled, "imported", "backgrounds", "i.png"), "w").close()
for n in ("colors.json", "hyprland.lua", "hyprlock.conf", "ghostty"):
    open(os.path.join(tmp, "cfg", "workstation", "theme", n), "w").close()


def status(wallpapers):
    return {"dark": [{"id": "imported", "name": "Imported"}], "light": [{"id": "bundled", "name": "Bundled"}],
            "invalid": {}, "state": {"dark": "imported", "light": "bundled", "mode": "dark", "wallpapers": wallpapers}}


src = open(os.path.join(repo, "roles/diagnostics/templates/repo-healthcheck.j2")).read()
env = jinja2.Environment(undefined=jinja2.ChainableUndefined)
env.filters["bool"] = lambda x: x is True or str(x).lower() in ("true", "yes", "1", "on")
code = env.from_string(src).render(
    theme_dir=themes, playbook_dir=repo, diagnostics_lib_dir=os.path.join(repo, "roles/diagnostics/files"))
os.environ.update(HOME=os.path.join(tmp, "home"), XDG_CONFIG_HOME=os.path.join(tmp, "cfg"),
                  XDG_DATA_HOME=os.path.join(tmp, "data"))


def run(wallpapers):
    m = types.ModuleType("hc")
    m.__dict__["__name__"] = "hc"
    exec(compile(code, "repo-healthcheck", "exec"), m.__dict__)
    m.run = lambda argv, **kw: (0, json.dumps(status(wallpapers)))
    m.outputs_current = getattr(m, "outputs_current", None)
    try:
        m.theme_checks()
    except Exception as e:                 # a crash is a failure too
        return [("CRASH", "theme_checks", repr(e))]
    return m.results


r = run({"imported": "i.png", "bundled": "b.png"})
ok("imported theme's own wallpaper is not 'file gone'", not any(n == "wallpaper choices" for _, n, _ in r))
r = run({"imported": "missing.png"})
ok("a really missing wallpaper is still reported", any(n == "wallpaper choices" and s == "WARN" for s, n, _ in r))
r = run({"bundled": "b.png"})
ok("bundled wallpaper ok", not any(n == "wallpaper choices" for _, n, _ in r))
ok("no crash", not any(s == "CRASH" for s, _, _ in r))
import shutil
shutil.rmtree(tmp)
print("healthcheck-theme: %d failed" % len(fails) if fails else "healthcheck-theme: all passed")
sys.exit(1 if fails else 0)
