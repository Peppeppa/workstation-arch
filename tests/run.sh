#!/usr/bin/env bash
# The repository's permanent checks - fast (~10 s), deterministic, and safe
# on any machine (nothing touches a live session; see each test's header):
#   1. syntax: bootstrap.sh, shell helpers, playbook, inventory, every YAML file
#   2. tests/theme-helper.sh  - the `theme` helper against a copy of themes/
#   3. tests/qml-logic.qml    - pure logic cut out of the shipped QML (qml6)
# Exit 0 = everything passed. Live-system invariants are repo-healthcheck's
# job (on the provisioned machine), not this script's.

set -u
cd "$(dirname "$0")/.."
fail=0
step() { # name, command...
    local name=$1; shift
    if out=$("$@" 2>&1); then
        echo "ok    $name"
    else
        echo "FAIL  $name"; printf '%s\n' "$out" | tail -15 | sed 's/^/      /'; fail=1
    fi
}

step "bash -n bootstrap.sh" bash -n bootstrap.sh
for f in roles/*/files/*.sh; do step "sh -n $f" sh -n "$f"; done
step "ansible-playbook --syntax-check local.yml" ansible-playbook --syntax-check local.yml </dev/null
step "ansible-inventory --list" ansible-inventory --list </dev/null
step "YAML parses" python3 -c '
import sys, yaml
for f in sys.argv[1:]:
    with open(f) as h:
        yaml.safe_load(h)
' $(git ls-files '*.yml' '*.yaml')
step "tests/theme-helper.sh" bash tests/theme-helper.sh
if command -v qml6 >/dev/null; then
    step "tests/qml-logic.qml" env QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 60 qml6 tests/qml-logic.qml
else
    echo "skip  tests/qml-logic.qml (qml6 not installed - comes with quickshell's qt6-declarative)"
fi

echo
[ $fail -eq 0 ] && echo "all checks passed" || echo "CHECKS FAILED"
exit $fail
