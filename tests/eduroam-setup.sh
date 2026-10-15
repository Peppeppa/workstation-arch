#!/usr/bin/env bash
# eduroam-setup (roles/network) against stubbed nmcli / nm-connection-editor /
# python3 - no NetworkManager, no profile is touched. Checks: only Wi-Fi
# 802.1X profiles with an agent-owned (1) / not-saved (2) password are
# switched to flags 0, nothing else is modified, the editor opens once per
# switched profile, the installer runs with its arguments, a missing
# installer file stops before anything changes.
set -u
cd "$(dirname "$0")/.."
script=$PWD/roles/network/files/eduroam-setup
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
log=$tmp/log

cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/bash
# profiles: uuid type eap flags id
profiles="u-edu 802-11-wireless peap 1 eduroam
u-thws 802-11-wireless peap 1 THWS
u-ok 802-11-wireless peap 0 Office
u-ask 802-11-wireless ttls 2 Lab
u-psk 802-11-wireless - - Home
u-eth 802-3-ethernet - - Wired"
if [ "$1" = -t ]; then
    printf '%s\n' "$profiles" | awk '{print $1 ":" $2}'; exit 0
fi
if [ "$1" = -g ]; then
    line=$(printf '%s\n' "$profiles" | awk -v u="$6" '$1 == u')
    set -- $1 $2 $line
    case $2 in
        802-1x.eap) [ "$5" = - ] || echo "$5" ;;
        802-1x.password-flags) [ "$6" = - ] || echo "$6 (x)" ;;
        connection.id) echo "$7" ;;
    esac
    exit 0
fi
echo "nmcli $*" >>"$LOG"
EOF
cat >"$tmp/bin/nm-connection-editor" <<'EOF'
#!/bin/bash
echo "editor $*" >>"$LOG"
EOF
cat >"$tmp/bin/python3" <<'EOF'
#!/bin/bash
echo "installer $*" >>"$LOG"
EOF
chmod +x "$tmp/bin"/*
export LOG=$log PATH=$tmp/bin:$PATH WAYLAND_DISPLAY=wayland-1

fail=0
check() { # name, expected log
    if [ "$(cat "$log" 2>/dev/null)" != "$2" ]; then
        echo "FAIL $1"; echo "--- expected"; echo "$2"; echo "--- got"; cat "$log"; fail=1
    fi
    rm -f "$log"
}

echo cat.py >"$tmp/cat.py"
"$script" "$tmp/cat.py" --silent >/dev/null
check "installer + fix + editor" "installer $tmp/cat.py --silent
nmcli connection modify uuid u-edu 802-1x.password-flags 0
nmcli connection modify uuid u-thws 802-1x.password-flags 0
nmcli connection modify uuid u-ask 802-1x.password-flags 0
editor --edit=u-edu
editor --edit=u-thws
editor --edit=u-ask"

"$script" "$tmp/missing.py" >/dev/null 2>&1 && { echo "FAIL missing installer accepted"; fail=1; }
check "missing installer changes nothing" ""

WAYLAND_DISPLAY= "$script" >/dev/null
check "fix only, no session: no editor" "nmcli connection modify uuid u-edu 802-1x.password-flags 0
nmcli connection modify uuid u-thws 802-1x.password-flags 0
nmcli connection modify uuid u-ask 802-1x.password-flags 0"

exit $fail
