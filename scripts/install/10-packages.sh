# Package manifest installation.
# Meant to be sourced by bootstrap.sh, not executed directly.
# Depends on: scripts/helpers/log.sh, REPO_ROOT being set.
#
# Pacman policy: missing packages are installed together with a full
# sync+upgrade (`pacman -Syu --needed`), never a bare `pacman -Sy`. On a
# rolling-release system, syncing the package database without upgrading
# the rest of the system risks partial upgrades. If every wanted package is
# already installed, pacman is not invoked at all — this bootstrap does not
# take over routine system updates, that remains a manual `pacman -Syu`.
#
# `--noconfirm` is added on top of that so a validated bootstrap run does
# not stop for a per-transaction "Proceed with installation?" prompt. It
# only skips that confirmation — it does not relax signature checking,
# does not ignore conflicts, and does not touch pacman.conf. Real failures
# (conflicts, bad signatures, corrupted packages, failed downloads) still
# make pacman exit non-zero, which `set -euo pipefail` turns into a clean
# bootstrap abort.

read_package_manifest() {
    local manifest="$1"
    grep -vE '^[[:space:]]*(#|$)' "${manifest}"
}

install_package_manifest() {
    local manifest="$1"
    local manifest_name
    manifest_name="$(basename "${manifest}")"

    if [[ ! -f "${manifest}" ]]; then
        log_error "package manifest not found: ${manifest}"
        exit 1
    fi

    local wanted=()
    while IFS= read -r pkg; do
        wanted+=("${pkg}")
    done < <(read_package_manifest "${manifest}")

    if [[ "${#wanted[@]}" -eq 0 ]]; then
        log_info "${manifest_name} has no packages listed; nothing to do"
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
        log_ok "${manifest_name}: packages already installed"
        return
    fi

    for pkg in "${missing[@]}"; do
        log_install "${pkg}"
    done

    sudo pacman -Syu --needed --noconfirm "${missing[@]}"

    log_ok "${manifest_name}: packages installed"
}
