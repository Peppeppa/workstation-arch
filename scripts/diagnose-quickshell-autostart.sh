#!/usr/bin/env bash
# Read-only diagnostic for the Quickshell-under-Hyprland autostart
# investigation (see AGENTS.md Next Milestone). Collects evidence about
# why `hl.exec_cmd("quickshell")` in the Hyprland Lua `hyprland.start`
# handler does not leave a running Quickshell process, even though the
# same handler successfully starts hyprpolkitagent/mako.
#
# This script changes NO packages, NO services, and NO repo-managed
# config. The only runtime side effect it may ever cause is the single
# controlled late-exec test in run_late_exec_test() below, and only
# when no Quickshell process is already running at the time it runs.
#
# Usage (from an SSH shell, after the graphical Hyprland session has
# been started interactively - see README.md):
#   /path/to/workstation-arch/scripts/diagnose-quickshell-autostart.sh
#
# No `set -e`: a later section must still run and report even if an
# earlier check finds nothing or a command it probes for is missing.
set -uo pipefail

readonly SELF_UID="${UID}"
readonly SELF_USER="$(id -un)"
readonly XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${SELF_UID}}"
readonly HOME_DIR="${HOME:-/home/${SELF_USER}}"
readonly DIAG_DIR="${XDG_RUNTIME_DIR}/quickshell-autostart-diag"
readonly KEYWORD_PATTERN='error|fatal|crash|wayland|egl|fail|exit|signal|warn'

# Populated by collect_hyprland(), read by later sections.
HYPR_PID=""
HYPR_SIG=""
HYPR_START_EPOCH=""

section() {
    printf '\n===== %s =====\n' "$1"
}

subsection() {
    printf '\n--- %s ---\n' "$1"
}

# --------------------------------------------------------------------
# 0. Basics
# --------------------------------------------------------------------
collect_basics() {
    date
    printf 'UID=%s user=%s\n' "${SELF_UID}" "${SELF_USER}"

    subsection "package versions"
    local pkg
    for pkg in hyprland quickshell qt6-base qt6-declarative upower; do
        pacman -Q "${pkg}" 2>/dev/null || printf '%s: NOT INSTALLED\n' "${pkg}"
    done

    subsection "command resolution"
    printf 'command -v quickshell: %s\n' "$(command -v quickshell 2>/dev/null || echo 'not found')"
    printf 'command -v qs:         %s\n' "$(command -v qs 2>/dev/null || echo 'not found')"
    printf 'readlink -f /usr/bin/quickshell: %s\n' "$(readlink -f /usr/bin/quickshell 2>/dev/null || echo 'n/a')"
    printf 'readlink -f /usr/bin/qs:         %s\n' "$(readlink -f /usr/bin/qs 2>/dev/null || echo 'n/a')"
}

# --------------------------------------------------------------------
# 1. Hyprland: PID, signature, monitors, runtime files, config block
# --------------------------------------------------------------------
find_hypr_pid() {
    pgrep -x Hyprland 2>/dev/null | head -n1
}

# Reads HYPRLAND_INSTANCE_SIGNATURE straight out of the running
# Hyprland process's own environment (authoritative - no directory
# name guessing). Falls back to scanning /run/user/$UID/hypr/ for the
# newest directory containing a live .socket.sock if /proc/<pid>/environ
# cannot be read.
find_hypr_signature() {
    local pid="$1" sig=""
    if [[ -n "${pid}" && -r "/proc/${pid}/environ" ]]; then
        sig="$(tr '\0' '\n' <"/proc/${pid}/environ" 2>/dev/null | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -n1)"
    fi
    if [[ -z "${sig}" && -d "${XDG_RUNTIME_DIR}/hypr" ]]; then
        sig="$(find "${XDG_RUNTIME_DIR}/hypr" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %f\n' 2>/dev/null \
            | sort -rn | awk 'NR==1{print $2}')"
    fi
    printf '%s' "${sig}"
}

