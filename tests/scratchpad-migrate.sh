#!/usr/bin/env bash
# Regression test for roles/quickshell/files/scratchpad-migrate.py (the
# one-time move of the scratchpad's four .txt notes into scratchpad.md):
# migrate, adopt, conflict (nothing written), marker, --check, and the file
# format shared with ScratchpadWindow.qml (fixture = tests/qml-logic.qml's).
# Safe anywhere: temporary directories only. Run by tests/run.sh.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
m="$repo/roles/quickshell/files/scratchpad-migrate.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { if ! eval "$2"; then echo "FAIL $1"; fail=1; fi; }
setup() { rm -rf "$tmp/old" "$tmp/new"; mkdir -p "$tmp/old" "$tmp/new"; }
run() { out=$(python3 "$m" "$tmp/old" "$tmp/new/scratchpad.md" "$@" 2>"$tmp/err"); rc=$?; }

# The shared format (same fixture as the QML test).
want=$'<!-- scratchpad note 1 -->\nhello\n<!-- scratchpad note 2 -->\n\n<!-- scratchpad note 3 -->\na\nb\n\n<!-- scratchpad note 4 -->\n\n'

setup; printf 'hello' > "$tmp/old/1.txt"; printf 'a\nb\n' > "$tmp/old/3.txt"; : > "$tmp/old/4.txt"
run --check
ok "check: says migrated, writes nothing" '[ "$out" = migrated ] && [ ! -e "$tmp/new/scratchpad.md" ] && [ ! -e "$tmp/old/MIGRATED" ]'
run
ok "migrate: file in the shared format" '[ "$out" = migrated ] && [ "$(cat "$tmp/new/scratchpad.md"; echo x)" = "${want}x" ]'
ok "migrate: old files untouched + marker" '[ "$(cat "$tmp/old/1.txt")" = hello ] && [ -e "$tmp/old/MIGRATED" ]'
ok "migrate: private file" '[ "$(stat -c %a "$tmp/new/scratchpad.md")" = 600 ]'
run
ok "second run: unchanged" '[ "$out" = unchanged ] && [ "$rc" -eq 0 ]'

setup; printf 'hello' > "$tmp/old/1.txt"; printf 'a\nb\n' > "$tmp/old/3.txt"; printf '%s' "$want" > "$tmp/new/scratchpad.md"
run
ok "same notes already there: adopted (marker only)" '[ "$out" = adopted ] && [ -e "$tmp/old/MIGRATED" ]'

setup; printf 'old note' > "$tmp/old/1.txt"; printf 'other\n' > "$tmp/new/scratchpad.md"
run
ok "conflict: exit 3, ACTION REQUIRED" '[ "$rc" -eq 3 ] && [ "$out" = conflict ] && grep -q "ACTION REQUIRED" "$tmp/err"'
ok "conflict: nothing written" '[ "$(cat "$tmp/new/scratchpad.md")" = other ] && [ ! -e "$tmp/old/MIGRATED" ] && [ "$(cat "$tmp/old/1.txt")" = "old note" ]'

setup
run
ok "no old notes: unchanged, no file created" '[ "$out" = unchanged ] && [ ! -e "$tmp/new/scratchpad.md" ]'

# parse == the QML rules (round trip, text above the first marker, no markers)
ok "parse round trip" '[ "$(python3 -c "
import importlib.util, sys
s = importlib.util.spec_from_file_location(\"m\", \"$m\"); mod = importlib.util.module_from_spec(s); s.loader.exec_module(mod)
n = [\"x\", \"\", \"a\nb\n\", \"\"]
print(mod.parse(mod.compose(n)) == n, mod.parse(\"top\n<!-- scratchpad note 2 -->\nb\n\") == [\"top\", \"b\", \"\", \"\"], mod.parse(\"plain\ntext\n\") == [\"plain\ntext\", \"\", \"\", \"\"])
")" = "True True True" ]'

[ "$fail" -eq 0 ] && echo "scratchpad-migrate: all checks passed"
exit "$fail"
