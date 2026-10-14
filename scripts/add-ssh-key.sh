#!/usr/bin/env bash
# Add the user's own SSH public key to ~/.ssh/authorized_keys - by hand,
# once per fresh install, as the normal user (README "Firewall and SSH").
# A public key, no secret. Not run by bootstrap.sh or Ansible; no sudo, no
# sshd configuration, no service restart.
#
#   scripts/add-ssh-key.sh
#
# Idempotent: the key counts as present when a line holds the same key type
# and key material (any comment, any options in front). Existing lines are
# kept; the file is only appended to, never rewritten. ~/.ssh ends up 700,
# authorized_keys 600, both owned by the user (sshd's StrictModes).
#
# Exit: 0 = added or already present, 1 = stopped (nothing changed).
set -euo pipefail

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9SzQ6w0lsAcNWu+1NoT6CCKzt2L7nrK+I9sbwRnEjs'

say() { printf '[REPO] %s\n' "$*"; }
stop() { printf '[REPO] STOP: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || stop "run as your normal user, not root"
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || stop "HOME is not a directory"

# The key: type + base64 material, and ssh-keygen must accept it.
[[ $KEY =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\ ([A-Za-z0-9+/]+={0,3})( .*)?$ ]] ||
    stop "the key in this script is not a public key line"
TYPE=${BASH_REMATCH[1]} BLOB=${BASH_REMATCH[3]}
command -v ssh-keygen >/dev/null || stop "ssh-keygen not found (package openssh)"
FP=$(ssh-keygen -lf - <<<"$KEY" 2>/dev/null) || stop "ssh-keygen rejects the key in this script"
FP=${FP#* } FP=${FP%% *}

SSH_DIR=$HOME/.ssh AUTH=$HOME/.ssh/authorized_keys
uid=$(id -u)
for p in "$SSH_DIR" "$AUTH"; do
    [ ! -L "$p" ] || stop "$p is a symlink - add the key to its target by hand"
done
[ -e "$SSH_DIR" ] || mkdir -m 700 -- "$SSH_DIR"
[ -d "$SSH_DIR" ] || stop "$SSH_DIR exists but is not a directory"
[ "$(stat -c %u -- "$SSH_DIR")" = "$uid" ] || stop "$SSH_DIR is not owned by you"
chmod 700 -- "$SSH_DIR"
if [ ! -e "$AUTH" ]; then
    (umask 077 && : >> "$AUTH")
fi
[ -f "$AUTH" ] || stop "$AUTH exists but is not a regular file"
[ "$(stat -c %u -- "$AUTH")" = "$uid" ] || stop "$AUTH is not owned by you"
chmod 600 -- "$AUTH"

if awk -v t="$TYPE" -v b="$BLOB" '
        /^[[:space:]]*(#|$)/ { next }
        { for (i = 1; i < NF; i++) if ($i == t && $(i + 1) == b) found = 1 }
        END { exit !found }' "$AUTH"; then
    say "already present: $FP ($AUTH)"
    exit 0
fi
# Append only; a last line without newline gets one first.
if [ -s "$AUTH" ] && [ -n "$(tail -c 1 -- "$AUTH")" ]; then
    printf '\n' >> "$AUTH"
fi
printf '%s\n' "$KEY" >> "$AUTH"
say "added: $FP ($AUTH)"
