#!/bin/sh
# Managed by Ansible (roles/hyprland/files/session-stop.sh) - do not edit
# by hand. Deployed to ~/.local/libexec/workstation/session-stop.
#
# session-stop NAME... - the stop half of Hyprland's session lifecycle
# (session.lua: hl.on("hyprland.start") starts the helpers, this runs from
# hl.on("hyprland.shutdown") via a blocking os.execute). It ends the
# session's Wayland clients while the compositor still serves them, in
# this order:
#
#  1. SIGTERM to the named helpers that THIS Hyprland started (its direct
#     children with that process name) and to hyprlock (hypridle's child).
#     None of them installs a SIGTERM handler, so the kernel ends them at
#     once - no exit path runs. Without this they noticed the vanished
#     display themselves and ran their exit path against a dead
#     connection: hyprpolkitagent SIGSEGV and xdg-desktop-portal-hyprland
#     SIGSEGV in their atexit destructors, hypridle SIGABRT (uncaught
#     exception) - a coredump per helper on every logout.
#  2. Stop of the portal frontend and its two Wayland-bound backends
#     (systemd --user, D-Bus-activated; they start again on first use next
#     login). Backends: same crash otherwise, and the unit was left
#     "failed" (Broken pipe). Frontend in the same stop: if it outlived the
#     backends it re-activated xdg-desktop-portal-gtk a moment later to
#     close the portal sessions of the dying apps (Chromium) - without a
#     display, so that unit failed instead ("cannot open display").
#     Deliberately not a stop of graphical-session.target, although these
#     units are PartOf= it: that also stops the a11y bus, and its
#     D-Bus-activated at-spi2-registryd then stays behind - one leaked
#     process per logout (measured on arch-dev). Nothing else bound to the
#     session crashed (gvfs, a11y keep running for the user manager like
#     before).
#
# Both waits are bounded (0.5 s / 2 s) and wait for an observable state,
# not a fixed delay: Hyprland is blocked inside os.execute meanwhile, so a
# helper that needed a compositor round trip to exit would otherwise stall
# the logout. Hyprland blocks SIGTERM/SIGCHLD (signalfd) and os.execute
# children inherit that mask - so no `timeout`/`wait`-on-signal here; kill
# itself is unaffected. Nothing else (no coredump handling, no restart).

p=$$
while [ "$p" -gt 1 ] && [ "$(cat "/proc/$p/comm" 2>/dev/null)" != Hyprland ]; do
    p=$(cut -d' ' -f4 "/proc/$p/stat" 2>/dev/null) || exit 0
done
[ "$p" -gt 1 ] || exit 0

targets=""
for name in "$@"; do
    targets="$targets $(pgrep -P "$p" -x "$name")"
done
targets="$targets $(pgrep -u "$(id -u)" -x hyprlock)"
# shellcheck disable=SC2086 # word splitting of the pid list is intended
kill -TERM $targets 2>/dev/null

i=0
while [ $i -lt 10 ]; do
    alive=0
    for t in $targets; do
        s=$(cut -d' ' -f3 "/proc/$t/stat" 2>/dev/null) || continue
        [ "$s" = Z ] || alive=1   # a zombie is gone; Hyprland reaps it later
    done
    [ $alive -eq 0 ] && break
    sleep 0.05
    i=$((i + 1))
done

portals="xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service"
# shellcheck disable=SC2086
systemctl --user --no-block stop $portals
i=0
# shellcheck disable=SC2086
while [ $i -lt 40 ] && systemctl --user -q is-active $portals; do
    sleep 0.05
    i=$((i + 1))
done
exit 0
