#!/usr/bin/env bash
set -uo pipefail

# workstation-arch PHASE 2 (personal environment) - the one public entry
# point to the private provisioning repository.
#
# Run once by hand, as your normal user, in a terminal of the graphical
# session - AFTER ./bootstrap.sh (phase 1) and after Bitwarden is set up
# (logged in, vault unlocked, SSH agent on):
#   ./bootstrap-personal.sh
#
# Nothing starts this on its own (no autostart, unit or prompt).
#
#   1. preflight: normal user; git + stow; phase 1's Bitwarden SSH-agent
#      integration (Bitwarden desktop installed, the managed IdentityAgent
#      block in ~/.ssh/config, github.com's pinned host keys). Missing ->
#      stop and say "run ./bootstrap.sh" - phase 1 is never done here.
#   2. scripts/private-handover.sh: GitHub over SSH via the Bitwarden agent
#      (else ONE "ACTION REQUIRED", exit 3), clone or safe fast-forward of
#      the private repository, its bootstrap.sh.
#
# Exit: 0 = done, 1 = stopped (preflight / repository not safe to update /
# network), 3 = ACTION REQUIRED (Bitwarden/GitHub SSH), else the private
# bootstrap's exit code.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT

# shellcheck source=scripts/helpers/log.sh
source "${REPO_ROOT}/scripts/helpers/log.sh"

phase1_missing() { # what
    log_error "$1 - phase 1 is not (fully) provisioned: run ./bootstrap.sh first"
    exit 1
}

preflight() {
    if [[ "${EUID}" -eq 0 ]]; then
        log_error "bootstrap-personal.sh must be run as a normal user, not as root/via sudo."
        exit 1
    fi
    local cmd
    for cmd in git stow ssh ssh-add; do
        command -v "${cmd}" >/dev/null 2>&1 || phase1_missing "${cmd} missing"
    done
    command -v bitwarden-desktop >/dev/null 2>&1 || phase1_missing "Bitwarden desktop missing"
    grep -qs '^# BEGIN workstation-arch (roles/base): Bitwarden SSH agent' "${HOME}/.ssh/config" \
        || phase1_missing "~/.ssh/config has no Bitwarden SSH agent block"
    ssh-keygen -F github.com -f "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 \
        || phase1_missing "github.com's host keys are not pinned in ~/.ssh/known_hosts"
    log_check "phase 1 integration present (git, stow, Bitwarden SSH agent config, github.com host keys)"
}

main() {
    log_info "workstation-arch bootstrap-personal (phase 2)"
    preflight
    "${REPO_ROOT}/scripts/private-handover.sh"
    local rc=$?
    case ${rc} in
        0) log_done "personal environment complete (phase 2)" ;;
        3) ;;                                   # the ACTION REQUIRED above says it all
        *) log_error "phase 2 stopped (exit ${rc}) - see the message above" ;;
    esac
    exit "${rc}"
}

main "$@"
