#!/usr/bin/env bash
set -euo pipefail

# workstation-arch bootstrap orchestrator.
#
# Run as a normal user from a clean Arch Linux install:
#   ./bootstrap.sh
#
# Do NOT run this with sudo. Individual steps escalate privileges only
# where required. sudo is validated once (a single password prompt) and
# kept alive for the duration of this run — see start_sudo_keepalive in
# scripts/install/00-environment.sh.
#
# Phase 1: base bootstrap framework + minimal base packages.
# Phase 2 (current): graphics/Wayland foundation packages.
# The rest of the desktop (Hyprland, Quickshell, audio/Bluetooth stacks,
# themes, ...) is not implemented yet.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT

# shellcheck source=scripts/helpers/log.sh
source "${REPO_ROOT}/scripts/helpers/log.sh"
# shellcheck source=scripts/install/00-environment.sh
source "${REPO_ROOT}/scripts/install/00-environment.sh"
# shellcheck source=scripts/install/10-packages.sh
source "${REPO_ROOT}/scripts/install/10-packages.sh"

cleanup() {
    stop_sudo_keepalive
}

main() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    log_info "workstation-arch bootstrap - phase 2"

    validate_environment
    install_package_manifest "${REPO_ROOT}/packages/base.txt"
    install_package_manifest "${REPO_ROOT}/packages/graphics.txt"

    log_info "phase 2 summary: environment validated, base + graphics packages ensured"
    log_done "bootstrap phase 2 complete"
}

main "$@"