collect_hyprland() {
    HYPR_PID="$(find_hypr_pid)"
    if [[ -z "${HYPR_PID}" ]]; then
        printf 'No running Hyprland process found (pgrep -x Hyprland). Nothing further in this section can be collected.\n'
        return
    fi
    printf 'Hyprland PID: %s\n' "${HYPR_PID}"
    ps -o pid,ppid,lstart,etimes,cmd -p "${HYPR_PID}" 2>/dev/null

    HYPR_START_EPOCH="$(ps -o lstart= -p "${HYPR_PID}" 2>/dev/null | xargs -I{} date -d {} +%s 2>/dev/null || true)"
    printf 'Hyprland start epoch: %s\n' "${HYPR_START_EPOCH:-unknown}"

    subsection "process ancestry / wrapper (e.g. start-hyprland), Xwayland"
    # Matches on a bounded binary/arg0 name, not a bare substring like
    # "PID" - that previously also matched unrelated args such as
    # "...crashpad-handler-pid=3889" on any process with "pid" anywhere
    # in its command line.
    {
        local header
        read -r header
        printf '%s\n' "${header}"
        grep -Ei '(^|[ /])(Hyprland|Xwayland|start-hyprland|hyprpolkitagent|mako|quickshell|qs)([ -]|$)' || printf '(no matches)\n'
    } < <(ps -eo pid,ppid,lstart,args 2>/dev/null)

    HYPR_SIG="$(find_hypr_signature "${HYPR_PID}")"
    if [[ -z "${HYPR_SIG}" ]]; then
        printf 'Could not determine HYPRLAND_INSTANCE_SIGNATURE - hyprctl/late-exec steps below will be skipped.\n'
    else
        printf 'HYPRLAND_INSTANCE_SIGNATURE: %s\n' "${HYPR_SIG}"
        subsection "hyprctl monitors"
        HYPRLAND_INSTANCE_SIGNATURE="${HYPR_SIG}" hyprctl monitors 2>&1 || printf '(hyprctl monitors failed)\n'

        subsection "Hyprland runtime dir (${XDG_RUNTIME_DIR}/hypr/${HYPR_SIG})"
        ls -la "${XDG_RUNTIME_DIR}/hypr/${HYPR_SIG}" 2>/dev/null || printf '(not found)\n'
    fi

    subsection "deployed ~/.config/hypr/hyprland.lua - hyprland.start block"
    local hyprconf="${HOME_DIR}/.config/hypr/hyprland.lua"
    if [[ -r "${hyprconf}" ]]; then
        local block
        block="$(awk '/hl\.on\("hyprland\.start"/{p=1} p{print} p && /^end\)/{exit}' "${hyprconf}")"
        if [[ -n "${block}" ]]; then
            printf '%s\n' "${block}"
        else
            printf '(no hl.on("hyprland.start", ...) block found in %s)\n' "${hyprconf}"
        fi
    else
        printf '(%s not found or not readable)\n' "${hyprconf}"
    fi
}

# --------------------------------------------------------------------
# 2. Current lifecycle processes
# --------------------------------------------------------------------
show_process() {
    local label="$1" pattern="$2"
    local pids
    pids="$(pgrep -f "${pattern}" 2>/dev/null || true)"
    if [[ -z "${pids}" ]]; then
        printf '%s: not running\n' "${label}"
        return
    fi
    printf '%s:\n' "${label}"
    # shellcheck disable=SC2086
    ps -o pid,ppid,lstart,etimes,args -p $(echo "${pids}" | tr '\n' ',' | sed 's/,$//') 2>/dev/null
}

collect_lifecycle() {
    show_process "hyprpolkitagent" '/usr/lib/hyprpolkitagent/hyprpolkitagent'
    show_process "mako" '(^|/)mako($| )'
    show_process "quickshell/qs" '(^|/)(quickshell|qs)($| )'
}

# --------------------------------------------------------------------
# 3./5. Quickshell runtime directory tree + logs
# --------------------------------------------------------------------
# Prints a text log's tail and any keyword matches; refuses to dump
# non-text (e.g. Quickshell's own binary log.qslog) files - reports
# their size/mtime instead.
dump_log_file() {
    local f="$1"
    printf '  %s (mtime %s, %s bytes)\n' "${f}" \
        "$(date -d "@$(stat -c %Y "${f}" 2>/dev/null || echo 0)" 2>/dev/null || echo unknown)" \
        "$(stat -c %s "${f}" 2>/dev/null || echo '?')"
    if file -b --mime-encoding "${f}" 2>/dev/null | grep -qv binary; then
        printf '    last 20 lines:\n'
        tail -n 20 "${f}" 2>/dev/null | sed 's/^/      /'
        printf '    keyword matches (%s):\n' "${KEYWORD_PATTERN}"
        grep -niE "${KEYWORD_PATTERN}" "${f}" 2>/dev/null | sed 's/^/      /' || printf '      (none)\n'
    else
        printf '    (binary log, not dumped - size/mtime above only)\n'
    fi
}

