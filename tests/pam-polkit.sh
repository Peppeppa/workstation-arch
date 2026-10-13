#!/usr/bin/env bash
# P1 regression (docs/testing/POLKIT_PAM_P1_REPORT.md): a cancelled polkit
# password dialog must not count as a failed login, a submitted wrong (or
# empty) password must. Runs the host's real PAM modules (pam_unix,
# pam_faillock) against Arch's stock system-auth (tests/fixtures) and the
# repository's /etc/pam.d/polkit-1 inside a bwrap user namespace with its
# own /etc and /run: a throwaway test user, nothing of the host's accounts,
# PAM configuration or faillock tallies is read or touched.
# "stock" = no /etc/pam.d/polkit-1, so polkit's /usr/lib/pam.d/polkit-1 is
# used (also proves that the /etc file takes precedence in "fixed").
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
fails=0
ok() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }

for tool in bwrap openssl faillock python3; do
    command -v "$tool" >/dev/null || { echo "skip  tests/pam-polkit.sh ($tool missing)"; exit 0; }
done
[ -f /usr/lib/pam.d/polkit-1 ] || { echo "skip  tests/pam-polkit.sh (no polkit vendor PAM file)"; exit 0; }
bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / true 2>/dev/null \
    || { echo "skip  tests/pam-polkit.sh (no unprivileged user namespaces)"; exit 0; }

# static: the repository stack = stock system-auth's auth section + ONE change
pam_file=$repo/roles/desktop/files/polkit-1.pam
want=$(grep -E '^-?auth' "$here/fixtures/pambase-system-auth" \
       | sed -E 's/^(auth +)\[success=1 default=bad\]( +pam_unix\.so)/\1[success=1 authtok_err=die default=bad]\2/')
ok "static: auth section = system-auth + authtok_err=die on pam_unix" '[ "$(grep -E "^-?auth" "$pam_file" | tr -s " ")" = "$(tr -s " " <<<"$want")" ]'
ok "static: exactly one line differs from system-auth" '[ "$(diff <(grep -E "^-?auth" "$here/fixtures/pambase-system-auth") <(grep -E "^-?auth" "$pam_file") | grep -c "^>")" = 1 ]'
ok "static: account/password/session = system-auth" '[ "$(grep -cE "^(account|password|session) +include +system-auth$" "$pam_file")" = 3 ]'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mk_root() { # $1 = stock|fixed
    local r=$tmp/$1
    mkdir -p "$r/etc/pam.d" "$r/etc/security" "$r/run/faillock"
    printf 'root:x:0:0::/root:/bin/bash\ntester:x:1000:1000::/tmp:/bin/bash\n' > "$r/etc/passwd"
    printf 'root:x:0:\ntester:x:1000:\n' > "$r/etc/group"
    printf 'root:!*:20000::::::\ntester:%s:20000:0:99999:7:::\n' "$(openssl passwd -6 -salt p1testsalt correct-horse)" > "$r/etc/shadow"
    printf 'passwd: files\ngroup: files\nshadow: files\n' > "$r/etc/nsswitch.conf"
    : > "$r/etc/security/faillock.conf"; : > "$r/etc/security/pam_env.conf"; : > "$r/etc/environment"
    cp "$here/fixtures/pambase-system-auth" "$r/etc/pam.d/system-auth"
    printf 'auth required pam_deny.so\naccount required pam_deny.so\npassword required pam_deny.so\nsession required pam_deny.so\n' > "$r/etc/pam.d/other"
    [ "$1" = fixed ] && cp "$pam_file" "$r/etc/pam.d/polkit-1"
    return 0
}
box() { # $1 = root, rest = command
    local r=$tmp/$1; shift
    bwrap --unshare-user --uid 0 --gid 0 --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib /lib64 \
        --symlink usr/bin /bin --symlink usr/bin /sbin --bind "$r/etc" /etc --bind "$r/run" /run --dir /var --symlink ../run /var/run \
        --proc /proc --dev /dev --tmpfs /tmp --ro-bind "$here/pam-client.py" /pam-client.py "$@"
}
auth() { box "$1" python3 /pam-client.py "${3:-polkit-1}" tester "$2" | cut -d' ' -f1; }
tally() { box "$1" faillock --user tester | tail -n +3 | grep -c .; }
reset() { rm -f "$tmp/$1/run/faillock/tester"; }
repeat() { local i; for i in $(seq "$1"); do auth "$2" "$3" >/dev/null; done; }
mk_root stock; mk_root fixed

# stock (the bug): one cancel = one failed login; three lock the account
reset stock; r=$(auth stock cancel)
ok "stock: cancel fails with AUTHTOK_ERR" '[ "$r" = AUTHTOK_ERR ]'
ok "stock: cancel counted by faillock (P1 reproduced)" '[ "$(tally stock)" = 1 ]'
repeat 2 stock cancel
ok "stock: 3 cancels -> correct password refused (locked)" '[ "$(auth stock pw:correct-horse)" != SUCCESS ]'

# fixed
reset fixed; r=$(auth fixed cancel)
ok "fixed: cancel still fails (no authentication without a password)" '[ "$r" = AUTHTOK_ERR ]'
ok "fixed: cancel NOT counted" '[ "$(tally fixed)" = 0 ]'
repeat 5 fixed cancel
ok "fixed: 6 cancels -> tally 0, correct password succeeds" '[ "$(tally fixed)" = 0 ] && [ "$(auth fixed pw:correct-horse)" = SUCCESS ]'
reset fixed
ok "fixed: wrong password -> AUTH_ERR" '[ "$(auth fixed pw:wrong)" = AUTH_ERR ]'
ok "fixed: wrong password counted" '[ "$(tally fixed)" = 1 ]'
reset fixed
ok "fixed: empty submitted password -> AUTH_ERR, counted" '[ "$(auth fixed pw:)" = AUTH_ERR ] && [ "$(tally fixed)" = 1 ]'
reset fixed; auth fixed pw:wrong >/dev/null; repeat 2 fixed cancel; auth fixed pw:wrong >/dev/null
ok "fixed: wrong, cancel, cancel, wrong -> tally 2" '[ "$(tally fixed)" = 2 ]'
auth fixed pw:correct-horse >/dev/null
ok "fixed: success resets the tally (authsucc)" '[ "$(tally fixed)" = 0 ]'
reset fixed; repeat 3 fixed pw:wrong
ok "fixed: 3 wrong passwords lock (deny=3 unchanged)" '[ "$(tally fixed)" = 3 ] && [ "$(auth fixed pw:correct-horse)" != SUCCESS ]'
r=$(auth fixed cancel)
ok "fixed: locked account + cancel -> still refused, lock kept" '[ "$r" != SUCCESS ] && [ "$(tally fixed)" -ge 3 ]'

# scope: other services (system-auth: sudo, login -> hyprlock) unchanged
reset fixed; auth fixed cancel system-auth >/dev/null
ok "scope: system-auth itself unchanged (cancel there still counts)" '[ "$(tally fixed)" = 1 ]'

echo "pam-polkit: $fails failure(s)"
[ "$fails" -eq 0 ]
