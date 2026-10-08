#!/usr/bin/env bash
# Regression test for phase 2 - bootstrap-personal.sh and its helper
# scripts/private-handover.sh (the public -> private handover) - and for
# phase 1 (bootstrap.sh) never touching anything private. Safe anywhere: temporary HOME, a local bare repository as the
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
echo "${WORKSTATION_GIT_SYNC:-unset}" > "$HANDOVER_LOG.sync"
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
P=$WORKSTATION_PRIVATE_DIR
H="$repo/scripts/private-handover.sh"
run() { : > "$tmp/ran"; "$H" > "$tmp/out" 2>&1; rc=$?; }
ran() { [ -s "$tmp/ran" ]; }

# ---- no agent socket / no key / key rejected -> one ACTION REQUIRED ---------
run
[ $rc -eq 3 ] && [ "$(grep -c 'ACTION REQUIRED' "$tmp/out")" = 1 ] && [ ! -e "$P" ] && ! ran
check "no Bitwarden socket -> exactly one ACTION REQUIRED, exit 3, no clone (rc $rc)" $?
grep -q 'Enable SSH agent' "$tmp/out" && grep -q 'bootstrap-personal.sh' "$tmp/out"
check "ACTION REQUIRED names the Bitwarden SSH agent option and the re-run" $?

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
[ "$(cat "$tmp/ran.sync")" = "$repo/scripts/git-sync.sh" ] && [ -x "$(cat "$tmp/ran.sync")" ]
check "private bootstrap gets WORKSTATION_GIT_SYNC = scripts/git-sync.sh" $?

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

# ---- no waiting: a locked agent is reported at once, also in a terminal -----
rm -rf "$HOME/repos" "$other"; WORKSTATION_PRIVATE_DIR=$P; export WORKSTATION_PRIVATE_DIR
NOKEYS=1 timeout 10 script -qec "$H" /dev/null > "$tmp/out" 2>&1; rc=$?
[ $rc -eq 3 ] && [ "$(grep -c 'ACTION REQUIRED' "$tmp/out")" = 1 ] && [ ! -e "$P" ]
check "terminal + locked agent -> one ACTION REQUIRED, exit 3 at once, no waiting (rc $rc)" $?

