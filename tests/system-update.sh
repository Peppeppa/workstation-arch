#!/usr/bin/env bash
# Regression test for the updater's shell side (roles/recovery):
#   system-update            snapshot failure -> exit 3 + no pacman, --no-snapshot,
#                            preflight/lock failures never overridden, --ui reports,
#                            one run at a time
#   snapshot-create          label validation, argv passed through untouched (no
#                            shell), JSON result
#   workstation-checkupdates ok / none / offline / error
#
# Safe anywhere: every privileged or system command is a stub in a temporary
# PATH (sudo, the root half, pacman, snapper, system-snapshot, checkupdates,
# nmcli, qs, repo-healthcheck) - nothing is updated, no snapshot is taken.
# Run by tests/run.sh.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { if ! eval "$2"; then echo "FAIL $1"; fail=1; fi; }

mkdir -p "$tmp/stub" "$tmp/lib" "$tmp/run"
log="$tmp/log"
sed -e "s#/usr/local/lib/workstation/system-update-root#$tmp/lib/system-update-root#g" \
    "$repo/roles/recovery/files/system-update" > "$tmp/system-update"
sed -e "s#/usr/local/bin/system-snapshot#$tmp/stub/system-snapshot#g" \
    "$repo/roles/recovery/files/snapshot-create" > "$tmp/snapshot-create"
cp "$repo/roles/recovery/files/workstation-checkupdates" "$tmp/workstation-checkupdates"
chmod +x "$tmp/system-update" "$tmp/snapshot-create" "$tmp/workstation-checkupdates"

stub() { # name, body
    printf '#!/bin/bash\n%s\n' "$2" > "$tmp/stub/$1"
    chmod +x "$tmp/stub/$1"
}
# sudo: -v ok, everything else runs as is (pacman is a stub too).
stub sudo 'if [ "$1" = -v ]; then exit 0; fi; exec "$@"'
stub pacman 'echo "pacman $*" >> '"$log"'; exit ${PACMAN_RC:-0}'
stub repo-healthcheck 'exit 0'
stub qs 'echo "qs $*" >> '"$log"
stub logger 'echo "logger $*" >> '"$log"
cat > "$tmp/lib/system-update-root" <<EOF
#!/bin/bash
echo "root \$*" >> "$log"
case \$1 in
    preflight) [ -z "\${PREFLIGHT_FAIL:-}" ] || { echo "system-update-root: \$PREFLIGHT_FAIL" >&2; exit 1; }; echo ok ;;
    pre) [ -z "\${SNAP_FAIL:-}" ] || { echo "snapper: \$SNAP_FAIL" >&2; exit 1; }; echo 42 ;;
    rebootneeded) exit 1 ;;
    *) echo ok ;;
esac
EOF
chmod +x "$tmp/lib/system-update-root"
export PATH="$tmp/stub:$PATH" XDG_RUNTIME_DIR="$tmp/run"

run() { # args... -> $rc, $out; log fresh
    : > "$log"
    out=$("$tmp/system-update" "$@" </dev/null 2>&1)
    rc=$?
}

# 1. normal run: snapshot, then pacman -Syu, ui reports finished 0 42
run --ui
ok "update: exit 0" '[ "$rc" -eq 0 ]'
ok "update: snapshot before pacman" '[ "$(grep -nE "^root pre |^pacman" "$log" | cut -d: -f2 | cut -c1-8 | tr "\n" " ")" = "root pre pacman - " ]'
ok "update: full -Syu, nothing else" 'grep -qx "pacman -Syu" "$log"'
ok "update: ui finished 0 42" 'grep -qx "qs ipc --any-display call updates finished 0 42" "$log"'
ok "update: result names the snapshot" 'grep -q "Pre-update snapshot: 42" <<<"$out"'

# 2. snapshot fails: exit 3, pacman never runs, ui snapshotFailed with the reason
SNAP_FAIL="no space left" run --ui
ok "snapshot fail: exit 3" '[ "$rc" -eq 3 ]'
ok "snapshot fail: no pacman" '! grep -q "^pacman" "$log"'
ok "snapshot fail: ui snapshotFailed + reason" 'grep -qx "qs ipc --any-display call updates snapshotFailed snapper: no space left" "$log"'
ok "snapshot fail: no finished report" '! grep -q "updates finished" "$log"'
ok "snapshot fail: says nothing was updated" 'grep -q "nothing was updated" <<<"$out"'

# 3. --no-snapshot: no pre step, the hook is told to skip, pacman runs, result says so
run --ui --no-snapshot
ok "no-snapshot: exit 0" '[ "$rc" -eq 0 ]'
ok "no-snapshot: no pre step" '! grep -q "^root pre " "$log"'
ok "no-snapshot: hook skip requested before pacman" '[ "$(grep -nE "^root skipsnapshot|^pacman" "$log" | cut -d: -f2 | cut -c1-9 | tr "\n" " ")" = "root skip pacman -S " ]'
ok "no-snapshot: result says no snapshot" 'grep -q "NO new pre-update snapshot" <<<"$out"'
ok "no-snapshot: ui finished 0 none" 'grep -qx "qs ipc --any-display call updates finished 0 none" "$log"'

