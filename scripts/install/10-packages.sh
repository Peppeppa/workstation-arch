# Phase 1: base package installation.
# Meant to be sourced by bootstrap.sh, not executed directly.
# Depends on: scripts/helpers/log.sh, REPO_ROOT being set.
#
# Pacman policy: missing packages are installed together with a full
# sync+upgrade (`pacman -Syu --needed`), never a bare `pacman -Sy`. On a
# rolling-release system, syncing the package database without upgrading
# the rest of the system risks partial upgrades. If every wanted package is
# already installed, pacman is not invoked at all — this bootstrap does not
# take over routine system updates, that remains a manual `pacman -Syu`.

read_package_manifest() {
    local manifest="$1"
    grep -vE '^[[:space:]]*(#|$)' "${manifest}"
}

install_base_packages() {
    local manifest="${REPO_ROOT}/packages/base.txt"

    if [[ ! -f "${manifest}" ]]; then
        log_error "package manifest not found: ${manifest}"
        exit 1
    fi

    local wanted=()
    while IFS= read -r pkg; do
        wanted+=("${pkg}")
    done < <(read_package_manifest "${manifest}")

    if [[ "${#wanted[@]}" -eq 0 ]]; then
        log_info "packages/base.txt has no packages listed; nothing to do"
        return
    fi

    declare -A installed=()
    local pkg
    while IFS= read -r pkg; do
        installed["${pkg}"]=1
    done < <(pacman -Qq)

    local missing=()
    for pkg in "${wanted[@]}"; do
        if [[ -n "${installed[${pkg}]:-}" ]]; then
            log_skip "${pkg} already installed"
        else
            missing+=("${pkg}")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        log_ok "base packages already installed"
        return
    fi

    for pkg in "${missing[@]}"; do
        log_install "${pkg}"
    done

    sudo pacman -Syu --needed "${missing[@]}"

    log_ok "base packages installed"
}
