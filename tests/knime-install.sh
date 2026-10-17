#!/usr/bin/env bash
# knime-install (roles/apps) against fake archives in a temporary HOME -
# nothing is downloaded, nothing outside the temporary directory changes.
# Checks: install layout (opt dir, symlink, wrapper, launcher entry), a second
# run changes nothing, a newer version switches the symlink and keeps the old
# one, foreign files are not overwritten, wrong names / two top directories /
# ../ paths / a missing launcher are refused before anything is written.
set -u
cd "$(dirname "$0")/.."
script=$PWD/roles/apps/files/knime-install
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home
mkdir -p "$HOME" "$tmp/src"
fail=0
bad() { echo "FAIL $*"; fail=1; }

# KNIME archives have one top directory and no "./" prefix - built the same way.
# mkarchive version name [setup-function]
mkarchive() {
    local v=$1 name=$2 d=$tmp/src/$1
    rm -rf "$d"; mkdir -p "$d/knime_$v/plugins"
    printf '#!/bin/sh\necho knime %s "$@"\n' "$v" >"$d/knime_$v/knime"
    chmod +x "$d/knime_$v/knime"
    echo icon >"$d/knime_$v/icon.xpm"
    if [ $# -ge 3 ]; then "$3" "$d"; fi
    (cd "$d" && tar -czf "$tmp/$name" -- *)
}

mkarchive 5.12.0 knime_5.12.0.linux.gtk.x86_64.tar.gz
"$script" "$tmp/knime_5.12.0.linux.gtk.x86_64.tar.gz" >/dev/null || bad "install failed"
[ "$(readlink "$HOME/.local/opt/knime")" = knime_5.12.0 ] || bad "symlink"
# No xwayland-scale in the temporary HOME -> scale 1, appended to the vmargs.
[ "$("$HOME/.local/bin/knime" x)" = "knime 5.12.0 x --launcher.appendVmargs -vmargs -Dchromium.args=--force-device-scale-factor=1" ] \
    || bad "wrapper runs the launcher"
grep -q 'backend=${KNIME_GDK_BACKEND:-x11}' "$HOME/.local/bin/knime" || bad "wrapper XWayland default"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho 1.25\n' >"$HOME/.local/bin/xwayland-scale"; chmod +x "$HOME/.local/bin/xwayland-scale"
[ "$("$HOME/.local/bin/knime")" = "knime 5.12.0 --launcher.appendVmargs -vmargs -Dchromium.args=--force-device-scale-factor=1.25" ] \
    || bad "wrapper passes the monitor scale"
rm "$HOME/.local/bin/xwayland-scale"
desktop=$HOME/.local/share/applications/workstation-knime.desktop
grep -qx "Exec=$HOME/.local/bin/knime" "$desktop" || bad "desktop Exec"
grep -qx "Icon=$HOME/.local/opt/knime/icon.xpm" "$desktop" || bad "desktop Icon"
command -v desktop-file-validate >/dev/null && { desktop-file-validate "$desktop" || bad "desktop entry invalid"; }

before=$(cd "$HOME" && find . -printf '%p %s %T@\n' | sort)
"$script" "$tmp/knime_5.12.0.linux.gtk.x86_64.tar.gz" >/dev/null || bad "second run failed"
after=$(cd "$HOME" && find . -printf '%p %s %T@\n' | sort)
[ "$before" = "$after" ] || bad "second run changed files"

mkarchive 5.13.0 knime_5.13.0.linux.gtk.x86_64.tar.gz
"$script" "$tmp/knime_5.13.0.linux.gtk.x86_64.tar.gz" >/dev/null || bad "update failed"
[ "$(readlink "$HOME/.local/opt/knime")" = knime_5.13.0 ] || bad "update symlink"
[ -x "$HOME/.local/opt/knime_5.12.0/knime" ] || bad "old version kept"

echo "mine" >"$HOME/.local/bin/knime"
"$script" "$tmp/knime_5.13.0.linux.gtk.x86_64.tar.gz" >/dev/null 2>&1 || bad "run with foreign wrapper failed"
[ "$(cat "$HOME/.local/bin/knime")" = mine ] || bad "foreign wrapper overwritten"

refuse() { # description, archive path
    local snap; snap=$(cd "$HOME" && find . | sort)
    "$script" "$2" >/dev/null 2>&1 && bad "accepted: $1"
    [ "$(cd "$HOME" && find . | sort)" = "$snap" ] || bad "wrote something: $1"
}
cp "$tmp/knime_5.13.0.linux.gtk.x86_64.tar.gz" "$tmp/other.tar.gz"
refuse "wrong file name" "$tmp/other.tar.gz"
two() { mkdir "$1/second"; }
mkarchive 6.0.0 knime_6.0.0.linux.gtk.x86_64.tar.gz two
refuse "two top directories" "$tmp/knime_6.0.0.linux.gtk.x86_64.tar.gz"
nolauncher() { rm "$1"/knime_*/knime; }
mkarchive 6.0.1 knime_6.0.1.linux.gtk.x86_64.tar.gz nolauncher
refuse "no launcher" "$tmp/knime_6.0.1.linux.gtk.x86_64.tar.gz"
python3 - "$tmp/knime_6.0.2.linux.gtk.x86_64.tar.gz" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as t:
    for name in ("knime_6.0.2/knime", "knime_6.0.2/../../escape"):
        data = b"x\n"; info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o755
        t.addfile(info, io.BytesIO(data))
PY
refuse "../ path" "$tmp/knime_6.0.2.linux.gtk.x86_64.tar.gz"
refuse "missing file" "$tmp/knime_9.9.9.linux.gtk.x86_64.tar.gz"

exit $fail
