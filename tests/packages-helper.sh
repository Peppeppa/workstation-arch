#!/usr/bin/env bash
# Regression test for workstation-pkg (roles/packages): the six list/filter
# pipelines, what each action finally runs, and that a cancelled pick does
# nothing. pacman, fzf, sudo, yay, flatpak and curl are stubs with fixed
# fixtures - nothing is installed, removed or downloaded. Run by tests/run.sh.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" -ne 0 ]; then echo "FAIL $1"; fail=1; fi; }

python3 - "$repo" "$tmp/workstation-pkg" <<'EOF' || exit 1
import sys, jinja2, yaml
repo, out = sys.argv[1:]
v = yaml.safe_load(open(repo + "/roles/packages/defaults/main.yml"))
v.update(yaml.safe_load(open(repo + "/roles/network/defaults/main.yml")))
v["fortinet_vpn_enabled"] = True
open(out, "w").write(jinja2.Template(open(repo + "/roles/packages/templates/workstation-pkg.j2").read()).render(**v))
EOF
chmod +x "$tmp/workstation-pkg"
mkdir -p "$tmp/stub"

cat > "$tmp/stub/pacman" <<'EOF'
#!/bin/bash
case "$*" in
  -Ss) printf '%s\n' "core/acl 2.4.0-1 [installed]" "    Access control list utilities" \
                     "extra/htop 3.4.1-1" "    Interactive process viewer" \
                     "extra/zellij 0.43.1-1" "    A terminal workspace with batteries included" \
                     "extra/firefox 150.0-1 [installed: 149.0-1]" "    Standalone web browser" ;;
  -Qs) printf '%s\n' "local/acl 2.4.0-1" "    Access control list utilities" \
                     "local/git 2.55.0-1" "    the fast distributed version control system" \
                     "local/glibc 2.43-1" "    GNU C Library" \
                     "local/yay 13.0.1-1" "    Yet another yogurt" \
                     "local/networkmanager-fortisslvpn 1.4.0-6" "    NetworkManager VPN plugin for Fortinet SSLVPN" \
                     "local/hello-aur 1.0-1" "    an explicit AUR package" \
                     "local/libfoo-aur 2.0-1" "    an AUR package pulled in as a dependency" ;;
  -Qqen) printf '%s\n' git ;;                                   # explicit + native (glibc, acl: dependencies)
  -Qqem) printf '%s\n' yay networkmanager-fortisslvpn hello-aur ;;   # explicit + foreign (libfoo-aur: dependency)
  -Qq) printf '%s\n' acl git glibc yay hello-aur libfoo-aur ;;
  *) echo "pacman $*" >> "$TMPLOG" ;;
esac
EOF
cat > "$tmp/stub/flatpak" <<'EOF'
#!/bin/bash
case "$*" in
  "list --app --columns=application") printf '%s\n' md.obsidian.Obsidian ;;
  "list --app --columns=name,application,origin") printf 'Obsidian\tmd.obsidian.Obsidian\tflathub\n' ;;
  "remote-ls --app --columns=name,application,description,origin")
      printf 'Obsidian\tmd.obsidian.Obsidian\tKnowledge base\tflathub\nLocalSend\torg.localsend.localsend_app\tShare files\tflathub\n' ;;
  *) echo "flatpak $*" >> "$TMPLOG" ;;
esac
EOF
# fzf: record what it was offered, pick the lines matching $PICK (none if
# $PICK is empty = Esc -> exit 130).
cat > "$tmp/stub/fzf" <<'EOF'
#!/bin/bash
cat > "$TMPOFFER"
[ -n "${PICK:-}" ] || exit 130
grep -E "$PICK" "$TMPOFFER" || exit 1
EOF
printf '#!/bin/bash\n"$@"\n' > "$tmp/stub/sudo"
printf '#!/bin/bash\necho "yay $*" >> "$TMPLOG"\n' > "$tmp/stub/yay"
cat > "$tmp/stub/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$TMPLOG"
echo '{"type":"search","resultcount":3,"results":[
 {"Name":"hello-aur","Version":"1.0-1","Description":"installed already","NumVotes":50},
 {"Name":"tiny-aur","Version":"0.2-1","Description":"a small tool","NumVotes":5},
 {"Name":"popular-aur","Version":"3.1-2","Description":"many votes","NumVotes":900}]}'
