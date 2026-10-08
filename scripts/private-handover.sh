#!/usr/bin/env bash
# The public -> private handover - internal helper of PHASE 2
# (./bootstrap-personal.sh runs it after its preflight; ./bootstrap.sh
# never does).
#
#   1. GitHub over SSH must work with the Bitwarden desktop SSH agent:
#      its socket exists, the agent lists a key, and `ssh -T git@github.com`
#      authenticates - checked once. If not: ONE "ACTION REQUIRED" with
#      what to do in Bitwarden (by hand - nothing here unlocks, reads or
#      exports anything), exit 3; re-run ./bootstrap-personal.sh after.
#   2. Clone the private provisioning repository, or fast-forward an
#      existing clone (scripts/git-sync.sh) - only if it is a git repository
#      with the expected origin, on a branch, with a clean working tree.
#      Never reset, stash, checkout over or delete anything: any doubt = stop.
#   3. Run its bootstrap.sh (with WORKSTATION_GIT_SYNC = that helper, for
#      the private repository's own list of checkouts) and return its exit
#      code.
#
# Nothing private is in this public repository: only the private repo's
# name and where it is cloned. The checkout and its contents stay the
# private repository's (it decides what to deploy and how).
#
# Exit: 0 = done (the private bootstrap's 0), 3 = ACTION REQUIRED
# (Bitwarden/GitHub SSH), 1 = stopped (network, host key, repository not
# safe to update), else the private bootstrap's exit code.
#
# Overridable for tests: WORKSTATION_PRIVATE_REPO, WORKSTATION_PRIVATE_DIR,
# WORKSTATION_BITWARDEN_SOCKET.
set -uo pipefail

PRIVATE_REPO=${WORKSTATION_PRIVATE_REPO:-git@github.com:Peppeppa/dotfiles-provision.git}
PRIVATE_DIR=${WORKSTATION_PRIVATE_DIR:-$HOME/repos/peppeppa/dotfiles-provision}
AGENT_SOCK=${WORKSTATION_BITWARDEN_SOCKET:-$HOME/.bitwarden-ssh-agent.sock}
GIT_SYNC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/git-sync.sh

say() { printf '[PRIVATE] %s\n' "$*"; }
stop() { printf '[PRIVATE] STOP: %s\n' "$*" >&2; exit 1; }

print_action() { # reason
    cat >&2 <<EOF

==================================================================
ACTION REQUIRED - private provisioning needs GitHub over SSH
------------------------------------------------------------------
Detected: $1

In the Bitwarden desktop app (OS menu -> Bitwarden), by hand:
  1. Self-hosted server: on the login screen pick "Self-hosted" and
     enter your server URL. Log in and unlock the vault yourself.
  2. Settings -> "Enable SSH agent": on.
     "Ask for authorization": Never - or click Authorize in the
     "Confirm SSH key usage" dialog each time it appears.
     (Recommended: show tray icon, start to tray, close to tray -
     Bitwarden must be running for the agent to exist.)
  3. Your GitHub SSH key must be an "SSH key" item in the vault, and
     its public key must be added to your GitHub account.
  4. Then re-run:  ./bootstrap-personal.sh
==================================================================
EOF
}

# One check. Sets REASON; returns 0 = GitHub accepts, 3 = the user's turn
# (Bitwarden), 1 = anything else (network, host key) = stop.
check_github() {
    REASON=""
    [ -S "$AGENT_SOCK" ] || {
        REASON="no Bitwarden SSH agent socket ($AGENT_SOCK) - Bitwarden not running, or its SSH agent is off"
        return 3
    }
    local keys gh
    if ! keys=$(SSH_AUTH_SOCK=$AGENT_SOCK ssh-add -L 2>&1) || [ -z "$keys" ]; then
        case $keys in
            *refused*) REASON="the Bitwarden SSH agent refuses (vault locked?)" ;;
            *) REASON="the Bitwarden SSH agent offers no key (vault locked, or no SSH key item)" ;;
        esac
        return 3
    fi
    # github.com's host keys are pinned in ~/.ssh/known_hosts by roles/base:
    # StrictHostKeyChecking=yes, never trust-on-first-use here. GitHub ends
    # the session with exit 1 even when authentication worked - judge the text.
    gh=$(SSH_AUTH_SOCK=$AGENT_SOCK ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes \
            -o ConnectTimeout=15 git@github.com 2>&1 </dev/null)
    case $gh in
        *"successfully authenticated"*) return 0 ;;
        *"Permission denied"*)
            REASON="GitHub rejected every key the agent offered (public key not on GitHub? or the \"Confirm SSH key usage\" dialog was not authorized)"
            return 3 ;;
        *) REASON="GitHub over SSH failed (network? host key?): $(printf '%s' "$gh" | tail -n 1)"; return 1 ;;
    esac
}

# ---- 1. GitHub SSH via the Bitwarden agent ----------------------------------
check_github; rc=$?
[ $rc -eq 1 ] && stop "$REASON"
if [ $rc -eq 3 ]; then
    print_action "$REASON"
    exit 3
fi
say "GitHub SSH works (Bitwarden agent)"
export SSH_AUTH_SOCK=$AGENT_SOCK

# ---- 2. clone, or a safe fast-forward (scripts/git-sync.sh) -----------------
"$GIT_SYNC" "$PRIVATE_REPO" "$PRIVATE_DIR" || exit 1

# ---- 3. the private bootstrap ---------------------------------------------------
[ -x "$PRIVATE_DIR/bootstrap.sh" ] || stop "$PRIVATE_DIR/bootstrap.sh missing or not executable"
say "running $PRIVATE_DIR/bootstrap.sh"
# The same safe clone/fast-forward for the user's further checkouts (the
# private repository's list; it runs without this, too, and then skips them).
WORKSTATION_GIT_SYNC=$GIT_SYNC "$PRIVATE_DIR/bootstrap.sh"
