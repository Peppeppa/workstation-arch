#!/usr/bin/env bash
# Regression test for the automatic pre-transaction snapshots
# (roles/recovery: recovery-lib.sh auto_snapshot/prune_auto, the pacman
# hook's pre-transaction-snapshot, recovery-baseline).
#
# Safe anywhere: the scripts run against a stub `snapper` (a JSON fixture
# for `--jsonout list`, create/delete only logged), stub `findmnt`/`id`,
# and a temporary marker directory - no real snapshot is read or touched.
# Run by tests/run.sh.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" -ne 0 ]; then echo "FAIL $1"; fail=1; fi; }

mkdir -p "$tmp/stub" "$tmp/lib" "$tmp/run"
# The scripts with their fixed paths pointed into $tmp.
for f in recovery-lib.sh pre-transaction-snapshot recovery-baseline; do
    sed -e "s#/usr/local/lib/workstation/#$tmp/lib/#g" -e "s#/run/workstation-recovery#$tmp/run#g" \
        "$repo/roles/recovery/files/$f" > "$tmp/lib/$f"
    chmod +x "$tmp/lib/$f"
done

# Fixture: what `snapper --jsonout -c root list` returns.
fixture() { # numbers of the auto class...
    python3 - "$@" > "$tmp/list.json" <<'EOF'
import json, sys
auto = [int(a) for a in sys.argv[1:]]
snaps = [{"number": 0, "type": "single", "description": "current", "userdata": None, "cleanup": ""},
         {"number": 1, "type": "single", "description": "known-good v1", "userdata": {"important": "yes"}, "cleanup": "number"},
         {"number": 14, "type": "pre", "description": "system-update", "userdata": {"update": "1"}, "cleanup": "number"},
         {"number": 15, "type": "post", "description": "system-update", "userdata": None, "cleanup": "number"},
         {"number": 22, "type": "pre", "description": "old slot", "userdata": {"slot": "previous-update", "update": "2"}, "cleanup": ""},
         {"number": 26, "type": "single", "description": "known-good v2", "userdata": {"important": "yes", "slot": "known-good"}, "cleanup": ""},
         {"number": 27, "type": "single", "description": "manual", "userdata": {"important": "yes"}, "cleanup": "number"}]
for n in auto:
    u = {"auto": "pre-transaction"}
    if n == 31: u["slot"] = "previous-update"     # an auto snapshot a recovery slot still uses
    snaps.append({"number": n, "type": "single", "description": "pacman", "userdata": u, "cleanup": ""})
print(json.dumps({"root": snaps}))
EOF
}

cat > "$tmp/stub/snapper" <<EOF
#!/bin/bash
# stub: list -> fixture; create -> log + next number; delete -> log
args="\$*"
case "\$args" in
    *--jsonout*list*) cat "$tmp/list.json" ;;
    *" create "*) echo "create \$args" >> "$tmp/log"; [ -f "$tmp/create-fails" ] && exit 1; echo 99 ;;
    *" delete "*) echo "delete \${args##*delete }" >> "$tmp/log" ;;
    *) echo "unexpected: \$args" >> "$tmp/log"; exit 3 ;;
esac
EOF
printf '#!/bin/sh\necho "rw,subvol=/@"\n' > "$tmp/stub/findmnt"   # booted from @ (root_subvol)
printf '#!/bin/sh\necho 0\n' > "$tmp/stub/id"                     # need_root
chmod +x "$tmp/stub/"*
export PATH="$tmp/stub:$PATH"

prunable() { bash -c ". $tmp/lib/recovery-lib.sh; auto_prunable" | tr '\n' ' '; }

# ---- retention: newest 3 of the class; nothing outside it -------------------
fixture 30 31 32 33 34
got=$(prunable); [ "$got" = "30 " ]; check "prune: 5 auto (31 slot-pinned) -> only 30 goes, slot-pinned 31 stays: got '$got'" $?
fixture 40 41 42
[ "$(prunable)" = "" ]; check "prune: exactly 3 auto -> nothing" $?
fixture
[ "$(prunable)" = "" ]; check "prune: no auto snapshots -> nothing (baseline/manual/pairs untouched)" $?
fixture 50 51 52 53 54 55 56
got=$(prunable); [ "$got" = "53 52 51 50 " ]; check "prune: 7 auto -> the 4 oldest, newest first by number: got '$got'" $?

