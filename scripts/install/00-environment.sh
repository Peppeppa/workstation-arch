# Environment and repository validation, plus sudo credential lifecycle.
# Meant to be sourced by bootstrap.sh, not executed directly.
# Depends on: scripts/helpers/log.sh, REPO_ROOT being set.

validate_environment() {
    verify_not_root
    verify_arch_linux
    verify_sudo
    verify_repository_layout
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
        log_error "unsupported distribution (ID=${distro_id:-unknown}); this bootstrap targets Arch Linux only."
        exit 1
    fi
    log_check "Arch Linux detected"

    if ! command -v pacman >/dev/null 2>&1; then
        log_error "pacman not found; this does not look like a working Arch system."
        exit 1
    fi
    log_check "pacman available"
}

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

    start_sudo_keepalive
}

# Sudo credential keepalive.
#
# `sudo -v` above prompts for the password once and caches it. Without a
# keepalive, that cache expires (sudo's normal timestamp timeout) if the
# rest of the bootstrap takes a while, causing another password prompt.
# This refreshes the cached credentials in the background for the
# lifetime of the bootstrap process, using only sudo's own credential
# cache — no sudoers changes, no NOPASSWD, no password handled by us.
#
# SUDO_KEEPALIVE_PID is read by stop_sudo_keepalive (called from
# bootstrap.sh's exit trap) so the background loop never outlives the
# bootstrap run.
SUDO_KEEPALIVE_PID=""

start_sudo_keepalive() {
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

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]] && kill -0 "${SUDO_KEEPALIVE_PID}" 2>/dev/null; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
        wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    fi
    SUDO_KEEPALIVE_PID=""
}

verify_repository_layout() {
    local required_paths=(
        "packages/base.txt"
        "scripts/install"
    )
    local path
    for path in "${required_paths[@]}"; do
        if [[ ! -e "${REPO_ROOT}/${path}" ]]; then
            log_error "expected repository path missing: ${path}"
            exit 1
        fi
    done
    log_check "repository layout looks valid"
}
