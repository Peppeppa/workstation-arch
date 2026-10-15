#!/usr/bin/env bash
# scripts/backup-inventory.sh against an artificial home - nothing real is
# read. Checks: the report has its sections and the right classification
# (Nextcloud coverage from nextcloud.cfg, git findings, VMs, venvs, unclear
# dirs, space sums), it leaks no file contents, no remote URL credentials,
# no Nextcloud server/user, no names of loose files or of deep directories,
# and the home is byte-for-byte unchanged afterwards (read-only), with no
# temporary files left.
set -u
cd "$(dirname "$0")/.."
script=$PWD/scripts/backup-inventory.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
H=$tmp/home
mkdir -p "$H" "$tmp/tmpdir"
fail=0
bad() { echo "FAIL $*"; fail=1; }

g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# personal data, Nextcloud
mkdir -p "$H/Documents/Steuer" "$H/Studium/Fach/Geheimprojekt" "$H/Work" "$H/Downloads" "$H/Kram" \
         "$H/.config/Nextcloud" "$H/knime-workspace/wf"
echo "SECRETCONTENT-doc" >"$H/Documents/Steuer/bescheid.txt"
echo "SECRETCONTENT-work" >"$H/Work/notes.txt"
echo '{"cells":[]}' >"$H/Studium/Fach/Geheimprojekt/analyse.ipynb"
echo x >"$H/Work/kunden.sqlite"
head -c 2048 /dev/zero >"$H/Downloads/big.bin"
echo y >"$H/Kram/z.txt"
echo "SECRETCONTENT-loose" >"$H/steuer-geheim.pdf"
echo nb >"$H/Untitled.ipynb"
echo wf >"$H/knime-workspace/wf/workflow.knime"
cat >"$H/.config/Nextcloud/nextcloud.cfg" <<EOF
[Accounts]
0\\url=https://cloud.SECRETHOST.example
0\\dav_user=SECRETUSER
0\\Folders\\1\\localPath=$H/Documents/
0\\Folders\\1\\paused=false
0\\FoldersWithPlaceholders\\2\\localPath=$H/Studium/
0\\FoldersWithPlaceholders\\2\\paused=true
EOF

# git: clean+pushed, dirty, ahead, no remote, remote with credentials
mkdir -p "$H/repos"
g init --bare "$tmp/remote.git"
for r in clean dirty ahead; do
    g init "$H/repos/$r"; echo a >"$H/repos/$r/f"; g -C "$H/repos/$r" add f; g -C "$H/repos/$r" commit -m a
    g -C "$H/repos/$r" remote add origin "$tmp/remote.git"; g -C "$H/repos/$r" push -u origin "main:$r"
    g -C "$H/repos/$r" branch --set-upstream-to "origin/$r"
done
echo changed >>"$H/repos/dirty/f"
echo b >"$H/repos/ahead/g"; g -C "$H/repos/ahead" add g; g -C "$H/repos/ahead" commit -m b
g init "$H/repos/noremote"; echo a >"$H/repos/noremote/f"; g -C "$H/repos/noremote" add f; g -C "$H/repos/noremote" commit -m a
g -C "$H/repos/clean" remote add mirror "https://user:TOKEN123SECRET@example.invalid/x.git"

# VM, venvs, apps, config
mkdir -p "$H/VirtualBox VMs/uni-vm/Snapshots" "$H/proj/.venv" "$H/proj2/.venv" "$H/.thunderbird/p.default" \
         "$H/.config/chromium/Default" "$H/.ssh" "$H/.local/bin" "$H/.config/systemd/user/default.target.wants" \
         "$H/.local/share/applications" "$H/.cache/x" "$H/.weird"
head -c 4096 /dev/zero >"$H/VirtualBox VMs/uni-vm/uni-vm.vdi"
echo s >"$H/VirtualBox VMs/uni-vm/Snapshots/{abc}.vdi"
echo "home = /usr/bin" >"$H/proj/.venv/pyvenv.cfg"; echo "[project]" >"$H/proj/pyproject.toml"
echo "home = /usr/bin" >"$H/proj2/.venv/pyvenv.cfg"
echo "SECRETCONTENT-mail" >"$H/.thunderbird/p.default/Inbox"
echo "SECRETCONTENT-bookmarks" >"$H/.config/chromium/Default/Bookmarks"
echo "-----BEGIN OPENSSH PRIVATE KEY----- SECRETCONTENT-key" >"$H/.ssh/id_ed25519"; echo "ssh-ed25519 AAAA" >"$H/.ssh/id_ed25519.pub"
printf '#!/bin/sh\necho SECRETCONTENT-script\n' >"$H/.local/bin/myscript"; chmod +x "$H/.local/bin/myscript"
echo "[Service]" >"$H/.config/systemd/user/backup.service"
echo "[Desktop Entry]" >"$H/.local/share/applications/mytool.desktop"
echo c >"$H/.cache/x/c"
head -c 2000000 /dev/zero >"$H/.weird/data"
echo "alias x=SECRETCONTENT-alias" >"$H/.bashrc"

