#!/usr/bin/env bash
set -euo pipefail

# workstation-arch bootstrap orchestrator.
#
# Run as a normal user from a clean Arch Linux install:
#   ./bootstrap.sh
#
# Do NOT run this with sudo. Individual steps escalate privileges only
# where required.
#
# Phase 1 (current): base bootstrap framework + minimal base packages.
# Desktop phases (Hyprland, Quickshell, audio/Bluetooth stacks, ...) are
# not implemented yet.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT

# shellcheck source=scripts/helpers/log.sh
source "${REPO_ROOT}/scripts/helpers/log.sh"
# shellcheck source=scripts/install/00-environment.sh
source "${REPO_ROOT}/scripts/install/00-environment.sh"
# shellcheck source=scripts/install/10-packages.sh
source "${REPO_ROOT}/scripts/install/10-packages.sh"

main() {
    log_info "workstation-arch bootstrap - phase 1"

    validate_environment
    install_base_packages

    log_info "phase 1 summary: environment validated, base packages ensured from packages/base.txt"
    log_done "bootstrap phase 1 complete"
}

main "$@"
