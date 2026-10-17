#!/bin/sh
# Managed by Ansible (roles/hyprland/files/xwayland-scale.sh) - do not edit.
# Hyprland leaves XWayland clients unscaled (xwayland.force_zero_scaling in
# conf/appearance.lua): sharp, but at 100 % size on a scaled monitor. A GTK
# app on XWayland can draw itself at that scale instead:
#
#   xwayland-scale                 print the focused monitor's scale (e.g. 1.25)
#   xwayland-scale exec CMD [ARGS] run CMD on XWayland (GDK_BACKEND=x11) with
#                                  GDK_DPI_SCALE = that scale
#
# One-shot, no state; the scale is read once at start (a later change in
# Appearance applies at the app's next start). Anything unreadable = 1.
scale=$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    ms = json.load(sys.stdin)
    m = next((m for m in ms if m.get("focused")), ms[0])
    s = float(m["scale"])
    print(f"{s:g}" if 0.25 <= s <= 4 else 1)
except Exception:
    print(1)
' 2>/dev/null) || scale=1
[ -n "$scale" ] || scale=1

case ${1-} in
    "") echo "$scale" ;;
    exec)
        shift
        [ $# -ge 1 ] || { echo "usage: xwayland-scale [exec COMMAND [ARGS...]]" >&2; exit 2; }
        GDK_BACKEND=x11 GDK_DPI_SCALE=$scale exec "$@" ;;
    *) echo "usage: xwayland-scale [exec COMMAND [ARGS...]]" >&2; exit 2 ;;
esac
