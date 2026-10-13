#!/usr/bin/env bash
# Fake "sudo -S": reads the password line, records only whether it matched.
IFS= read -r pw
[ "$pw" = "sim-secret" ] && echo ok >> "$HOME/sudo-auth" || { echo bad >> "$HOME/sudo-auth"; exit 1; }
exec "$@"
