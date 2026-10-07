#!/usr/bin/env bash
# Regression test for scripts/private-handover.sh (the public -> private
# handover). Safe anywhere: temporary HOME, a local bare repository as the
# "private repo", stub ssh/ssh-add (no network, no agent, no key is ever
# touched), a throwaway unix socket standing in for Bitwarden's.
# Run by tests/run.sh.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" -ne 0 ]; then echo "FAIL $1"; fail=1; fi; }

export HOME="$tmp/home" GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$tmp/stub"
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

# The "private repo": a bare remote with a bootstrap.sh that logs its run.
git init -q --bare "$tmp/remote.git"
git clone -q "$tmp/remote.git" "$tmp/work" 2>/dev/null
cat > "$tmp/work/bootstrap.sh" <<'EOF'
#!/bin/sh
echo "ran $(git -C "$(dirname "$0")" rev-parse --short HEAD)" >> "$HANDOVER_LOG"
exit "${PRIVATE_RC:-0}"
EOF
chmod +x "$tmp/work/bootstrap.sh"
echo one > "$tmp/work/file"
git -C "$tmp/work" add -A && git -C "$tmp/work" commit -qm one && git -C "$tmp/work" push -q origin main
push_change() { echo "$1" > "$tmp/work/file"; git -C "$tmp/work" commit -qam "$1"; git -C "$tmp/work" push -q origin main; }

# Stubs: ssh-add lists a key unless $NOKEYS; ssh -T answers like GitHub.
printf '#!/bin/sh\n[ -n "${NOKEYS:-}" ] && exit 1\necho "ssh-ed25519 AAAA test"\n' > "$tmp/stub/ssh-add"
cat > "$tmp/stub/ssh" <<'EOF'
#!/bin/sh
echo "ssh $*" >> "$SSH_LOG"
case "${GH:-ok}" in
  ok) echo "Hi test! You've successfully authenticated, but GitHub does not provide shell access." >&2 ;;
  denied) echo "git@github.com: Permission denied (publickey)." >&2 ;;
  *) echo "ssh: connect to host github.com port 22: Network is unreachable" >&2; exit 255 ;;
esac
exit 1
EOF
chmod +x "$tmp/stub/"*
export PATH="$tmp/stub:$PATH" HANDOVER_LOG="$tmp/ran" SSH_LOG="$tmp/ssh.log"
export WORKSTATION_PRIVATE_REPO="$tmp/remote.git" WORKSTATION_PRIVATE_DIR="$HOME/repos/peppeppa/dotfiles-provision"
export WORKSTATION_BITWARDEN_SOCKET="$HOME/.bitwarden-ssh-agent.sock"
export WORKSTATION_PRIVATE_WAIT=0    # the no-terminal path; waiting is tested below
P=$WORKSTATION_PRIVATE_DIR
H="$repo/scripts/private-handover.sh"
run() { : > "$tmp/ran"; "$H" > "$tmp/out" 2>&1; rc=$?; }
ran() { [ -s "$tmp/ran" ]; }

# ---- no agent socket / no key / key rejected -> one ACTION REQUIRED ---------
run
[ $rc -eq 3 ] && [ "$(grep -c 'ACTION REQUIRED' "$tmp/out")" = 1 ] && [ ! -e "$P" ] && ! ran
check "no Bitwarden socket -> exactly one ACTION REQUIRED, exit 3, no clone (rc $rc)" $?
grep -q 'Enable SSH agent' "$tmp/out"; check "ACTION REQUIRED names the Bitwarden SSH agent option" $?

