#!/usr/bin/env bash
# system-rollback (roles/recovery): the guarded root switch, on stubs.
#
# Safe anywhere: the top level is a temporary directory whose "subvolumes"
# are plain directories (stub btrfs: snapshot = cp -a, delete = rm -rf),
# mount/umount/mountpoint/findmnt/ukify/objcopy/snapper/logger are stubs,
# every fixed path of the script and its library points into $tmp. Checks:
#   - success: @ = the snapshot, the old @ kept as @broken-*, main UKI rebuilt
#     from the stored snapshot-boot UKI, vmlinuz copied, the restore record
#     written into the NEW system
#   - failure between the two renames: the old @ is put back, nothing left over
#   - failure while building the UKI: nothing changed
#   - a kernel without a stored or matching UKI: refused, nothing changed
# Run by tests/run.sh.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" -ne 0 ]; then echo "FAIL $1"; fail=1; fi; }

mkdir -p "$tmp/stub" "$tmp/lib" "$tmp/run" "$tmp/boot/EFI/Linux" "$tmp/boot/EFI/workstation/snapshots" "$tmp/top"
subst() { sed -e "s#/usr/local/lib/workstation/#$tmp/lib/#g" -e "s#/run/workstation-recovery#$tmp/run#g" \
              -e "s#/\.snapshots/#$tmp/top/@snapshots/#g" -e "s#/boot/#$tmp/boot/#g" -e "s#MAIN_UKI=/boot#MAIN_UKI=$tmp/boot#"; }
subst < "$repo/roles/recovery/files/system-rollback" > "$tmp/system-rollback"
python3 - "$repo/roles/recovery/templates/recovery-lib.sh.j2" <<'EOF' | subst > "$tmp/lib/recovery-lib.sh"
import jinja2, shlex, sys
env = jinja2.Environment(keep_trailing_newline=True, undefined=jinja2.StrictUndefined)
env.filters["quote"] = shlex.quote
print(env.from_string(open(sys.argv[1]).read()).render(playbook_dir="/nonexistent"), end="")
EOF
sed -i "s#^RECOVERY_TOP=.*#RECOVERY_TOP=$tmp/top#" "$tmp/lib/recovery-lib.sh"

stub() { printf '#!/bin/bash\n%s\n' "$2" > "$tmp/stub/$1"; chmod +x "$tmp/stub/$1"; }
stub id 'echo 0'
stub mount ':'
stub umount ':'
stub mountpoint 'exit 0'
stub logger "echo \"logger \$*\" >> $tmp/log"
stub findmnt 'case "$*" in *FSTYPE*) echo btrfs;; *SOURCE*) echo /dev/mapper/root;; *) echo rw,subvol=/@;; esac'
stub snapper 'echo "number|date|description"; echo "30|2026-10-10 18:46:21|Test A"'
stub btrfs 'case "$1 $2" in "subvolume snapshot") cp -a "$3" "$4";; "subvolume delete") rm -rf "$3";; "property set") :;; *) exit 9;; esac'
# objcopy: the fake UKI is "UNAME=<k>" text
stub objcopy 'for a; do case $a in --only-section=.uname) u=1;; esac; done; eval "in=\${$(($#-1))}"; eval "out=\${$#}"
if [ -n "${u:-}" ]; then sed -n "s/^UNAME=//p" "$in" | tr -d "\n" > "$out"; else cp "$in" "$out"; fi'
stub ukify "for a; do case \$a in --output=*) o=\${a#--output=};; --uname=*) k=\${a#--uname=};; --cmdline=*) c=\${a#--cmdline=};; esac; done
[ -f $tmp/ukify-fails ] && { echo 'ukify: boom' >&2; exit 1; }
printf 'UNAME=%s\nCMDLINE=%s\nREBUILT\n' \"\$k\" \"\$c\" > \"\$o\""
stub mv "[ -f $tmp/mv-fails ] && [ \"\$1\" = $tmp/top/@rollback-new ] && { echo 'mv: boom' >&2; exit 1; }; exec /usr/bin/mv \"\$@\""
export PATH="$tmp/stub:$PATH"

