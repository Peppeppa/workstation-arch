#!/usr/bin/env bash
# LUKS recovery key + header backup onto an offline stick - run LOCALLY by
# the owner, as root, in a terminal on the machine itself (never over SSH,
# never by Ansible or an agent): docs/recovery/README.md,
# docs/release/LUKS_RECOVERY_PLAN.md. Used for H14 on the laptop (2026-10-14).
#
#   sudo scripts/luks-recovery-setup.sh <mountpoint of the recovery stick>
#
# The LUKS partition is the one /etc/kernel/cmdline unlocks
# (cryptdevice=PARTUUID=...). It must have exactly one keyslot. Steps:
# systemd-cryptenroll --recovery-key (asks for the existing passphrase, shows
# the key once) -> the owner writes it on paper -> screen cleared -> key typed
# back from paper and the passphrase tested, each against its own slot ->
# luksHeaderBackup to <stick>/luks-header.img (never overwritten, 0400),
# byte-compared with the disk, passphrase tested through the backup.
# Secrets exist only on the TTY; the output lines are statuses only.
# A failure stops; nothing is removed (a new keyslot stays - decide by hand).
set -uo pipefail

[ $# = 1 ] || { echo "usage: sudo $0 <mountpoint of the recovery stick>" >&2; exit 2; }
MNT=$1
HDR=$MNT/luks-header.img
log() { echo "[luks-recovery] $*"; }
fail() { log "FAIL $*"; exit 1; }
slots() { cryptsetup luksDump "$L" | grep -cE '^\s+[0-9]+: luks2'; }
recovery_slot() {
    cryptsetup luksDump --dump-json-metadata "$L" | python3 -c '
import json, sys
d = json.load(sys.stdin)
s = [k for t in d["tokens"].values() if t["type"] == "systemd-recovery" for k in t["keyslots"]]
print(s[0] if len(s) == 1 else "")'
}
clear_screen() { printf '\033[H\033[2J\033[3J'; }
try3() { # what, cryptsetup args...
    local what=$1 i; shift
    for i in 1 2 3; do
        cryptsetup open --test-passphrase "$@" && { log "$what PASS"; return 0; }
        echo "not accepted ($i/3)"
    done
    fail "$what"
}

[ "$(id -u)" = 0 ] || fail "run as root (sudo)"
[ -t 0 ] || fail "needs a terminal (secrets are typed here)"
PARTUUID=$(sed -n 's/.*cryptdevice=PARTUUID=\([^:]*\):.*/\1/p' /etc/kernel/cmdline)
[ -n "$PARTUUID" ] || fail "no cryptdevice=PARTUUID= in /etc/kernel/cmdline"
L=/dev/disk/by-partuuid/$PARTUUID
cryptsetup isLuks --type luks2 "$L" || fail "$L is not LUKS2"
UUID=$(cryptsetup luksUUID "$L")
log "LUKS partition $(readlink -f "$L") UUID $UUID"
findmnt -rn "$MNT" >/dev/null || fail "$MNT is not a mountpoint"
[ "$(findmnt -rno SOURCE /)" != "$(findmnt -rno SOURCE "$MNT")" ] || fail "$MNT is on the system disk"
[ ! -e "$HDR" ] || fail "$HDR exists - not overwritten"
n=$(slots)
[ "$n" = 1 ] || fail "expected exactly 1 keyslot, found $n"

echo "A recovery key is ADDED in a free keyslot; the existing passphrase stays."
read -r -p "Enter = continue, Ctrl+C = abort (nothing changed) " _
systemd-cryptenroll --recovery-key "$L" || fail "systemd-cryptenroll"
RS=$(recovery_slot)
[ "$(slots)" = 2 ] && [ -n "$RS" ] && [ "$RS" != 0 ] || fail "keyslot layout after enrolling"
log "recovery key in keyslot $RS"
read -r -p "Write the key on paper NOW, compare twice, then Enter (screen is cleared) " _
clear_screen
echo "Type the recovery key FROM THE PAPER:"
try3 "recovery key (slot $RS)" --key-slot "$RS" "$L"
clear_screen
echo "Type the existing passphrase:"
try3 "passphrase (slot 0)" --key-slot 0 "$L"

(umask 077; cryptsetup luksHeaderBackup "$L" --header-backup-file "$HDR") || fail "luksHeaderBackup"
chmod 0400 "$HDR"; sync
SZ=$(stat -c %s "$HDR")
cmp -n "$SZ" "$HDR" "$L" || fail "backup differs from the disk header"
[ "$(cryptsetup luksUUID "$HDR")" = "$UUID" ] || fail "backup UUID"
log "header backup $HDR ($SZ bytes, sha256 $(sha256sum "$HDR" | cut -d' ' -f1))"
echo "Type the existing passphrase once more (checked against the BACKUP header):"
try3 "passphrase via backup header" --key-slot 0 --header "$HDR" "$L"
sync
log "done - next: the docs + SHA256SUMS on the stick (docs/recovery/README.md), unmount"
