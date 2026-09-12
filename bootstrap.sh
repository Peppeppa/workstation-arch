#!/usr/bin/env bash
set -euo pipefail

# workstation-arch bootstrap wrapper.
#
# Run as a normal user from a clean Arch Linux install:
#   ./bootstrap.sh [ansible-playbook args...]
#
# Ansible - not this script - is the source of truth for the desired
# system state (see local.yml, roles/). This wrapper only:
#   1. verifies Arch Linux and that it isn't run as root
#   2. validates sudo once and keeps it alive for this run
#   3. installs git + ansible if missing
#   4. hands off to `ansible-playbook local.yml`, forwarding any extra
#      arguments (e.g. --check, --tags base) and its exit code
#
# Do NOT run this with sudo. Individual steps escalate privileges only
# where required (sudo -v here, `become: true` in Ansible).

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT

# shellcheck source=scripts/helpers/log.sh
source "${REPO_ROOT}/scripts/helpers/log.sh"

SUDO_KEEPALIVE_PID=""

cleanup() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]] && kill -0 "${SUDO_KEEPALIVE_PID}" 2>/dev/null; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
        wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    fi
    SUDO_KEEPALIVE_PID=""
}

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

    if ! command -v pacman >/dev/null 2>&1; then
        log_error "pacman not found; this does not look like a working Arch system."
        exit 1
    fi
}

# Validates sudo once (a single password prompt) and refreshes that
# credential cache in the background for the lifetime of this script, so
# nothing prompts for the password again mid-run. Uses only sudo's own
# credential cache - no sudoers changes, no NOPASSWD.
verify_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        log_error "sudo not found; install and configure sudo before running bootstrap."
        exit 1
    fi

    log_check "validating sudo credentials"
    if ! sudo -v; then
        log_error "unable to validate sudo access for current user."
        exit 1
    fi
    log_ok "sudo credentials validated"

    (
        while kill -0 "$$" 2>/dev/null; do
            sudo -n true 2>/dev/null
            sleep 60
        done
    ) &
    disown
    SUDO_KEEPALIVE_PID=$!
    log_info "keeping sudo credentials active for this bootstrap run"
}

install_bootstrap_tools() {
    local pkg
    local missing=()
    for pkg in git ansible; do
        if ! pacman -Qq "${pkg}" >/dev/null 2>&1; then
            missing+=("${pkg}")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        log_ok "git and ansible already installed"
        return
    fi

    for pkg in "${missing[@]}"; do
        log_install "${pkg}"
    done
    sudo pacman -Syu --needed --noconfirm "${missing[@]}"
    log_ok "bootstrap tools installed"
}

main() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    log_info "workstation-arch bootstrap"

    verify_not_root
    verify_arch_linux
    verify_sudo
    install_bootstrap_tools

    log_info "handing off to Ansible (local.yml)"
    cd "${REPO_ROOT}"

    set +e
    ansible-playbook local.yml "$@"
    local ansible_exit=$?
    set -e

    if [[ "${ansible_exit}" -eq 0 ]]; then
        log_done "bootstrap complete"
    else
        log_error "Ansible provisioning failed (exit ${ansible_exit})"
    fi
    exit "${ansible_exit}"
}

main "$@"
