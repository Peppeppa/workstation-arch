#!/usr/bin/env python3
"""Keybindings vs. the cheatsheet document, per host (run by tests/run.sh).

Renders roles/hyprland's binds.lua.j2 and cheatsheet.md.j2 with each host's
variables (role defaults < group_vars/all.yml < host_vars/<host>.yml, like
Ansible) and checks:
  - no key combination is bound twice
  - every main-modifier bind appears in the cheatsheet, and every key the
    cheatsheet names is bound (no stale or missing rows)
  - removed binds stay removed (Super+F1, Super+Shift+T)
With an output directory as argument, the laptop's rendered hyprland.md is
written there (tests/cheatsheet-render.qml renders it with Qt).
"""
import os
import re
import sys

import jinja2
import yaml

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TPL = os.path.join(ROOT, "roles/hyprland/templates")
MODS = {"SHIFT": "Shift", "CTRL": "Ctrl", "ALT": "Alt", "SUPER": "Super"}


def load(path):
    with open(os.path.join(ROOT, path)) as f:
        return yaml.safe_load(f) or {}


def render(name, variables):
    # trim_blocks like Ansible's template module (a {% if %} line inside a
    # Markdown table must not leave an empty line that ends the table)
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(TPL), undefined=jinja2.StrictUndefined,
                             keep_trailing_newline=True, trim_blocks=True)
    return env.get_template(name).render(**variables)


def check(host):
    v = {}
    for role in ("hyprland", "desktop", "quickshell", "power"):
        p = os.path.join("roles", role, "defaults/main.yml")
        if os.path.exists(os.path.join(ROOT, p)):
            v.update(load(p))
    v.update(load("group_vars/all.yml"))
    v.update(load("host_vars/%s.yml" % host))
    v["ansible_facts"] = {"user_dir": "/home/test"}
    binds = render("conf/binds.lua.j2", v)
    sheet = render("cheatsheet.md.j2", v)
    mod = v["hyprland_main_modifier"]
    m = "Super" if mod == "SUPER" else mod.capitalize()
    resize = "Ctrl" if mod == "ALT" else "Alt"
    errors = []

    # literal main-modifier binds: mainMod .. " + SHIFT + X" / .. resizeMod .. " + H"
    combos = []
    for line in binds.splitlines():
        code = line.split("--")[0]
        b = re.search(r'hl\.bind\(mainMod \.\. "( \+ [^"]+)"', code)
        if b and not b.group(1).endswith(" + "):        # (" + " .. i: the workspace loop, added below)
            combos.append(tuple(MODS.get(t, t) for t in b.group(1).split(" + ")[1:]))
        b = re.search(r'hl\.bind\(mainMod \.\. " \+ " \.\. resizeMod \.\. " \+ (\w+)"', code)
        if b:
            combos.append((resize, b.group(1)))
    dup = sorted({c for c in combos if combos.count(c) > 1})
    if dup:
        errors.append("bound twice: %s" % dup)

    # cheatsheet rows: `Super + [Mods +] keys` (keys: "H / J / K / L", "1 ... 9")
    rows = set()
    for k in re.findall(r"^\| `%s \+ ([^`]+)`" % m, sheet, re.M):
        parts = k.split(" + ")
        mods, keys = tuple(parts[:-1]), parts[-1]
        for key in re.split(r" / | \.\.\. ", keys):
            rows.add(mods + (key.split(" ")[0],))
    bound = {c for c in combos if c[-1] not in ("left", "right", "up", "down")}
    bound |= {("1",), ("9",), ("Shift", "1"), ("Shift", "9")}          # the workspace loop
    named = {("mouse:272",): ("left",), ("mouse:273",): ("right",)}     # "left / right mouse drag"
    bound = {named.get(c, c) for c in bound}
    for c in sorted(bound - rows):
        errors.append("bound but not in the cheatsheet: %s + %s" % (m, " + ".join(c)))
    for c in sorted(rows - bound):
        errors.append("in the cheatsheet but not bound: %s + %s" % (m, " + ".join(c)))
    for gone in (("F1",), ("Shift", "T")):
        if gone in combos:
            errors.append("removed bind is back: %s + %s" % (m, " + ".join(gone)))
    return errors, sheet


def main():
    fail = False
    for f in sorted(os.listdir(os.path.join(ROOT, "host_vars"))):
        host = f[:-4]
        errors, sheet = check(host)
        for e in errors:
            print("FAIL %s: %s" % (host, e))
        fail |= bool(errors)
        if host == "laptop" and len(sys.argv) > 1:
            with open(os.path.join(sys.argv[1], "hyprland.md"), "w") as out:
                out.write(sheet)
    if not fail:
        print("keybindings: no duplicates, cheatsheet matches the binds on every host")
    sys.exit(1 if fail else 0)


main()
