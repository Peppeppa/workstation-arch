#!/usr/bin/env bash
# scripts/add-ssh-key.sh against a temporary HOME (the real ~/.ssh is never
# read or changed): first run, repeat, duplicates with another comment or
# options, existing keys kept, no truncation, permissions, refusals.
set -uo pipefail
cd "$(dirname "$0")/.."
S=$PWD/scripts/add-ssh-key.sh
KEY=$(sed -n "s/^KEY='\(.*\)'$/\1/p" "$S")
BLOB=${KEY#* }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" -eq 0 ]; then :; else echo "FAIL $1"; fail=1; fi; }
run() { HOME=$1 bash "$S" >"$tmp/out" 2>&1; }
count() { grep -c -- "$BLOB" "$1"; }
mode() { stat -c %a -- "$1"; }

# 1. first run: no ~/.ssh at all
h=$tmp/h1; mkdir "$h"
run "$h"; check "first run exit 0" $?
grep -q "added" "$tmp/out"; check "first run says added" $?
[ "$(mode "$h/.ssh")" = 700 ]; check "~/.ssh 700 (got $(mode "$h/.ssh"))" $?
[ "$(mode "$h/.ssh/authorized_keys")" = 600 ]; check "authorized_keys 600" $?
[ "$(cat "$h/.ssh/authorized_keys")" = "$KEY" ]; check "exactly the key" $?
[ "$(stat -c %u "$h/.ssh/authorized_keys")" = "$(id -u)" ]; check "owned by the user" $?

# 2. repeat: unchanged
before=$(sha256sum < "$h/.ssh/authorized_keys")
run "$h"; check "repeat exit 0" $?
grep -q "already present" "$tmp/out"; check "repeat says already present" $?
[ "$(sha256sum < "$h/.ssh/authorized_keys")" = "$before" ]; check "repeat leaves the file unchanged" $?

# 3. same key, other comment / with options -> no duplicate, others kept
h=$tmp/h3; mkdir -p "$h/.ssh"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherKeyOtherKeyOtherKeyOtherKeyOther other@host\n%s laptop-comment\n' "$KEY" > "$h/.ssh/authorized_keys"
cp "$h/.ssh/authorized_keys" "$tmp/orig3"
run "$h"; check "other comment: exit 0" $?
grep -q "already present" "$tmp/out"; check "other comment: detected" $?
cmp -s "$h/.ssh/authorized_keys" "$tmp/orig3"; check "other comment: file unchanged" $?
h=$tmp/h4; mkdir -p "$h/.ssh"
printf '# my keys\nfrom="10.0.0.0/8",no-agent-forwarding %s\n' "$KEY" > "$h/.ssh/authorized_keys"
run "$h"; grep -q "already present" "$tmp/out"; check "options in front: detected" $?
[ "$(count "$h/.ssh/authorized_keys")" = 1 ]; check "options in front: still one line" $?
# commented-out key does not count
h=$tmp/h5; mkdir -p "$h/.ssh"; printf '# %s\n' "$KEY" > "$h/.ssh/authorized_keys"
run "$h"; grep -q "added" "$tmp/out"; check "commented-out key: added" $?

# 4. existing keys kept, no newline at the end, permissions fixed
h=$tmp/h6; mkdir -p "$h/.ssh"; chmod 755 "$h/.ssh"
printf 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQOther other' > "$h/.ssh/authorized_keys"; chmod 644 "$h/.ssh/authorized_keys"
run "$h"; check "append: exit 0" $?
[ "$(sed -n 1p "$h/.ssh/authorized_keys")" = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQOther other" ]; check "append: existing line intact" $?
[ "$(sed -n 2p "$h/.ssh/authorized_keys")" = "$KEY" ]; check "append: key on its own line" $?
[ "$(wc -l < "$h/.ssh/authorized_keys")" = 2 ]; check "append: two lines" $?
[ "$(mode "$h/.ssh")" = 700 ] && [ "$(mode "$h/.ssh/authorized_keys")" = 600 ]; check "append: modes fixed to 700/600" $?
run "$h"; [ "$(count "$h/.ssh/authorized_keys")" = 1 ]; check "append: repeat adds nothing" $?

# 5. refusals change nothing
h=$tmp/h7; mkdir -p "$h/.ssh" "$tmp/elsewhere"; : > "$tmp/elsewhere/keys"; ln -s "$tmp/elsewhere/keys" "$h/.ssh/authorized_keys"
run "$h"; [ $? -eq 1 ]; check "symlinked authorized_keys: refused" $?
[ ! -s "$tmp/elsewhere/keys" ]; check "symlink target untouched" $?
mkdir -p "$tmp/fakebin"; printf '#!/bin/sh\necho 0\n' > "$tmp/fakebin/id"; chmod +x "$tmp/fakebin/id"
h=$tmp/h8; mkdir "$h"
HOME=$h PATH="$tmp/fakebin:$PATH" bash "$S" >"$tmp/out" 2>&1; [ $? -eq 1 ]; check "root: refused" $?
grep -q "not root" "$tmp/out"; check "root: says why" $?
[ ! -e "$h/.ssh" ]; check "root: nothing created" $?
# a broken key in the script is refused before anything is touched
sed "s|^KEY='.*'$|KEY='ssh-ed25519 AAAAnot-a-key'|" "$S" > "$tmp/bad.sh"
h=$tmp/h9; mkdir "$h"; HOME=$h bash "$tmp/bad.sh" >"$tmp/out" 2>&1; [ $? -eq 1 ]; check "invalid key: refused" $?
[ ! -e "$h/.ssh" ]; check "invalid key: nothing created" $?

[ $fail -eq 0 ] && echo "add-ssh-key: all checks passed"
exit $fail