EOF
chmod +x "$tmp/stub/"*
export PATH="$tmp/stub:$PATH" TMPLOG="$tmp/log" TMPOFFER="$tmp/offer"
W="$tmp/workstation-pkg"
run() { : > "$tmp/log"; : > "$tmp/offer"; PICK="$1" "$W" "$2" </dev/null >/dev/null 2>&1; }

# ---- Arch install: sync packages with repo + description, installed out ----
run '^htop ' install-arch
grep -q '^htop  .*extra .*Interactive process viewer' "$tmp/offer"; check "install-arch: name, repo, description offered" $?
! grep -q -E '^(acl|firefox) ' "$tmp/offer"; check "install-arch: installed packages (incl. outdated) not offered" $?
grep -qx 'pacman -S --needed -- htop' "$tmp/log"; check "install-arch: pacman -S --needed, no --noconfirm" $?

# ---- Arch remove: explicit + native only ------------------------------------
run '^git ' remove-arch
[ "$(awk '{print $1}' "$tmp/offer" | tr '\n' ' ')" = "git " ]; check "remove-arch: only explicit native (no dependencies, no AUR)" $?
grep -qx 'pacman -Rns -- git' "$tmp/log"; check "remove-arch: pacman -Rns" $?

# ---- AUR remove: explicit + foreign only, baseline marked --------------------
run '^hello-aur ' remove-aur
[ "$(awk '{print $1}' "$tmp/offer" | sort | tr '\n' ' ')" = "hello-aur networkmanager-fortisslvpn yay " ]
check "remove-aur: explicit foreign only (dependency libfoo-aur not offered)" $?
grep -q '^yay .*\[workstation baseline\]' "$tmp/offer" && ! grep -q '^hello-aur .*baseline' "$tmp/offer"
check "remove-aur: provisioned AUR packages marked as baseline" $?
grep -qx 'pacman -Rns -- hello-aur' "$tmp/log"; check "remove-aur: pacman -Rns" $?

# ---- AUR search (fzf reload): votes first, installed out, >= 2 chars ---------
out=$("$W" _aur-search he 2>/dev/null)
[ "$(awk '{print $1}' <<<"$out" | tr '\n' ' ')" = "popular-aur tiny-aur " ]; check "aur-search: installed out, most votes first: '$out'" $?
grep -q 'rpc/v5/search/he' "$tmp/log"; check "aur-search: queries the AUR RPC (name-desc)" $?
[ "$("$W" _aur-search h)" = "(type at least 2 characters)" ]; check "aur-search: 1 character -> no query" $?

# ---- Flatpak install / remove -------------------------------------------------
run 'org.localsend' install-flatpak
! grep -q 'md.obsidian.Obsidian' "$tmp/offer" && grep -q 'LocalSend.*org.localsend.localsend_app.*Share files' "$tmp/offer"
check "install-flatpak: name + app id + description, installed apps out" $?
grep -qx 'flatpak install flathub org.localsend.localsend_app' "$tmp/log"; check "install-flatpak: flatpak install <remote> <id>" $?
run 'Obsidian' remove-flatpak
grep -qx 'flatpak uninstall -- md.obsidian.Obsidian' "$tmp/log"; check "remove-flatpak: uninstall by app id, no --unused" $?

# ---- Esc in fzf: nothing runs ------------------------------------------------
for a in install-arch remove-arch remove-aur install-flatpak remove-flatpak; do
    run '' "$a"
    [ ! -s "$tmp/log" ]; check "$a: Esc -> no action" $?
done
run '' install-aur
! grep -q '^yay' "$tmp/log"; check "install-aur: Esc -> no action" $?

[ $fail -eq 0 ] && echo "packages-helper: all checks passed"
exit $fail