collect_quickshell_runtime() {
    local label="$1"
    local qsdir="${XDG_RUNTIME_DIR}/quickshell"
    if [[ ! -d "${qsdir}" ]]; then
        printf 'No %s - Quickshell has never created runtime state for this user since boot.\n' "${qsdir}"
        return
    fi

    subsection "tree (${label})"
    find "${qsdir}" -maxdepth 3 2>/dev/null | sort

    subsection "by-pid symlinks -> targets (${label})"
    if [[ -d "${qsdir}/by-pid" ]]; then
        find "${qsdir}/by-pid" -maxdepth 1 -type l 2>/dev/null | while IFS= read -r link; do
            printf '  %s -> %s\n' "${link}" "$(readlink -f "${link}" 2>/dev/null || echo '?')"
        done
    else
        printf '  (no by-pid dir)\n'
    fi

    subsection "instance logs, oldest to newest (${label})"
    local logs
    logs="$(find "${qsdir}/by-id" -maxdepth 2 -type f \( -name 'log.log' -o -name 'log.qslog' \) 2>/dev/null \
        | xargs -r -I{} stat -c '%Y %n' {} 2>/dev/null | sort -n | awk '{print $2}')"
    if [[ -z "${logs}" ]]; then
        printf '  (no instance logs found)\n'
    else
        while IFS= read -r f; do
            dump_log_file "${f}"
        done <<<"${logs}"
    fi
}

# --------------------------------------------------------------------
# 4. Controlled late-exec test (the only permitted runtime side effect)
# --------------------------------------------------------------------
LATE_EXEC_RAN=0
LATE_EXEC_MARKER_EPOCH=""
LATE_EXEC_RESULT=""   # one of: skipped-already-running / still-running / exit0 / exitN / signal / exec-failed / no-evidence

