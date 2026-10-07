#!/bin/sh
# Managed by Ansible (roles/hyprland/files/focus-or-launch.sh) - do not edit.
# focus-or-launch CLASS_REGEX COMMAND [ARGS...] - one-shot helper for a
# keybind: focus the first window whose class matches CLASS_REGEX (Python
# re.search), otherwise start COMMAND. One `hyprctl clients` read per
# keypress, then it exits.
set -eu
[ $# -ge 2 ] || { echo "usage: focus-or-launch CLASS_REGEX COMMAND [ARGS...]" >&2; exit 2; }
regex=$1; shift
addr=$(hyprctl clients -j 2>/dev/null | python3 -c '
import json, re, sys
rx = re.compile(sys.argv[1])
for c in json.load(sys.stdin):
    if rx.search(c.get("class") or ""):
        print(c["address"]); break
' "$regex" || true)
if [ -n "$addr" ]; then
    exec hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
fi
exec "$@"