# ---- bootstrap-personal.sh: preflight, then the handover ---------------------
B="$repo/bootstrap-personal.sh"
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/bitwarden-desktop"; chmod +x "$tmp/stub/bitwarden-desktop"
command -v stow >/dev/null || { printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/stow"; chmod +x "$tmp/stub/stow"; }
prun() { : > "$tmp/ran"; "$B" > "$tmp/out" 2>&1; rc=$?; }
prun
[ $rc -eq 1 ] && grep -q 'run ./bootstrap.sh first' "$tmp/out" && [ ! -e "$P" ] && ! ran
check "personal: no Bitwarden block in ~/.ssh/config -> stop, nothing cloned (rc $rc)" $?
mkdir -p "$HOME/.ssh"
printf '# BEGIN workstation-arch (roles/base): Bitwarden SSH agent\nHost *\n    IdentityAgent ~/.bitwarden-ssh-agent.sock\n# END workstation-arch (roles/base): Bitwarden SSH agent\n' > "$HOME/.ssh/config"
prun
[ $rc -eq 1 ] && grep -q 'host keys are not pinned' "$tmp/out" && ! ran
check "personal: github.com host keys not pinned -> stop (rc $rc)" $?
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$HOME/.ssh/known_hosts"
rm "$tmp/stub/bitwarden-desktop"
if ! command -v bitwarden-desktop >/dev/null; then
    prun
    [ $rc -eq 1 ] && grep -q 'Bitwarden desktop missing' "$tmp/out" && ! ran
    check "personal: Bitwarden desktop not installed -> stop (rc $rc)" $?
fi
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/bitwarden-desktop"; chmod +x "$tmp/stub/bitwarden-desktop"
NOKEYS=1 prun
[ $rc -eq 3 ] && [ "$(grep -c 'ACTION REQUIRED' "$tmp/out")" = 1 ] && [ ! -e "$P" ] && ! ran
check "personal: preflight ok, agent locked -> exactly one ACTION REQUIRED, exit 3 (rc $rc)" $?
prun
[ $rc -eq 0 ] && [ -d "$P/.git" ] && ran && grep -q 'personal environment complete' "$tmp/out"
check "personal: SSH ok -> cloned, private bootstrap ran (rc $rc)" $?
prun
[ $rc -eq 0 ] && grep -q 'up to date' "$tmp/out" && ran; check "personal: second run idempotent (rc $rc)" $?
echo dirty > "$P/file"
prun
[ $rc -eq 1 ] && [ "$(cat "$P/file")" = dirty ] && ! ran; check "personal: dirty private repo -> stop, edit kept (rc $rc)" $?
git -C "$P" checkout -q -- file

# ---- git-sync.sh directly (the private bootstrap's further checkouts) --------
S="$repo/scripts/git-sync.sh"
srun() { "$S" "$@" > "$tmp/out" 2>&1; rc=$?; }
d="$HOME/repos/var/walls"
srun "$tmp/remote.git" "$d"
[ $rc -eq 0 ] && [ "$(git -C "$d" symbolic-ref --short HEAD)" = main ] && [ "$(git -C "$d" remote get-url origin)" = "$tmp/remote.git" ] \
    && grep -q 'cloned (main at' "$tmp/out"
check "git-sync: missing -> cloned, branch main, origin exact (rc $rc)" $?
state() { git -C "$d" rev-parse HEAD; git -C "$d" status --porcelain; find "$d" -path "$d/.git" -prune -o -printf '%p %s\n' | sort; }
before=$(state); srun "$tmp/remote.git" "$d"
[ $rc -eq 0 ] && grep -q 'up to date' "$tmp/out" && [ "$(state)" = "$before" ]; check "git-sync: second run changes nothing (rc $rc)" $?
push_change five; srun "$tmp/remote.git" "$d"
[ $rc -eq 0 ] && [ "$(cat "$d/file")" = five ] && grep -q 'fast-forwarded' "$tmp/out"; check "git-sync: stale -> fast-forward (rc $rc)" $?
push_change six; echo keep > "$d/untracked-only"; head=$(git -C "$d" rev-parse HEAD)
srun "$tmp/remote.git" "$d"
[ $rc -eq 1 ] && [ -f "$d/untracked-only" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$head" ]; check "git-sync: untracked file -> stop, kept (rc $rc)" $?
rm "$d/untracked-only"
git -C "$d" switch -q -c topic; srun "$tmp/remote.git" "$d"
[ $rc -eq 1 ] && grep -q 'no upstream' "$tmp/out"; check "git-sync: branch without upstream -> stop (rc $rc)" $?
git -C "$d" switch -q main; git -C "$d" branch -q -D topic
mkdir -p "$d/sub"; srun "$tmp/remote.git" "$d/sub"
[ $rc -eq 1 ] && grep -q 'not a git checkout' "$tmp/out" && [ ! -e "$d/sub/.git" ]; check "git-sync: directory inside another checkout -> stop (rc $rc)" $?
rmdir "$d/sub"
srun "$tmp/remote.git" "$d"; [ $rc -eq 0 ] && [ "$(cat "$d/file")" = six ]; check "git-sync: resolved -> fast-forward resumes (rc $rc)" $?
srun onlyone; [ $rc -eq 1 ]; check "git-sync: usage error -> exit 1" $?
! grep -nE '(^|[;&|(]|\$\() *(g|git) +(-[^ ]+ +)*(reset|stash|clean|push|checkout)|--force|\brm -' "$S"; check "git-sync.sh: no reset/stash/clean/checkout/force/rm" $?

# ---- bootstrap.sh (phase 1) never goes private --------------------------------
! grep -nE 'private-handover|bootstrap-personal\.sh"|ssh -T|ssh-add|git@github' "$repo/bootstrap.sh" | grep -v '^\s*[0-9]*:\s*#' | grep -v 'print\|cd \${REPO_ROOT} &&'
check "bootstrap.sh: no handover, no GitHub SSH, no agent query" $?
w=$(sed -n '/^is_real_run()/,/^}/p' "$repo/bootstrap.sh")
eval "$w"
is_real_run && is_real_run --tags base && ! is_real_run --check && ! is_real_run -C --diff && ! is_real_run --list-tasks
check "bootstrap: next steps only after real runs" $?

[ $fail -eq 0 ] && echo "private-handover: all checks passed"
exit $fail