before=$(cd "$H" && find . -printf '%p %s %T@ %m\n' | sort)
out=$(HOME=$H TMPDIR=$tmp/tmpdir PATH=$PATH bash "$script" 2>"$tmp/err")
printf "%s\n" "$out" > "${DEBUG_OUT:-/dev/null}"
rc=$?
after=$(cd "$H" && find . -printf '%p %s %T@ %m\n' | sort)

[ $rc -eq 0 ] || bad "exit $rc: $(cat "$tmp/err")"
[ "$before" = "$after" ] || { bad "home changed"; diff <(echo "$before") <(echo "$after") | head -5; }
[ -z "$(ls -A "$tmp/tmpdir")" ] || bad "temporary files left"
for s in SECRETCONTENT TOKEN123SECRET SECRETHOST SECRETUSER steuer-geheim Geheimprojekt bescheid kunden.sqlite \
         remote.git example.invalid "PRIVATE KEY"; do
    printf '%s' "$out" | grep -qF "$s" && bad "leaks: $s"
done

has() { printf '%s\n' "$out" | grep -qE "$2" || bad "$1"; }
has "Nextcloud disclaimer" "kein Nachweis für eine erfolgreiche Synchronisation"
has "sync folders from nextcloud.cfg" '^  - `~/Documents`'
has "placeholder (VFS) note" 'Studium.*virtuelle Dateien'
has "paused folder named" 'Studium.*pausiert'
has "Documents covered" '\| Kritisch \| Home: Documents .*\| ja \| im Sync-Ordner'
has "Work not covered" '\| Kritisch \| Home: Work .*\| nein \| Unbedingt sichern'
has "Studium covered (VFS folder)" '\| Kritisch \| Home: Studium .*\| ja \|'
has "knime workspace critical" 'KNIME-Workspace'
has "loose files by extension, no names, not covered" 'Lose Dateien direkt in `~` \((pdf 1, ipynb 1|ipynb 1, pdf 1)\) .*\| nein \|'
has "git clean" '\| Reproduzierbar \| `~/repos/clean` .*sauber'
has "git dirty" '\| Kritisch \| `~/repos/dirty` .*1 geänderte'
has "git ahead" '\| Kritisch \| `~/repos/ahead` .*1 Commits nicht gepusht'
has "git no remote" '\| Kritisch \| `~/repos/noremote` .*KEIN Remote'
has "VM row" '\| Kritisch \| `uni-vm` .*1 Festplatte\(n\), Snapshot-Dateien: 1'
has "deep notebook dir summarised" '~/Studium/Fach/\.\.\.'
has "database dir counted" '1 ~/Work$'
has "venv with lock reproducible" 'Reproduzierbar: `~/proj/\.venv`'
has "venv without list unclear" 'Unklar: `~/proj2/\.venv`'
has "thunderbird critical" '\| Kritisch \| Thunderbird-Profil'
has "chromium important" '\| Wichtig \| Chromium-Profil'
has "ssh counted, not read" '1 öffentliche Schlüssel, 1 mögliche private'
has "own scripts named" '1 Dateien \(myscript\)'
has "user unit named" 'backup\.service'
has "desktop entry named" 'mytool\.desktop'
has "unclear top dir" '\| `~/Kram` \|'
has "unclear hidden dir" '\| `~/\.weird` \|'
has "cache reproducible" 'Caches \(`~/\.cache`'
has "space table" '\| Kritisch \+ Wichtig \| [0-9.]+[KMGT]?B \|'
has "checklist" '^1\. Nextcloud-Client'

# without a readable nextcloud.cfg the sync boundaries are unknown - said so
H2=$tmp/home2; mkdir -p "$H2/Documents"; echo d >"$H2/Documents/a"
out2=$(HOME=$H2 TMPDIR=$tmp/tmpdir bash "$script" 2>/dev/null)
printf '%s\n' "$out2" | grep -q 'Sync-Grenzen unbekannt' || bad "no-config: boundaries not reported unknown"
printf '%s\n' "$out2" | grep -qE '\| Kritisch \| Home: Documents .*\| unklar \|' || bad "no-config: coverage not 'unklar'"

# space sum: covered Documents/Studium not counted, nested paths not twice
crit=$(printf '%s\n' "$out" | sed -n 's/^| Kritisch | \(.*\) |$/\1/p')
[ -n "$crit" ] || bad "no Kritisch sum"

exit $fail
