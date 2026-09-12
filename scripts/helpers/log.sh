# Logging helpers for bootstrap scripts.
# Meant to be sourced by bootstrap.sh, not executed directly.

log_check() {
    printf '[CHECK]   %s\n' "$*"
}

log_skip() {
    printf '[SKIP]    %s\n' "$*"
}

log_install() {
    printf '[INSTALL] %s\n' "$*"
}

log_ok() {
    printf '[OK]      %s\n' "$*"
}

log_info() {
    printf '[INFO]    %s\n' "$*"
}

log_done() {
    printf '[DONE]    %s\n' "$*"
}

log_error() {
    printf '[ERROR]   %s\n' "$*" >&2
}
