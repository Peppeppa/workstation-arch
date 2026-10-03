#!/usr/bin/env bash
# screenshots feature (screenshots_enabled, see group_vars/all.yml and
# docs/feature-architecture.md) - on-demand helper started by a
# Hyprland keybind (roles/hyprland/templates/hyprland.lua.j2), never a
# persistent process. Modes:
#   screenshot region  - interactive slurp selection, then grim
#   screenshot monitor - grim of the currently focused Hyprland monitor
# Both save a PNG under the XDG Pictures/Screenshots directory, copy it
# to the Wayland clipboard, and confirm via a mako notification.
set -euo pipefail

mode="${1:-}"
if [[ "${mode}" != "region" && "${mode}" != "monitor" ]]; then
    echo "usage: screenshot {region|monitor}" >&2
    exit 1
fi

# xdg-user-dir (xdg-user-dirs package) respects a user-customized
# ~/.config/user-dirs.dirs and otherwise falls back to the standard
# ~/Pictures default on its own - no generator run needed first.
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
region)
    # slurp exits non-zero (and prints nothing) when the user cancels
    # with Escape - exit quietly with no file, no clipboard write, no
    # notification. Not an error.
    geometry="$(slurp)" || exit 0
    [[ -n "${geometry}" ]] || exit 0
    grim -g "${geometry}" "${tmp_dest}"
    ;;
monitor)
    # The focused-monitor name is the one piece of state this needs
    # from Hyprland; a single on-demand `hyprctl` call for a user-
    # triggered keybind is not the polling this project's performance
    # rules forbid (see AGENTS.md Performance Rules / docs/idle-
    # baseline.md). json.tool-free parsing via python3 avoids adding a
    # jq dependency: python3 is already a hard requirement for Ansible
    # itself to run on this machine.
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

mv "${tmp_dest}" "${dest}"
trap - EXIT

wl-copy --type image/png < "${dest}"

notify-send "Screenshot gespeichert" "${dest}"
