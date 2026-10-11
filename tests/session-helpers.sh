#!/usr/bin/env bash
# Session helpers of roles/hyprland (Bug Hunt v1): focus-or-launch with a
# stubbed hyprctl - focus an existing window, launch otherwise, and launch
# (never crash) when hyprctl is missing, fails or prints garbage.
# Safe anywhere: only stubs in a temporary PATH run. Run by tests/run.sh.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { if ! eval "$2"; then echo "FAIL $1"; fail=1; fi; }
mkdir -p "$tmp/stub"
log="$tmp/log"
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$tmp/stub/$1"; chmod +x "$tmp/stub/$1"; }
stub hyprctl 'if [ "$1" = clients ]; then [ -n "${CLIENTS_RC:-}" ] && exit "$CLIENTS_RC"; printf "%s" "${CLIENTS:-[]}"; else echo "hyprctl $*" >> '"$log"'; fi'
stub launched 'echo "launched $*" >> '"$log"
F="$repo/roles/hyprland/files/focus-or-launch.sh"
run() { : > "$log"; PATH="$tmp/stub:/usr/bin:/bin" sh "$F" "$@" >/dev/null 2>&1; rc=$?; }

CLIENTS='[{"class": "chromium", "address": "0xabc"}]' run '^chromium$' launched x
ok "existing window: focused" 'grep -q "address:0xabc" "$log" && ! grep -q launched "$log"'
CLIENTS='[{"class": "org.gnome.Nautilus", "address": "0x1"}]' run '^chromium$' launched x
ok "no match: launched with its args" 'grep -qx "launched x" "$log"'
CLIENTS='not json' run '^chromium$' launched
ok "garbage from hyprctl: launched" 'grep -q "^launched" "$log"'
CLIENTS_RC=1 run '^chromium$' launched
ok "hyprctl fails: launched" 'grep -q "^launched" "$log"'
CLIENTS='[{"class": null, "address": "0x2"}, {"address": "0x3"}]' run '^chromium$' launched
ok "client without class: no crash, launched" 'grep -q "^launched" "$log"'
CLIENTS='[]' run '([' launched
ok "invalid regex: launched, no focus" 'grep -q "^launched" "$log"'
run onlyone
ok "usage: exit 2" '[ "$rc" -eq 2 ]'
[ $fail -eq 0 ] && echo "session-helpers: all checks passed"
exit $fail