python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$WORKSTATION_BITWARDEN_SOCKET"
NOKEYS=1 run
[ $rc -eq 3 ] && grep -q 'offers no key' "$tmp/out" && [ ! -e "$P" ]; check "socket but no key -> ACTION REQUIRED (rc $rc)" $?
GH=denied run
[ $rc -eq 3 ] && grep -q 'rejected' "$tmp/out" && [ ! -e "$P" ]; check "GitHub denies -> ACTION REQUIRED (rc $rc)" $?
GH=down run
[ $rc -eq 1 ] && ! grep -q 'ACTION REQUIRED' "$tmp/out" && [ ! -e "$P" ]; check "network failure -> plain stop, not ACTION REQUIRED (rc $rc)" $?
grep -q 'StrictHostKeyChecking=yes' "$tmp/ssh.log" && grep -q 'BatchMode=yes' "$tmp/ssh.log"
check "ssh -T: pinned host keys only, never prompts" $?

# ---- SSH ok -> clone + private bootstrap ---------------------------------------
run
[ $rc -eq 0 ] && [ "$(cat "$P/file")" = one ] && ran; check "SSH ok -> cloned, bootstrap ran (rc $rc)" $?
run
[ $rc -eq 0 ] && grep -q 'up to date' "$tmp/out" && ran; check "second run: no change, bootstrap runs again (rc $rc)" $?

# ---- clean clone -> fast-forward -----------------------------------------------
push_change two
run
[ $rc -eq 0 ] && [ "$(cat "$P/file")" = two ] && grep -q 'fast-forwarded' "$tmp/out"; check "clean repo -> fast-forward (rc $rc)" $?

# ---- dirty clone -> nothing updated, nothing discarded -------------------------
push_change three
echo "my local edit" > "$P/file"; echo keep > "$P/untracked"
head=$(git -C "$P" rev-parse HEAD)
run
[ $rc -eq 1 ] && [ "$(cat "$P/file")" = "my local edit" ] && [ -f "$P/untracked" ] \
    && [ "$(git -C "$P" rev-parse HEAD)" = "$head" ] && ! ran && grep -q 'local changes' "$tmp/out"
check "dirty repo -> stop, edit + untracked file + HEAD kept, bootstrap not run (rc $rc)" $?
git -C "$P" checkout -q -- file; rm "$P/untracked"
run
[ $rc -eq 0 ] && [ "$(cat "$P/file")" = three ]; check "after cleaning up -> fast-forward resumes (rc $rc)" $?

# ---- local commit ahead -> kept; diverged -> stop ------------------------------
echo mine > "$P/mine"; git -C "$P" add mine; git -C "$P" commit -qm mine
run
[ $rc -eq 0 ] && [ -f "$P/mine" ]; check "local commit ahead -> kept, run goes on (rc $rc)" $?
push_change four
head=$(git -C "$P" rev-parse HEAD)
run
[ $rc -eq 1 ] && grep -q 'diverged' "$tmp/out" && [ "$(git -C "$P" rev-parse HEAD)" = "$head" ] && ! ran
check "diverged -> stop, local commit kept, no merge (rc $rc)" $?
git -C "$P" reset -q --hard origin/main    # (test cleanup only)

# ---- private bootstrap's exit code is passed on --------------------------------
PRIVATE_RC=2 run
[ $rc -eq 2 ]; check "private bootstrap exit code propagated (rc $rc)" $?

# ---- not a checkout / foreign origin / detached -> untouched -------------------
other="$HOME/elsewhere"; WORKSTATION_PRIVATE_DIR=$other; export WORKSTATION_PRIVATE_DIR
mkdir -p "$other"; echo precious > "$other/notes"
run
[ $rc -eq 1 ] && [ "$(cat "$other/notes")" = precious ] && [ ! -e "$other/.git" ] && ! ran
check "existing non-git directory -> stop, untouched (rc $rc)" $?
rm -rf "$other"; git clone -q "$tmp/remote.git" "$other"; git -C "$other" remote set-url origin https://example.invalid/x.git
run
[ $rc -eq 1 ] && grep -q 'expected' "$tmp/out" && ! ran; check "foreign origin -> stop (rc $rc)" $?
git -C "$other" remote set-url origin "$tmp/remote.git"; git -C "$other" checkout -q --detach
run
[ $rc -eq 1 ] && grep -q 'detached' "$tmp/out" && ! ran; check "detached HEAD -> stop (rc $rc)" $?