setup() { # fresh top level: @ (current), snapshot 30 (kernel $1), stored UKI for 7.2.9, main UKI 7.2.9
    rm -rf "$tmp/top"/* "$tmp/log" "$tmp/ukify-fails" "$tmp/mv-fails"
    mkdir -p "$tmp/top/@/etc/kernel" "$tmp/top/@snapshots/30/snapshot/etc/kernel" "$tmp/top/@snapshots/30/snapshot/usr/lib/modules/$1"
    echo current > "$tmp/top/@/etc/state"
    echo snapshot > "$tmp/top/@snapshots/30/snapshot/etc/state"
    echo "rootflags=subvol=@ rw" > "$tmp/top/@snapshots/30/snapshot/etc/kernel/cmdline"
    echo "vmlinuz $1" > "$tmp/top/@snapshots/30/snapshot/usr/lib/modules/$1/vmlinuz"
    printf 'UNAME=7.2.9\nMAIN\n' > "$tmp/boot/EFI/Linux/arch-linux.efi"
    printf 'UNAME=7.2.9\nSTORED\n' > "$tmp/boot/EFI/workstation/snapshots/7.2.9.efi"
}
run() { bash "$tmp/system-rollback" 30 --yes >"$tmp/out" 2>&1; }
broken() { ls -d "$tmp/top"/@broken-* 2>/dev/null | wc -l; }

# ---- success
setup 7.2.9
run; rc=$?; check "success: exit 0 ($(tail -1 "$tmp/out"))" $rc
[ "$(cat "$tmp/top/@/etc/state")" = snapshot ]; check "success: @ is the snapshot" $?
[ "$(broken)" = 1 ] && [ "$(cat "$tmp/top"/@broken-*/etc/state)" = current ]; check "success: old @ kept as @broken-*" $?
grep -q REBUILT "$tmp/boot/EFI/Linux/arch-linux.efi" && grep -q "CMDLINE=rootflags=subvol=@ rw" "$tmp/boot/EFI/Linux/arch-linux.efi"
check "success: main UKI rebuilt with the restored system's cmdline" $?
[ "$(cat "$tmp/boot/vmlinuz-linux")" = "vmlinuz 7.2.9" ]; check "success: vmlinuz from the snapshot" $?
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['snapshot']==30 and d['previous'].startswith('@broken-') and d['description']=='2026-10-10 18:46:21 - Test A'" \
    "$tmp/top/@/var/lib/workstation/snapshot-restore.json"; check "success: restore record in the new @" $?
[ ! -e "$tmp/top/@rollback-new" ] && [ ! -e "$tmp/boot/EFI/Linux/arch-linux.efi.rollback" ]; check "success: nothing left over" $?

# ---- failure between the two renames: @ is put back
setup 7.2.9
touch "$tmp/mv-fails"
run; [ $? -ne 0 ]; check "mv failure: exit != 0" $?
[ "$(cat "$tmp/top/@/etc/state" 2>/dev/null)" = current ]; rc=$?; check "mv failure: the old @ is back ($(tail -2 "$tmp/out" | tr '\n' ' '))" $rc
[ "$(broken)" = 0 ] && [ ! -e "$tmp/top/@rollback-new" ]; check "mv failure: no @broken-*, no @rollback-new left" $?
grep -q MAIN "$tmp/boot/EFI/Linux/arch-linux.efi" && [ ! -e "$tmp/boot/EFI/Linux/arch-linux.efi.rollback" ]; check "mv failure: main UKI unchanged" $?
grep -q "FAILED" "$tmp/log"; check "mv failure: logged" $?

# ---- failure while building the UKI: nothing changed
setup 7.2.9
touch "$tmp/ukify-fails"
run; [ $? -ne 0 ]; check "ukify failure: exit != 0" $?
[ "$(cat "$tmp/top/@/etc/state")" = current ] && [ "$(broken)" = 0 ] && [ ! -e "$tmp/top/@rollback-new" ]; check "ukify failure: @ untouched, nothing left" $?

# ---- kernel without a stored or matching UKI: refused
setup 7.0.0
run; [ $? -ne 0 ] && grep -q "no stored UKI" "$tmp/out"; check "kernel without UKI: refused" $?
[ "$(cat "$tmp/top/@/etc/state")" = current ] && [ "$(broken)" = 0 ]; check "kernel without UKI: nothing changed" $?

[ $fail -eq 0 ] && echo "system-rollback: all checks passed"
exit $fail
