#!/usr/bin/env bash
# Clone a git repository, or fast-forward an existing clone - safely.
# Shared by phase 2: scripts/private-handover.sh (the private provisioning
# repository) and, through $WORKSTATION_GIT_SYNC, the private bootstrap
# (the user's further checkouts). User level only: run as the user who
# owns the checkout, never as root.
#
#   git-sync.sh <url> <directory>
#
# <directory> missing -> clone (parent directories created). Present ->
# updated only if it is a git checkout of its own (not a subdirectory of
# another), with exactly <url> as origin, on a branch with an upstream, and
# a clean working tree (untracked files count); then fetch + fast-forward
# only. A local commit ahead is kept. Anything else = stop, with the reason:
# never reset, stash, clean, force, check out over or delete anything.
#
# Exit: 0 = cloned / fast-forwarded / up to date, 1 = stopped (nothing changed).
set -uo pipefail

[ $# -eq 2 ] || { echo "usage: ${0##*/} <url> <directory>" >&2; exit 1; }
URL=$1 DIR=$2

say() { printf '[REPO] %s\n' "$*"; }
stop() { printf '[REPO] STOP: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || stop "$DIR: run as your normal user, not root"

if [ ! -e "$DIR" ]; then
    mkdir -p -- "$(dirname -- "$DIR")" || stop "cannot create $(dirname -- "$DIR")"
    say "cloning $URL -> $DIR"
    git clone -q -- "$URL" "$DIR" || stop "$DIR: git clone failed"
    say "$DIR: cloned ($(git -C "$DIR" symbolic-ref -q --short HEAD) at $(git -C "$DIR" rev-parse --short HEAD))"
    exit 0
fi

g() { git -C "$DIR" "$@"; }
[ -d "$DIR" ] && [ "$(g rev-parse --show-toplevel 2>/dev/null)" = "$(cd -- "$DIR" && pwd -P)" ] \
    || stop "$DIR exists but is not a git checkout - left untouched; move it away yourself"
origin=$(g remote get-url origin 2>/dev/null)
[ "$origin" = "$URL" ] || stop "$DIR has origin '${origin:-none}', expected $URL - left untouched"
branch=$(g symbolic-ref -q --short HEAD) || stop "$DIR is on a detached HEAD - left untouched"
[ -z "$(g status --porcelain --untracked-files=normal)" ] \
    || stop "$DIR has local changes - nothing was updated or discarded; commit, push or remove them yourself, then re-run"
g fetch -q origin || stop "$DIR: git fetch failed"
upstream=$(g rev-parse -q --verify "@{upstream}") || stop "$DIR: branch $branch has no upstream - left untouched"
if g merge-base --is-ancestor "$upstream" HEAD; then
    say "$DIR ($branch): up to date (or only local commits ahead)"
elif g merge-base --is-ancestor HEAD "$upstream"; then
    g merge -q --ff-only "$upstream" || stop "$DIR: fast-forward failed"
    say "$DIR ($branch): fast-forwarded to $(g rev-parse --short HEAD)"
else
    stop "$DIR ($branch) and its upstream have diverged - nothing changed; resolve it yourself"
fi
