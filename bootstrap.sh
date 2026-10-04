#!/usr/bin/env bash
set -euo pipefail

# workstation-arch bootstrap launcher.
#
# Run as a normal user from a clean Arch Linux install:
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
        log_done "bootstrap complete"
    else
        log_error "Ansible provisioning failed (exit ${ansible_exit})"
        log_error "the failing task is the 'fatal:' one above (role : task, with its file:line);"
        log_error "rerun just that role with details: ./bootstrap.sh --tags <role> -v"
        log_error "desktop/runtime state: repo-diagnose (see README 'Troubleshooting')"
    fi
    exit "${ansible_exit}"
}

main "$@"
