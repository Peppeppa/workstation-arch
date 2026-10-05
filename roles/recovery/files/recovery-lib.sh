# Managed by Ansible (roles/recovery/files/recovery-lib.sh) - do not edit by hand.
# Deployed to /usr/local/lib/workstation/recovery-lib.sh, sourced by
# system-update, system-snapshot and system-rollback (docs/recovery-design.md).
# Shared pieces only: the top-level mount, recovery slots, UKI building and
# the checks every command needs. Runs as root (the callers ensure it).
#
# A recovery slot is a matching pair taken from the RUNNING system:
#   snapper snapshot <n> (read-only, pinned)   /.snapshots/<n>/snapshot
#   writable boot clone                        @recovery/<slot>
#   UKI = the booted UKI's kernel + initramfs  /boot/EFI/workstation/recovery/<slot>.efi
#         with the recovery cmdline embedded (ukify)
#   systemd-boot entry (BLS Type #1)           /boot/loader/entries/workstation-recovery-<slot>.conf
# Slots: before-update, previous-update, known-good.

set -euo pipefail

RECOVERY_TOP=/run/workstation-recovery/top
RECOVERY_UKI_DIR=/boot/EFI/workstation/recovery
RECOVERY_BROKEN_DIR=/boot/EFI/workstation/broken
RECOVERY_ENTRY_DIR=/boot/loader/entries
MAIN_UKI=/boot/EFI/Linux/arch-linux.efi
KERNEL_CMDLINE=/etc/kernel/cmdline
SLOTS="before-update previous-update known-good"

die() { echo "${0##*/}: $*" >&2; exit 1; }
say() { echo "${0##*/}: $*"; }

need_root() { [ "$(id -u)" -eq 0 ] || die "run as root (sudo ${0##*/} ...)"; }

# The subvolume / is mounted from: "@" normally, "@recovery/<slot>" in a slot boot.
root_subvol() { findmnt -no OPTIONS / | tr ',' '\n' | sed -n 's#^subvol=/##p'; }

booted_from_main() { [ "$(root_subvol)" = "@" ]; }

root_device() { findmnt -no SOURCE / | sed 's/\[.*//'; }

top_mount() {
    mkdir -p "$RECOVERY_TOP"
    mountpoint -q "$RECOVERY_TOP" || mount -o subvolid=5 "$(root_device)" "$RECOVERY_TOP"
}

top_umount() { if mountpoint -q "$RECOVERY_TOP"; then umount "$RECOVERY_TOP"; fi; }

uki_uname() { objcopy -O binary --only-section=.uname "$1" /dev/stdout 2>/dev/null | tr -d '\0'; }

boot_epoch() { awk '/^btime/{print $2}' /proc/stat; }

# The main UKI is the image this system booted only if it was not rebuilt
# since the boot and carries the running kernel. A slot is never made from
# an untested, freshly generated UKI.
main_uki_is_booted() {
    [ -f "$MAIN_UKI" ] || return 1
    [ "$(uki_uname "$MAIN_UKI")" = "$(uname -r)" ] || return 1
    [ "$(stat -c %Y "$MAIN_UKI")" -lt "$(boot_epoch)" ]
}

# Bytes free on the root filesystem (Btrfs estimate) and on the ESP.
root_free_bytes() { btrfs filesystem usage -b / 2>/dev/null | awk '/Free \(estimated\)/{print $3; exit}'; }
root_size_bytes() { btrfs filesystem usage -b / 2>/dev/null | awk '/Device size/{print $3; exit}'; }
esp_free_bytes() { df -B1 --output=avail /boot | tail -1 | tr -d ' '; }

# The cmdline a UKI gets: the system's own one, root pointed elsewhere for
# a slot, never resume= in a slot (a recovery kernel must not resume an
# image written by another kernel).
slot_cmdline() {
    sed -E "s#rootflags=subvol=@(\s|\$)#rootflags=subvol=@recovery/$1\1#; s/(^| )resume(_offset)?=[^ ]*//g" "$KERNEL_CMDLINE" \
        | tr -s ' ' | sed 's/ *$//' | tr -d '\n'
    printf ' noresume'
}

# build_uki <source uki> <cmdline> <output>
build_uki() {
    local src=$1 cmd=$2 out=$3 w
    w=$(mktemp -d)
    for s in linux initrd osrel splash; do
        objcopy -O binary --only-section=".$s" "$src" "$w/$s"
    done
    [ -s "$w/linux" ] && [ -s "$w/initrd" ] || { rm -rf "$w"; die "$src has no kernel/initramfs sections"; }
    local splash=()
    [ -s "$w/splash" ] && splash=(--splash="$w/splash")
    ukify build --linux="$w/linux" --initrd="$w/initrd" --os-release="@$w/osrel" "${splash[@]}" \
        --uname="$(uki_uname "$src")" --cmdline="$cmd" --output="$out.tmp" 2>&1 >/dev/null \
        | { grep -v '^Wrote unsigned' >&2 || true; }
    rm -rf "$w"
    mv -f "$out.tmp" "$out"
}