# ---- the hook: one create per transaction, classified, then prune ------------
fixture 60 61 62 63
: > "$tmp/log"
printf 'less\nnano\nvim\nzsh\n' | "$tmp/lib/pre-transaction-snapshot" > "$tmp/out" 2>&1
check "hook: exit 0" $?
[ "$(grep -c '^create' "$tmp/log")" = 1 ]; check "hook: exactly one snapshot for a 4-package transaction" $?
grep -q -- '--type single' "$tmp/log" && grep -q -- '--cleanup-algorithm  --description' "$tmp/log"
check "hook: single snapshot, own cleanup (not snapper's number limit)" $?
grep -q 'auto=pre-transaction' "$tmp/log"; check "hook: classified auto=pre-transaction" $?
grep -q 'pacman: 4 packages (less, nano, vim, ...)' "$tmp/log"; check "hook: description names the transaction" $?
grep -q '^delete 60$' "$tmp/log"; check "hook: prunes the class to 3 (fixture already had 4)" $?

# Every target count (the description must never end the hook under set -e).
for t in "less" "less\nwhich" "a\nb\nc"; do
    fixture; : > "$tmp/log"
    printf "$t\n" | "$tmp/lib/pre-transaction-snapshot" > "$tmp/out" 2>&1
    rc=$?; creates=$(grep -c '^create' "$tmp/log"); last=$(tail -1 "$tmp/out"); n=$(printf "$t\n" | wc -l)
    [ $rc -eq 0 ] && [ "$creates" = 1 ]; ok=$?
    check "hook: $n target(s) -> exit 0, one snapshot (rc $rc, creates $creates: $last)" $ok
done
grep -q 'pacman: 3 packages (a, b, c)' "$tmp/log"; check "hook: 3 targets described without '...'" $?

# ---- skip marker: fresh = skip once, stale = snapshot anyway -----------------
: > "$tmp/log"; echo "system-update took snapshot 77" > "$tmp/run/skip-pre-snapshot"
printf 'less\n' | "$tmp/lib/pre-transaction-snapshot" > "$tmp/out" 2>&1
[ ! -s "$tmp/log" ] && [ ! -e "$tmp/run/skip-pre-snapshot" ]; check "skip marker: fresh -> no snapshot, marker consumed" $?
: > "$tmp/log"; echo old > "$tmp/run/skip-pre-snapshot"; touch -d '2 hours ago' "$tmp/run/skip-pre-snapshot"
printf 'less\n' | "$tmp/lib/pre-transaction-snapshot" > "$tmp/out" 2>&1
[ "$(grep -c '^create' "$tmp/log")" = 1 ]; check "skip marker: stale (2 h) -> snapshot taken anyway" $?

# ---- a failed snapshot aborts the transaction -------------------------------
: > "$tmp/log"; touch "$tmp/create-fails"
printf 'less\n' | "$tmp/lib/pre-transaction-snapshot" > "$tmp/out" 2>&1
[ $? -ne 0 ]; check "snapshot failure -> non-zero exit (pacman AbortOnFail)" $?
grep -q 'ABORTED' "$tmp/out"; check "snapshot failure -> says the transaction was aborted" $?
rm -f "$tmp/create-fails"

# ---- recovery boot: no snapshot, transaction goes on -------------------------
: > "$tmp/log"; printf '#!/bin/sh\necho "rw,subvol=/@recovery/known-good"\n' > "$tmp/stub/findmnt"
printf 'less\n' | "$tmp/lib/pre-transaction-snapshot" > "$tmp/out" 2>&1
[ $? -eq 0 ] && [ ! -s "$tmp/log" ]; check "recovery boot: no snapshot, exit 0" $?
printf '#!/bin/sh\necho "rw,subvol=/@"\n' > "$tmp/stub/findmnt"

# ---- baseline: known-good slot present -> nothing; none -> created once ------
fixture 70
: > "$tmp/log"
[ "$("$tmp/lib/recovery-baseline")" = "present 26" ] && [ ! -s "$tmp/log" ]; check "baseline: known-good slot counts as the baseline" $?
python3 - "$tmp/list.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["root"] = [s for s in d["root"] if (s.get("userdata") or {}).get("slot") != "known-good"]
json.dump(d, open(sys.argv[1], "w"))
EOF
out=$("$tmp/lib/recovery-baseline"); [ "$out" = "created 99" ] && grep -q 'baseline=yes' "$tmp/log"
rc=$?; check "baseline: none -> one pinned baseline=yes snapshot ($out)" $rc

[ $fail -eq 0 ] && echo "recovery-snapshots: all checks passed"
exit $fail