run_late_exec_test() {
    # Baseline PIDs are captured once and reused below (never
    # re-queried as "already") so a process that was already running
    # before this test can never be mistaken for one this test itself
    # started.
    local baseline_pids
    baseline_pids="$(pgrep -f '(^|/)(quickshell|qs)($| )' 2>/dev/null || true)"
    if [[ -n "${baseline_pids}" ]]; then
        printf 'Skipped: a quickshell/qs process is already running (PID(s): %s). Per the task scope, the late-exec test only runs when none is running.\n' "${baseline_pids//$'\n'/, }"
        LATE_EXEC_RESULT="skipped-already-running"
        return
    fi

    if [[ -z "${HYPR_SIG}" ]]; then
        printf 'Skipped: no valid HYPRLAND_INSTANCE_SIGNATURE was found in section 1, cannot drive hyprctl.\n'
        LATE_EXEC_RESULT="no-evidence"
        return
    fi

    mkdir -p "${DIAG_DIR}"
    LATE_EXEC_MARKER_EPOCH="$(date +%s)"
    local wrapper="${DIAG_DIR}/late-exec-${LATE_EXEC_MARKER_EPOCH}.sh"
    local logfile="${DIAG_DIR}/late-exec-${LATE_EXEC_MARKER_EPOCH}.log"

    cat >"${wrapper}" <<EOF
#!/bin/sh
{
  echo "QS_LATE_EXEC_START=\$(date +%s)"
  echo "PATH=\$PATH"
  echo "WAYLAND_DISPLAY=\$WAYLAND_DISPLAY"
  echo "XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR"
  echo "ULIMIT_N=\$(ulimit -n)"
  quickshell
  echo "QS_EXIT=\$?"
} >"${logfile}" 2>&1
EOF
    chmod +x "${wrapper}"

    printf 'Triggering exactly one hl.exec_cmd() call via the live Hyprland instance (same codepath as hyprland.start):\n'
    printf '  wrapper: %s\n  log:     %s\n' "${wrapper}" "${logfile}"
    LATE_EXEC_RAN=1

    if ! HYPRLAND_INSTANCE_SIGNATURE="${HYPR_SIG}" hyprctl eval "hl.exec_cmd(\"${wrapper}\")" 2>&1; then
        printf 'hyprctl eval itself failed - could not even dispatch the test.\n'
        LATE_EXEC_RESULT="no-evidence"
        return
    fi

    # Bounded, one-shot wait for this single triggered attempt to either
    # produce an exit code or leave a running process - not a persistent
    # watchdog/polling mechanism. baseline_pids is empty here (guaranteed
    # by the early return above), but we still diff against it rather
    # than trusting a fresh pgrep outright, in case something unrelated
    # to this test starts a quickshell/qs process in the same window.
    local waited=0
    local pid=""
    while [[ "${waited}" -lt 5 ]]; do
        sleep 1
        waited=$((waited + 1))
        pid="$(pgrep -f '(^|/)(quickshell|qs)($| )' 2>/dev/null | grep -vxF "${baseline_pids}" | head -n1 || true)"
        if [[ -n "${pid}" ]] || grep -q '^QS_EXIT=' "${logfile}" 2>/dev/null; then
            break
        fi
    done

    subsection "late-exec log"
    if [[ -r "${logfile}" ]]; then
        cat "${logfile}"
    else
        printf '(log file was never created - the exec_cmd dispatch itself may have failed before the wrapper could even run)\n'
    fi

    if [[ -n "${pid}" ]]; then
        printf 'Process still running after the test: PID %s\n' "${pid}"
        ps -o pid,ppid,lstart,args -p "${pid}" 2>/dev/null
        LATE_EXEC_RESULT="still-running"
        return
    fi

    local exit_code="" sig_name=""
    exit_code="$(sed -n 's/^QS_EXIT=//p' "${logfile}" 2>/dev/null | tail -n1)"
    if [[ -z "${exit_code}" ]]; then
        printf 'No QS_EXIT line appeared within 5s and no process is running - inconclusive within the wait window.\n'
        LATE_EXEC_RESULT="no-evidence"
    elif [[ "${exit_code}" -eq 0 ]]; then
        printf 'Quickshell exited with code 0 and left no running process.\n'
        LATE_EXEC_RESULT="exit0"
    elif [[ "${exit_code}" -eq 126 || "${exit_code}" -eq 127 ]]; then
        printf 'Exit code %s: the shell itself could not exec quickshell (not found / not executable).\n' "${exit_code}"
        LATE_EXEC_RESULT="exec-failed"
    elif [[ "${exit_code}" -gt 128 ]] && sig_name="$(kill -l "$((exit_code - 128))" 2>/dev/null)" && [[ -n "${sig_name}" ]]; then
        # 128+N is only a real signal death if N is an actual signal
        # number on this system (kill -l validates that) - an exit code
        # like 255 is extremely commonly a program's own chosen "generic
        # failure" exit status (128+127, and 127 is not a valid signal),
        # not proof of being killed by a signal. Treat it as exitN
        # instead, below, rather than misreport it as a signal.
        local sig_num=$((exit_code - 128))
        printf 'Exit code %s: terminated by signal %s (%s).\n' "${exit_code}" "${sig_num}" "${sig_name}"
        LATE_EXEC_RESULT="signal"
    else
        printf 'Exit code %s (non-zero; quickshell'\''s own chosen exit status - not a validated signal-termination code).\n' "${exit_code}"
        LATE_EXEC_RESULT="exitN"
    fi
}

# --------------------------------------------------------------------
# 6. Attribution: original hyprland.start attempt vs. this test
# --------------------------------------------------------------------
attribute_runtime_dirs() {
    local qsdir="${XDG_RUNTIME_DIR}/quickshell/by-id"
    if [[ ! -d "${qsdir}" ]]; then
        printf '(no %s - nothing to attribute)\n' "${qsdir}"
        return
    fi
    if [[ -z "${HYPR_START_EPOCH}" ]]; then
        printf 'Cannot attribute: Hyprland start time was not determined in section 1.\n'
        return
    fi

    find "${qsdir}" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | while read -r mtime dir; do
        local mtime_int="${mtime%.*}"
        if [[ "${LATE_EXEC_RAN}" -eq 1 && -n "${LATE_EXEC_MARKER_EPOCH}" && "${mtime_int}" -ge "${LATE_EXEC_MARKER_EPOCH}" ]]; then
            printf '  %s (mtime %s) -> this script'\''s own late-exec test (created at/after its marker)\n' "${dir}" "${mtime_int}"
        elif [[ "${mtime_int}" -ge "${HYPR_START_EPOCH}" ]]; then
            printf '  %s (mtime %s) -> created after Hyprland started and before the late-exec test; most likely the original hyprland.start attempt, but any manual testing done in between cannot be excluded\n' "${dir}" "${mtime_int}"
        else
            printf '  %s (mtime %s) -> predates this Hyprland session entirely (stale, from an earlier boot/session)\n' "${dir}" "${mtime_int}"
        fi
    done
}