# The snapper snapshot number a slot currently uses ("" if none).
slot_snapshot() {
    snapper -c root --csvout --separator '|' list --columns number,userdata 2>/dev/null \
        | awk -F'|' -v s="slot=$1" 'NR > 1 && index($2, s) { n = $1 } END { if (n != "") print n }'
}

slot_title() {
    case $1 in
        before-update)   echo "Recovery: before the last update" ;;
        previous-update) echo "Recovery: before the update before" ;;
        known-good)      echo "Recovery: known good" ;;
    esac
}

write_entry() { # slot, label
    cat > "$RECOVERY_ENTRY_DIR/workstation-recovery-$1.conf.tmp" <<EOF
# Managed by system-update/system-snapshot (roles/recovery) - do not edit.
title   $(slot_title "$1") - $2
sort-key zz-workstation-recovery-$1
uki     /EFI/workstation/recovery/$1.efi
EOF
    mv -f "$RECOVERY_ENTRY_DIR/workstation-recovery-$1.conf.tmp" "$RECOVERY_ENTRY_DIR/workstation-recovery-$1.conf"
}

# Remove a slot's clone, UKI and entry; its snapshot loses the pin and the
# slot mark (snapper's number cleanup may then remove it like any other).
drop_slot() {
    local slot=$1 n
    n=$(slot_snapshot "$slot")
    [ -n "$n" ] && snapper -c root modify --cleanup-algorithm number --userdata "slot=" "$n" >/dev/null 2>&1 || true
    [ -d "$RECOVERY_TOP/@recovery/$slot" ] && btrfs subvolume delete "$RECOVERY_TOP/@recovery/$slot" >/dev/null
    rm -f "$RECOVERY_UKI_DIR/$slot.efi" "$RECOVERY_ENTRY_DIR/workstation-recovery-$slot.conf"
}

# Move slot a's parts to slot b (b is dropped first).
move_slot() {
    local a=$1 b=$2 n label
    n=$(slot_snapshot "$a")
    [ -n "$n" ] || return 0
    drop_slot "$b"
    label=$(sed -n 's/^title .* - //p' "$RECOVERY_ENTRY_DIR/workstation-recovery-$a.conf" 2>/dev/null || true)
    mv "$RECOVERY_TOP/@recovery/$a" "$RECOVERY_TOP/@recovery/$b"
    sed -i -E "s#subvol=/@recovery/$a(\s)#subvol=/@recovery/$b\1#" "$RECOVERY_TOP/@recovery/$b/etc/fstab"
    echo "$b" > "$RECOVERY_TOP/@recovery/$b/etc/workstation-recovery-slot"
    build_uki "$RECOVERY_UKI_DIR/$a.efi" "$(slot_cmdline "$b")" "$RECOVERY_UKI_DIR/$b.efi"
    rm -f "$RECOVERY_UKI_DIR/$a.efi" "$RECOVERY_ENTRY_DIR/workstation-recovery-$a.conf"
    snapper -c root modify --userdata "slot=$b" "$n" >/dev/null
    write_entry "$b" "${label:-snapshot $n}"
}

# make_slot <slot> <snapshot number> <label>: the snapshot must have been
# taken from the running @ a moment ago (callers), with the booted UKI.
make_slot() {
    local slot=$1 n=$2 label=$3 clone
    clone="$RECOVERY_TOP/@recovery/$slot"
    mkdir -p "$RECOVERY_TOP/@recovery" "$RECOVERY_UKI_DIR"
    drop_slot "$slot"
    btrfs subvolume snapshot "/.snapshots/$n/snapshot" "$clone" >/dev/null
    # the clone mounts itself as /; @home, @log, @pkg, @snapshots stay shared
    sed -i -E "s#^(\S+\s+/\s+btrfs\s+\S*)subvol=/@(\s)#\1subvol=/@recovery/$slot\2#" "$clone/etc/fstab"
    grep -qE "subvol=/@recovery/$slot(\s)" "$clone/etc/fstab" || die "could not point $clone/etc/fstab at the clone"
    echo "$slot" > "$clone/etc/workstation-recovery-slot"
    build_uki "$MAIN_UKI" "$(slot_cmdline "$slot")" "$RECOVERY_UKI_DIR/$slot.efi"
    snapper -c root modify --cleanup-algorithm "" --userdata "slot=$slot" "$n" >/dev/null
    write_entry "$slot" "$label"
}

repo_commit() {
    local repo
    repo=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/workstation-arch
    git -C "$repo" log -1 --format=%h 2>/dev/null || echo "?"
}
