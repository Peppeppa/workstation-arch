#!/usr/bin/env bash
set -euo pipefail

# workstation-arch bootstrap launcher - PHASE 1 (system).
#
# Run as a normal user from a clean Arch Linux install - a plain TTY is
# enough, no graphical session, no credentials:
#   ./bootstrap.sh [ansible-playbook args...]
#
# Prerequisite (run this yourself first, once):
#   sudo pacman -Syu --needed git ansible
#
# Ansible - not this script - is the source of truth for the desired
# system state (see local.yml, roles/), and Ansible - not this script -
# owns privilege escalation (`become`). This launcher only:
#   1. verifies Arch Linux and that it isn't run as root
#   2. verifies git and ansible-playbook are already installed
#   3. hands off to `ansible-playbook --ask-become-pass local.yml`,
#      forwarding any extra arguments (e.g. --check, --tags base) and
#      its exit code
#   4. after a successful real run: prints the next steps. Nothing
#      private happens here - no GitHub SSH, no Bitwarden, no private
#      repository. That is PHASE 2, ./bootstrap-personal.sh, started by
#      hand once Bitwarden is set up in the graphical session.
#
# Do NOT run this with sudo - Ansible will prompt for the become
# password itself ("BECOME password:") and use it only for the tasks
# that actually need it.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT

# shellcheck source=scripts/helpers/log.sh
source "${REPO_ROOT}/scripts/helpers/log.sh"

verify_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        log_error "bootstrap.sh must be run as a normal user, not as root/via sudo."
        exit 1
    fi
    log_check "running as normal user ($(whoami))"
}

verify_arch_linux() {
    if [[ ! -r /etc/os-release ]]; then
        log_error "/etc/os-release not found; cannot verify this is Arch Linux."
        exit 1
    fi

    local distro_id=""
    distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"

    if [[ "${distro_id}" != "arch" ]]; then
        log_error "unsupported distribution (ID=${distro_id:-unknown}); this bootstrap targets upstream Arch Linux only."
        exit 1
    fi
    log_check "Arch Linux detected"
}

verify_prerequisites() {
    local missing=()
    local cmd
    for cmd in git ansible-playbook; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        log_error "missing required command(s): ${missing[*]}"
        log_error "install them first: sudo pacman -Syu --needed git ansible"
        exit 1
    fi
    log_check "git and ansible-playbook available"
}

# Next steps only after a real run - not after a dry run, a syntax check
# or a listing.
is_real_run() {
    local arg
    for arg in "$@"; do
        case "${arg}" in
            -C|--check|--syntax-check|--list-tasks|--list-tags|--list-hosts) return 1 ;;
        esac
    done
}

print_next_steps() {
    cat <<EOF

Next steps (phase 2: personal environment - once, by hand):
  1. Reboot and log in at the login screen (Hyprland session).
  2. Open Bitwarden (OS menu -> Bitwarden), log in and unlock the vault.
  3. Bitwarden Settings -> "Enable SSH agent": on ("Ask for authorization":
     Never, or authorize the GitHub key when asked).
  4. In a terminal:  cd ${REPO_ROOT} && ./bootstrap-personal.sh
EOF
}

main() {
    log_info "workstation-arch bootstrap"

    verify_not_root
    verify_arch_linux
    verify_prerequisites

    log_info "handing off to Ansible (local.yml)"
    cd "${REPO_ROOT}"

    set +e
    ansible-playbook --ask-become-pass local.yml "$@"
    local ansible_exit=$?
    set -e

    if [[ "${ansible_exit}" -eq 0 ]]; then
        log_done "bootstrap complete (phase 1: system)"
        if is_real_run "$@"; then
            print_next_steps
        fi
    else
        log_error "Ansible provisioning failed (exit ${ansible_exit})"
        log_error "the failing task is the 'fatal:' one above (role : task, with its file:line);"
        log_error "rerun just that role with details: ./bootstrap.sh --tags <role> -v"
        log_error "desktop/runtime state: repo-diagnose (see README 'Troubleshooting')"
    fi
    exit "${ansible_exit}"
}

main "$@"