# 4. --no-snapshot never overrides anything else: preflight (pacman lock) stops it
PREFLIGHT_FAIL="pacman is running (or /var/lib/pacman/db.lck is stale)" run --ui --no-snapshot
ok "lock: exit 1" '[ "$rc" -eq 1 ]'
ok "lock: no pacman, no skip" '! grep -qE "^pacman|^root skipsnapshot" "$log"'
ok "lock: reason shown" 'grep -q "db.lck" <<<"$out"'
ok "lock: ui finished 1" 'grep -qx "qs ipc --any-display call updates finished 1 none" "$log"'

# 5. sudo refused (no permission): exit 1, nothing runs
stub sudo 'if [ "$1" = -v ]; then echo "sudo: 3 incorrect password attempts" >&2; exit 1; fi; exec "$@"'
run --ui
ok "no sudo: exit 1, nothing ran" '[ "$rc" -eq 1 ] && ! grep -qE "^root|^pacman" "$log"'
stub sudo 'if [ "$1" = -v ]; then exit 0; fi; exec "$@"'

# 6. pacman fails (e.g. a conflict it cannot resolve): reported, not hidden
PACMAN_RC=1 run --ui
ok "pacman fail: exit 1 + FAILED" '[ "$rc" -eq 1 ] && grep -q "pacman FAILED" <<<"$out"'

# 7. one run at a time (the lock held by another system-update)
exec 8>"$tmp/run/system-update.lock"
flock -n 8
run
ok "parallel: second run refused" '[ "$rc" -eq 1 ] && grep -q "already running" <<<"$out" && ! grep -q "^pacman" "$log"'
exec 8>&-

# 8. usage
run --bogus
ok "usage: exit 2" '[ "$rc" -eq 2 ]'

# ---- snapshot-create -------------------------------------------------------
stub id 'echo 0'
cat > "$tmp/stub/system-snapshot" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$tmp/argv"
echo "system-snapshot: snapshot 57: \$1"
EOF
chmod +x "$tmp/stub/system-snapshot"
stub snapper 'python3 -c "import json, sys; print(json.dumps({\"root\": [{\"number\": 57, \"date\": \"2026-10-10 13:00:00\", \"description\": open(sys.argv[1]).readline().rstrip(\"\\n\") + \" (repo abc)\"}]}))" '"$tmp"'/argv'

label='Vor "Install" $(touch /tmp/x) `id`; ä & | * ~'
out=$("$tmp/snapshot-create" "$label" 2>&1); rc=$?
ok "snapshot: special characters accepted" '[ "$rc" -eq 0 ]'
ok "snapshot: label passed as ONE literal argv element" '[ "$(cat "$tmp/argv")" = "$label" ]'
ok "snapshot: JSON number" '[ "$(python3 -c "import json,sys; print(json.loads(sys.argv[1])[\"number\"])" "$out")" = 57 ]'
for bad in "" "-x" "--known-good" "$(printf 'a\nb')" "$(printf 'a\tb')" "$(printf '%0101d' 0)"; do
    rm -f "$tmp/argv"
    "$tmp/snapshot-create" "$bad" >/dev/null 2>&1; rc=$?
    ok "snapshot: rejects $(printf '%q' "$bad" | cut -c1-20)" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
done
"$tmp/snapshot-create" a b >/dev/null 2>&1
ok "snapshot: exactly one argument" '[ $? -eq 2 ]'
stub system-snapshot 'echo "system-snapshot: booted from @recovery/x, not @" >&2; exit 1'
out=$("$tmp/snapshot-create" "x" 2>&1); rc=$?
ok "snapshot: failure is an error, with the reason" '[ "$rc" -eq 1 ] && grep -q "booted from" <<<"$out"'
rm -f "$tmp/stub/id"

# ---- workstation-checkupdates ---------------------------------------------
cu() { "$tmp/workstation-checkupdates" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"], len(d.get("packages", [])))'; }
stub checkupdates 'printf "linux 6.1-1 -> 6.2-1\nmesa 1:25-1 -> 1:26-1\n"; exit 0'
stub nmcli 'echo full'
ok "check: two updates" '[ "$(cu)" = "ok 2" ]'
stub checkupdates 'printf "linux 6.1-1 -> 6.2-1\n"; exit 0'
ok "check: one update" '[ "$(cu)" = "ok 1" ]'
stub checkupdates 'exit 2'
ok "check: none" '[ "$(cu)" = "ok 0" ]'
stub checkupdates 'echo "==> ERROR: Cannot fetch updates" >&2; exit 1'
ok "check: error while online" '[ "$(cu)" = "error 0" ]'
stub nmcli 'echo none'
ok "check: offline" '[ "$(cu)" = "offline 0" ]'

[ "$fail" -eq 0 ] && echo "system-update: all checks passed"
exit "$fail"