# --------------------------------------------------------------------
# 7. Summary
# --------------------------------------------------------------------
print_summary() {
    local qs_now
    qs_now="$(pgrep -f '(^|/)(quickshell|qs)($| )' 2>/dev/null || true)"

    printf 'Facts:\n'
    printf '  - Hyprland running: %s\n' "$([[ -n "${HYPR_PID}" ]] && echo "yes (PID ${HYPR_PID})" || echo "no")"
    printf '  - quickshell/qs running right now: %s\n' "$([[ -n "${qs_now}" ]] && echo "yes (PID ${qs_now})" || echo "no")"
    printf '  - late-exec test outcome: %s\n' "${LATE_EXEC_RESULT:-not run}"

    printf '\nVerdict: '
    if [[ -z "${HYPR_PID}" ]]; then
        printf 'E. Not evaluable - Hyprland itself is not running, so nothing about its autostart handler can be assessed right now.\n'
        return
    fi

    case "${LATE_EXEC_RESULT:-}" in
    skipped-already-running)
        printf 'E. Not evaluable this run - a quickshell/qs process was already running when this script started, so the late-exec test was skipped and section 3/5 above (same before/after data) is what you have. If that process traces back to the original hyprland.start attempt (check its start time against Hyprland'\''s start time above), that alone would support the opposite of A/B; re-run this script right after a fresh graphical login with nothing manually started yet for a clean read.\n'
        ;;
    still-running)
        if [[ -z "${qs_now}" ]]; then
            printf 'E. Inconclusive - the late-exec test reported a running process but none is found now; re-run.\n'
        else
            printf 'C. Quickshell works when launched via a controlled late hl.exec_cmd() (same mechanism, same environment family) after the session is already up, but no process was observed from the original hyprland.start attempt (see sections 2-3 above for whether one ever appeared). This points at something timing-/session-readiness-specific to the hyprland.start moment itself, not a generic Hyprland/Quickshell incompatibility.\n'
        fi
        ;;
    exit0 | exitN | signal | exec-failed)
        printf 'D. Quickshell also fails/exits on a controlled late hl.exec_cmd() (outcome: %s) - this is NOT purely a hyprland.start-timing issue; something about this exact spawn mechanism (fork + cleared signal mask + restored NOFILE limit + stdout/stderr to /dev/null + `/bin/sh -c`) causes Quickshell specifically to fail regardless of when it runs. See the late-exec log above for the captured exit code/signal and environment.\n' "${LATE_EXEC_RESULT}"
        ;;
    no-evidence | "")
        if [[ -z "${qs_now}" ]]; then
            printf 'E. Inconclusive - no quickshell/qs process is running and the late-exec test could not produce a clear result (see section 4 above for why: missing signature, dispatch failure, or timeout). Re-run with a longer wait or check /run/user/%s/quickshell manually for anything the 5s window missed.\n' "${SELF_UID}"
        else
            printf 'Quickshell IS currently running (PID %s) - re-run this script right after a fresh graphical login, before anything else touches Quickshell, for a clean A/B/C/D read.\n' "${qs_now}"
        fi
        ;;
    *)
        printf 'E. Inconclusive - unexpected internal state (LATE_EXEC_RESULT=%s). Re-run.\n' "${LATE_EXEC_RESULT:-}"
        ;;
    esac

    printf '\nNote on A vs. B: this script cannot distinguish "never started at hyprland.start" (A) from "started and exited before this script ran" (B) unless section 3 above shows a Quickshell by-id runtime directory attributable to the original hyprland.start window (see the attribution list). Check that list: an attributed directory with a log.log reaching "Configuration Loaded" supports B; no attributable directory at all supports A.\n'
}

main() {
    section "0. BASICS"
    collect_basics

    section "1. HYPRLAND"
    collect_hyprland

    section "2. LIFECYCLE PROCESSES"
    collect_lifecycle

    section "3. QUICKSHELL RUNTIME (before late-exec test)"
    collect_quickshell_runtime "before"

    section "4. CONTROLLED LATE-EXEC TEST"
    run_late_exec_test

    section "5. QUICKSHELL RUNTIME (after late-exec test)"
    collect_quickshell_runtime "after"

    section "6. RUNTIME DIRECTORY ATTRIBUTION"
    attribute_runtime_dirs

    section "DIAGNOSIS SUMMARY"
    print_summary
}

main "$@"
