#!/usr/bin/env python3
"""ADD the workstation's LazyVim extras to lazyvim.json (roles/apps).

usage: lazyvim-extras.py <path/to/lazyvim.json> <extra,extra,...>
Prints "changed" or "unchanged". Other extras and keys stay the user's.

A file created here (fresh install: LazyVim has not run yet) carries the
same "version" / "install_version" LazyVim 16 writes for a new install
(json format 8). Without "version" LazyVim treats the file as format 0 and
prefixes every entry with "lazyvim.plugins.extras." once more ->
"Failed to load lazyvim.plugins.extras.lazyvim.plugins.extras.lang.python"
for every extra at each start (Clean Install Acceptance v1); without
"install_version" it falls back to the pre-8 defaults (fzf-lua, neo-tree
instead of the snacks picker/explorer the keymaps expect). A later LazyVim
migrates from 8 itself."""
import json, os, sys

LAZYVIM_JSON_VERSION = 8
PREFIX = "lazyvim.plugins.extras."

path, wanted = sys.argv[1], [e for e in sys.argv[2].split(",") if e]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {"install_version": LAZYVIM_JSON_VERSION}
before = json.dumps(data, sort_keys=True)

extras = data.setdefault("extras", [])
# Repairs of files earlier versions of this task broke:
# 2026-10-10: the whole list as ONE string entry "['lazyvim.plugins.extras...']".
extras[:] = [e for e in extras if not e.startswith("['" + PREFIX)]
# 2026-10-14: a file without "version" -> LazyVim's v0 migration doubled the
# prefix (and, never having written the file itself, left no install_version).
if any(e.startswith(PREFIX + PREFIX) for e in extras):
    extras[:] = [PREFIX + e[2 * len(PREFIX):] if e.startswith(PREFIX + PREFIX) else e for e in extras]
    data.setdefault("install_version", LAZYVIM_JSON_VERSION)
extras[:] = list(dict.fromkeys(extras)) + [e for e in wanted if e not in extras]
data.setdefault("version", LAZYVIM_JSON_VERSION)

changed = json.dumps(data, sort_keys=True) != before
if changed:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
print("changed" if changed else "unchanged")
