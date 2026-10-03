#!/usr/bin/env bash
# screenshots feature (screenshots_enabled / screenshots_ocr_enabled,
# see group_vars/all.yml and docs/feature-architecture.md) - on-demand
# helper started by a Hyprland keybind (roles/hyprland/templates/
# hyprland.lua.j2), never a persistent process. Modes:
#   screenshot smart   - interactive slurp selection: drag a region OR
#                        click a window (click on empty desktop = that
#                        monitor), then save PNG + copy image to clipboard
#   screenshot ocr     - same selection, OCR'd locally by tesseract
#                        (deu+eng); recognized TEXT goes to the clipboard,
#                        no PNG is ever written to disk
#   screenshot monitor - grim of the currently focused Hyprland monitor
#                        (no default keybind - kept for manual/later use)
# Every mode confirms via a mako notification and exits; nothing is
# left running and nothing touches the network.
set -euo pipefail

mode="${1:-}"
case "${mode}" in
smart | ocr | monitor) ;;
*)
    echo "usage: screenshot {smart|ocr|monitor}" >&2
    exit 1
    ;;
esac

# Visible window rectangles ("x,y wxh", one per line - slurp's stdin box
# format) from one on-demand pair of hyprctl calls. slurp itself does
# the click-vs-drag distinction: a click selects the smallest given box
# under the cursor, a drag selects a free region - no coordinate
# heuristics here. "Visible" = mapped, not hidden, and on a workspace a
# monitor is currently showing (its open special workspace instead of
# the normal one underneath it, if any), or pinned. python3 instead of
# jq: already a hard requirement for Ansible itself on this machine.
window_boxes() {
    python3 -c '
import json, sys
monitors, clients = json.loads(sys.argv[1]), json.loads(sys.argv[2])
shown = set()
for m in monitors:
    special = m.get("specialWorkspace", {}).get("id", 0)
    shown.add(special if special else m["activeWorkspace"]["id"])
for c in clients:
    if not c.get("mapped") or c.get("hidden"):
        continue
    if c["workspace"]["id"] not in shown and not c.get("pinned"):
        continue
    (x, y), (w, h) = c["at"], c["size"]
    if w > 0 and h > 0:
        print(f"{x},{y} {w}x{h}")
' "$(hyprctl monitors -j)" "$(hyprctl clients -j)"
}

# Prints the selected geometry, or nothing if the user cancelled.
# -o adds each monitor as a box too, so a click on empty desktop selects
# that monitor instead of a useless 1x1 point (windows always win: they
# are the smaller box). slurp rejects a blank stdin line, so only feed
# it boxes when there are any.
select_geometry() {
    local boxes
    boxes="$(window_boxes)"
    if [[ -n "${boxes}" ]]; then
        printf '%s\n' "${boxes}" | slurp -o
    else
        slurp -o </dev/null
    fi
}

if [[ "${mode}" == "ocr" ]]; then
    # slurp exits non-zero (and prints nothing) on Escape - quiet exit,
    # clipboard untouched. Same for the smart mode below.
    geometry="$(select_geometry)" || exit 0
    [[ -n "${geometry}" ]] || exit 0

    # PNG streams grim -> tesseract over a pipe: no temp file, nothing
    # on disk at all. -s 2 upscales the capture, which markedly improves
    # tesseract's accuracy on ~96 dpi screen text. deu+eng in one pass
    # handles mixed German/English text (incl. umlauts/ß). The
    # "Estimating resolution" chatter on stderr is noise, real failures
    # still surface via the exit status (pipefail).
    if ! text="$(grim -s 2 -g "${geometry}" - | tesseract stdin stdout -l deu+eng 2>/dev/null)"; then
        notify-send "OCR fehlgeschlagen" "tesseract konnte das Bild nicht verarbeiten"
        exit 1
    fi
    # Drop the page-break form feed tesseract appends, then trailing
    # whitespace.
    text="${text//$'\f'/}"
    text="${text%"${text##*[![:space:]]}"}"
    if [[ -z "${text//[[:space:]]/}" ]]; then
        notify-send "OCR: kein Text erkannt" "Zwischenablage unverändert"
        exit 0
    fi
    printf '%s' "${text}" | wl-copy --type text/plain
    notify-send "OCR-Text kopiert" "$(printf '%s' "${text}" | head -c 120)"
    exit 0
fi

# xdg-user-dir (xdg-user-dirs package) respects a user-customized
# ~/.config/user-dirs.dirs (generated once by roles/desktop) and falls
# back to ~/Pictures on its own otherwise.
pictures_dir="$(xdg-user-dir PICTURES 2>/dev/null || true)"
pictures_dir="${pictures_dir:-${HOME}/Pictures}"
target_dir="${pictures_dir}/Screenshots"
mkdir -p "${target_dir}"

timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
dest="${target_dir}/Screenshot_${timestamp}.png"
suffix=2
while [[ -e "${dest}" ]]; do
    dest="${target_dir}/Screenshot_${timestamp}_${suffix}.png"
    suffix=$((suffix + 1))
done

# Capture into a private tmp file in the same directory first (mktemp
# default mode 0600) so a mid-capture failure never leaves a broken or
# empty file at the final, user-visible name, and the final `mv` is a
# same-filesystem rename, not a copy.
tmp_dest="$(mktemp "${target_dir}/.screenshot-XXXXXX.png")"
trap 'rm -f "${tmp_dest}"' EXIT

case "${mode}" in
smart)
    geometry="$(select_geometry)" || exit 0
    [[ -n "${geometry}" ]] || exit 0
    grim -g "${geometry}" "${tmp_dest}"
    ;;
monitor)
    # The focused-monitor name is the one piece of state this needs
    # from Hyprland; a single on-demand `hyprctl` call for a user-
    # triggered action is not the polling this project's performance
    # rules forbid (see AGENTS.md Performance Rules / docs/idle-
    # baseline.md).
    monitor_name="$(hyprctl monitors -j | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    if m.get("focused"):
        print(m["name"])
        break
')"
    if [[ -z "${monitor_name}" ]]; then
        echo "screenshot: could not determine the focused monitor" >&2
        exit 1
    fi
    grim -o "${monitor_name}" "${tmp_dest}"
    ;;
esac

# mv -n: never overwrite a file another instance created at the same
# name since the existence check above.
mv -n "${tmp_dest}" "${dest}"
[[ -e "${tmp_dest}" ]] && { echo "screenshot: ${dest} appeared concurrently" >&2; exit 1; }
trap - EXIT

wl-copy --type image/png < "${dest}"

notify-send "Screenshot gespeichert" "${dest}"