# ---- waiting mode (terminal): one ACTION REQUIRED, then on by itself ---------
# ssh-add refuses twice (vault locked), then lists a key; GitHub denies once
# (dialog not authorized), then accepts. GitHub must only be asked once the
# agent offers a key - never while it is still locked.
rm -rf "$HOME/repos"; WORKSTATION_PRIVATE_DIR="$HOME/repos/peppeppa/dotfiles-provision"
cat > "$tmp/stub/ssh-add" <<'EOF'
#!/bin/sh
n=$(($(cat "$TMPC.add" 2>/dev/null || echo 0) + 1)); echo $n > "$TMPC.add"
[ $n -le 2 ] && { echo "error fetching identities: agent refused operation" >&2; exit 1; }
echo "ssh-ed25519 AAAA test"
EOF
cat > "$tmp/stub/ssh" <<'EOF'
#!/bin/sh
n=$(($(cat "$TMPC.ssh" 2>/dev/null || echo 0) + 1)); echo $n > "$TMPC.ssh"
echo "ssh after $(cat "$TMPC.add") agent checks" >> "$SSH_LOG"
[ $n -le 1 ] && { echo "git@github.com: Permission denied (publickey)." >&2; exit 255; }
echo "Hi test! You've successfully authenticated, but GitHub does not provide shell access." >&2; exit 1
EOF
chmod +x "$tmp/stub/"*
export TMPC="$tmp/count" WORKSTATION_PRIVATE_POLL=0 WORKSTATION_PRIVATE_RETRY=0
rm -f "$TMPC".*; : > "$SSH_LOG"
WORKSTATION_PRIVATE_WAIT=1 run
[ $rc -eq 0 ] && [ "$(grep -c 'ACTION REQUIRED' "$tmp/out")" = 1 ] && [ -d "$WORKSTATION_PRIVATE_DIR/.git" ] && ran
check "wait: locked -> denied -> accepted: one ACTION REQUIRED, then cloned + bootstrap ran (rc $rc)" $?
[ "$(head -1 "$SSH_LOG")" = "ssh after 4 agent checks" ]   # 2 refused, then key seen + the full check && [ "$(wc -l < "$SSH_LOG")" = 2 ]
check "wait: GitHub asked only once the agent offers a key, retried once after the denial" $?
grep -q 'waiting: GitHub rejected' "$tmp/out" && grep -q 'Waiting here' "$tmp/out"; check "wait: status changes shown" $?
rm -rf "$HOME/repos"; rm -f "$TMPC".*
printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/ssh-add"
WORKSTATION_PRIVATE_WAIT=1 WORKSTATION_PRIVATE_WAIT_MAX=0 run
[ $rc -eq 3 ] && grep -q 'gave up waiting' "$tmp/out" && [ ! -e "$WORKSTATION_PRIVATE_DIR" ]
check "wait: gives up after WORKSTATION_PRIVATE_WAIT_MAX, exit 3, nothing cloned (rc $rc)" $?

# ---- bootstrap.sh: handover only after real runs --------------------------------
w=$(sed -n '/^wants_private_handover()/,/^}/p' "$repo/bootstrap.sh")
eval "$w"
wants_private_handover && wants_private_handover --tags base; check "bootstrap: real runs hand over" $?
! wants_private_handover --check && ! wants_private_handover -C --diff && ! wants_private_handover --list-tasks \
    && ! WORKSTATION_PRIVATE=0 wants_private_handover
check "bootstrap: --check/-C/--list-*/WORKSTATION_PRIVATE=0 skip the handover" $?

[ $fail -eq 0 ] && echo "private-handover: all checks passed"
exit $fail
