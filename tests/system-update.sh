#!/usr/bin/env bash
# Regression test for the updater's shell side (roles/recovery):
#   system-update            snapshot failure -> exit 3 + no pacman, --no-snapshot,
#                            preflight/lock failures never overridden, --ui reports,
#                            one run at a time
#   snapshot-create          slot helper: label validation, argv passed through untouched (no
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
sed -e "s#/usr/local/lib/workstation/snapshot-boot#$tmp/stub/snapshot-boot#g" \
    "$repo/roles/recovery/files/snapshot-create" > "$tmp/snapshot-create"
# the same file, installed under its second name (polkit: password)
cp "$tmp/snapshot-create" "$tmp/snapshot-delete"; chmod +x "$tmp/snapshot-delete"
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
    post) [ -z "\${POST_FAIL:-}" ] || { echo "system-update-root: \$POST_FAIL" >&2; exit 1; }; echo ok ;;
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
ok "update: full -Syu without the Y/n question, nothing else" 'grep -qx "pacman -Syu --noconfirm" "$log"'
ok "update: ui finished 0 42" 'grep -qx "qs ipc --any-display call updates finished 0 42" "$log"'
ok "update: result names the snapshot" 'grep -q "Pre-update snapshot: 42" <<<"$out"'

# 1b. pacman done, but the recovery-point step after it fails: the boot image
#     check and the health check must still run, with a result (Bug Hunt v1)
POST_FAIL="snapper modify failed" run --ui
ok "post fails: boot image check still runs" 'grep -q "^root ukicheck" "$log"'
ok "post fails: health check after the update still runs" '[ "$(grep -c "^root " "$log")" -ge 4 ]'
ok "post fails: a RESULT line is printed" 'grep -q "^RESULT:" <<<"$out"'
ok "post fails: the failure is named" 'grep -q "recovery point" <<<"$out" && grep -q "snapper modify failed" <<<"$out"'
ok "post fails: non-zero exit" '[ "$rc" -ne 0 ]'
ok "post fails: ui finished non-zero" 'grep -qE "updates finished [1-9][0-9]* 42" "$log"'

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

# ---- snapshot-create (the slot helper behind the dialog) -------------------
stub id 'echo 0'
cat > "$tmp/stub/snapshot-boot" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$tmp/argv"
[ -n "\${SB_FAIL:-}" ] && { echo "snapshot-boot: \$SB_FAIL" >&2; exit 1; }
echo '{"ok": true, "slot": 1, "number": 57, "description": "x", "replaced": null, "warnings": []}'
EOF
chmod +x "$tmp/stub/snapshot-boot"

label='Vor "Install" $(touch /tmp/x) `id`; ä & | * ~'
out=$("$tmp/snapshot-create" set 1 "$label" 2>&1); rc=$?
ok "slots: special characters accepted" '[ "$rc" -eq 0 ]'
ok "slots: empty slot -> slot-set, label ONE literal argv element" '[ "$(cat "$tmp/argv")" = "$(printf "slot-set\n1\n%s" "$label")" ]'
ok "slots: JSON passed through" '[ "$(python3 -c "import json,sys; print(json.loads(sys.argv[1])[\"number\"])" "$out")" = 57 ]'
# Security Hardening v1.1 (S3-B): snapshot-create (no password) only
# creates; overwrite and delete remove a snapshot -> only as snapshot-delete
# (own polkit action, administrator password). Enforced here, not in QML.
for args in "set 2 Neu 35" "delete 3 35" "replace 2 35 Neu"; do
    rm -f "$tmp/argv"
    # shellcheck disable=SC2086
    "$tmp/snapshot-create" $args >/dev/null 2>&1; rc=$?
    ok "slots: snapshot-create refuses '$args' (deletes a snapshot)" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
done
"$tmp/snapshot-delete" replace 2 35 "Neu" >/dev/null 2>&1
ok "slots: snapshot-delete replace = slot-set --replace the confirmed number" '[ "$(tr "\n" " " < "$tmp/argv")" = "slot-set 2 Neu --replace 35 " ]'
"$tmp/snapshot-delete" delete 3 35 >/dev/null 2>&1
ok "slots: snapshot-delete delete passes slot + confirmed number" '[ "$(tr "\n" " " < "$tmp/argv")" = "slot-delete 3 35 " ]'
"$tmp/snapshot-delete" replace 1 35 "$label" >/dev/null 2>&1
ok "slots: replace label stays ONE literal argv element" '[ "$(cat "$tmp/argv")" = "$(printf "slot-set\n1\n%s\n--replace\n35" "$label")" ]'
for args in "set 1 x" "delete 1" "delete 1 x" "delete 4 3" "delete 1 3 4" "replace 1 x y" "replace 1 3" "replace 0 3 y" "replace 1 -3 y" ""; do
    rm -f "$tmp/argv"
    # shellcheck disable=SC2086
    "$tmp/snapshot-delete" $args >/dev/null 2>&1; rc=$?
    ok "slots: snapshot-delete rejects '$args'" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
done
for bad in "" "-x" "$(printf 'a\nb')" "$(printf '%0101d' 0)"; do
    rm -f "$tmp/argv"
    "$tmp/snapshot-delete" replace 1 35 "$bad" >/dev/null 2>&1; rc=$?
    ok "slots: replace rejects label $(printf '%q' "$bad" | cut -c1-20)" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
done
cp "$tmp/snapshot-create" "$tmp/snapshot-other"; rm -f "$tmp/argv"
"$tmp/snapshot-other" set 1 x >/dev/null 2>&1; rc=$?
ok "slots: any other installed name does nothing" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
for bad in "" "-x" "--known-good" "$(printf 'a\nb')" "$(printf 'a\tb')" "$(printf '%0101d' 0)"; do
    rm -f "$tmp/argv"
    "$tmp/snapshot-create" set 1 "$bad" >/dev/null 2>&1; rc=$?
    ok "slots: rejects label $(printf '%q' "$bad" | cut -c1-20)" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
done
for args in "set 4 x" "set 0 x" "set 1 x abc" "set 1" "create 1 x" ""; do
    rm -f "$tmp/argv"
    # shellcheck disable=SC2086
    "$tmp/snapshot-create" $args >/dev/null 2>&1; rc=$?
    ok "slots: rejects '$args'" '[ "$rc" -eq 2 ] && [ ! -e "$tmp/argv" ]'
done
out=$(SB_FAIL="slot 1 holds snapshot 36 - overwrite it only after confirming that one" "$tmp/snapshot-delete" replace 1 35 x 2>&1); rc=$?
ok "slots: failure is an error, with the reason" '[ "$rc" -eq 1 ] && grep -q "holds snapshot 36" <<<"$out"'
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
