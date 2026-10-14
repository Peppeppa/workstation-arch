#!/usr/bin/env python3
"""roles/apps/files/lazyvim-extras.py against temporary lazyvim.json files
(nothing of the real Neovim config is read or changed).

Regression (Clean Install Acceptance v1): on a fresh install the task created
lazyvim.json without "version"; LazyVim's v0 migration doubled every extra
("lazyvim.plugins.extras.lazyvim.plugins.extras.lang.python" -> 13 "Failed
to load" errors at each start) and, lacking install_version, it picked the
pre-8 defaults (fzf-lua/neo-tree). When a LazyVim checkout exists
($LAZYVIM_DIR or ~/.local/share/nvim/lazy/LazyVim) and nvim is installed,
the result also goes through LazyVim's own load/migrate code."""
import json, os, re, shutil, subprocess, sys, tempfile

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
script = os.path.join(repo, "roles/apps/files/lazyvim-extras.py")
P = "lazyvim.plugins.extras."
wanted = [P + "lang.python", P + "dap.core"]
fails = 0


def ok(name, cond):
    global fails
    if not cond:
        fails += 1
        print("FAIL", name)


def run(path):
    r = subprocess.run([sys.executable, script, path, ",".join(wanted)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    with open(path) as f:
        return r.stdout.strip(), json.load(f)


lazyvim = os.environ.get("LAZYVIM_DIR", os.path.expanduser("~/.local/share/nvim/lazy/LazyVim"))
have_lazyvim = os.path.isfile(os.path.join(lazyvim, "lua/lazyvim/util/json.lua")) and shutil.which("nvim")
LOAD = r"""
local lv, path = arg[1], arg[2]
package.path = lv .. "/lua/?.lua;" .. package.path
local src = io.open(lv .. "/lua/lazyvim/config/init.lua"):read("*a")
local version = tonumber(src:match("M%.json = {%s*version = (%d+)"))
local data = vim.json.decode(io.open(path):read("*a"), { luanil = { object = true, array = true } })
_G.LazyVim = { info = function() end, is_list = vim.islist }
LazyVim.json = require("lazyvim.util.json")
LazyVim.config = { json = { version = version, path = path,
  data = vim.tbl_deep_extend("force", { news = {}, extras = {} }, data) } }
if LazyVim.config.json.data.version ~= version then LazyVim.json.migrate() end
local d = LazyVim.config.json.data
io.stdout:write(vim.json.encode({ extras = d.extras, install = d.install_version or 7 }))
"""


def lazyvim_view(path):
    """What LazyVim itself makes of the file: (extras, effective install_version)."""
    lua = os.path.join(os.path.dirname(path), "load.lua")
    with open(lua, "w") as f:
        f.write(LOAD)
    r = subprocess.run(["nvim", "--clean", "--headless", "-l", lua, lazyvim, path],
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    return d["extras"], d["install"]


with tempfile.TemporaryDirectory() as tmp:
    # 1. fresh install: no lazyvim.json yet
    f1 = os.path.join(tmp, "fresh.json")
    out, d = run(f1)
    ok("fresh: changed", out == "changed")
    ok("fresh: exactly the wanted extras", d["extras"] == wanted)
    ok("fresh: version + install_version written", d.get("version") == 8 and d.get("install_version") == 8)
    ok("fresh: second run unchanged", run(f1)[0] == "unchanged")
    if have_lazyvim:
        extras, install = lazyvim_view(f1)
        ok("fresh: LazyVim loads the names unchanged (no doubled prefix): %s" % extras, extras == wanted)
        ok("fresh: LazyVim sees a new install (snacks defaults), install_version=%s" % install, install >= 8)

    # 2. the file the 2026-10-14 clean install got (LazyVim already migrated it)
    f2 = os.path.join(tmp, "broken.json")
    with open(f2, "w") as f:
        json.dump({"extras": [P + w for w in wanted], "news": {"NEWS.md": "1"}, "version": 8}, f)
    out, d = run(f2)
    ok("broken: repaired", out == "changed" and d["extras"] == wanted)
    ok("broken: install_version 8 added, news kept", d.get("install_version") == 8 and d["news"] == {"NEWS.md": "1"})
    ok("broken: second run unchanged", run(f2)[0] == "unchanged")

    # 3. the user's own file (written by LazyVim): only additions, nothing else
    f3 = os.path.join(tmp, "user.json")
    user = {"extras": [P + "editor.neo-tree", P + "dap.core"], "install_version": 7, "version": 8}
    with open(f3, "w") as f:
        json.dump(user, f)
    out, d = run(f3)
    ok("user: own extras + install_version kept, python added",
       d["extras"] == [P + "editor.neo-tree", P + "dap.core", P + "lang.python"] and d["install_version"] == 7)
    ok("user: second run unchanged", run(f3)[0] == "unchanged")
    if have_lazyvim:
        ok("user: LazyVim keeps the names", lazyvim_view(f3)[0] == d["extras"])

    # 4. the 2026-10-10 one-string entry
    f4 = os.path.join(tmp, "string.json")
    with open(f4, "w") as f:
        json.dump({"extras": ["['%slang.python']" % P], "version": 8}, f)
    out, d = run(f4)
    ok("one-string entry removed", d["extras"] == wanted)

print("lazyvim-extras: all checks passed%s" % ("" if have_lazyvim else " (LazyVim load step skipped: no checkout)")
      if not fails else "lazyvim-extras: %d FAILED" % fails)
sys.exit(1 if fails else 0)
