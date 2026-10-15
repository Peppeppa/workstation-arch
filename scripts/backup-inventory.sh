#!/usr/bin/env bash
# Backup inventory before erasing a machine (docs/migration/BACKUP_INVENTORY.md).
# Run by the owner, as the normal user, on the machine that will be erased:
#
#   bash backup-inventory.sh > ~/backup-inventory.md
#
# READ-ONLY and metadata only: names of top-level and application
# directories, sizes (du), file counts, newest modification dates, git
# status counters. It never prints file contents, never prints single file
# names below the home's top level (loose files and downloads are counted by
# extension), never prints git remote URLs, account names, SSIDs or keys.
# The only file it reads is the Nextcloud client's nextcloud.cfg, and of that
# only the localPath/paused lines of the sync folders (where the sync
# boundaries are) - no server URL, no user. No sudo, no network, no temporary
# files, nothing written anywhere; the report goes to stdout. Uses only bash,
# coreutils, find, du, awk, git (and nmcli for counts, when present).
#
# A Nextcloud sync folder in the report is NOT proof that its files reached
# the server: check the client ("up to date", no errors) yourself.
set -u
export LC_ALL=C

H=${HOME:?}
NOW=$(date '+%Y-%m-%d %H:%M')

# ---- helpers --------------------------------------------------------------
bytes() { du -sb -- "$1" 2>/dev/null | cut -f1; }
human() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0}B"; }
files() { find "$1" -xdev -type f 2>/dev/null | wc -l; }
newest() { # newest mtime below $1 as a date (no file name)
    find "$1" -xdev -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 \
        | awk '{ if ($1 != "") print strftime("%Y-%m-%d", $1); else print "-" }'
}
rel() { case $1 in "$H") echo "~" ;; "$H"/*) echo "~/${1#"$H"/}" ;; *) echo "$1" ;; esac; }
cell() { printf '%s' "$1" | tr '|\n' '/ '; }   # safe inside a markdown table

# ---- Nextcloud sync folders ----------------------------------------------
NC_CFG=$H/.config/Nextcloud/nextcloud.cfg
NC_PATHS=()          # local sync roots, without trailing slash
NC_STATE=unknown     # unknown | none | found
NC_NOTES=()
declare -A NC_DIR=()   # config entry (e.g. 0\Folders\1) -> local path
declare -A NC_PAUSED=()
if [ -r "$NC_CFG" ]; then
    NC_STATE=none
    while IFS= read -r line; do
        key=${line%%=*} val=${line#*=}
        case $key in
            *\\localPath)
                val=${val%/}; [ -n "$val" ] || continue
                NC_PATHS+=("$val"); NC_STATE=found; NC_DIR[${key%\\localPath}]=$val
                case $key in *FoldersWithPlaceholders*)
                    NC_NOTES+=("\`$(rel "$val")\`: virtuelle Dateien (Platzhalter) - lokal evtl. nur Stubs, Inhalt nur auf dem Server") ;;
                esac ;;
            *\\paused) [ "$val" = true ] && NC_PAUSED[${key%\\paused}]=1 ;;
        esac
    done < <(grep -E '\\(Folders|FoldersWithPlaceholders)\\[0-9]+\\(localPath|paused)=' "$NC_CFG" 2>/dev/null)
    for k in "${!NC_PAUSED[@]}"; do
        NC_NOTES+=("\`$(rel "${NC_DIR[$k]-?}")\`: Synchronisation **pausiert** - Stand auf dem Server veraltet")
    done
fi
# coverage of a path: ja (inside a sync root) | teilweise (contains one) | nein | unklar
coverage() {
    local p=${1%/} r part=0
    [ "$NC_STATE" = unknown ] && { echo unklar; return; }
    for r in "${NC_PATHS[@]+"${NC_PATHS[@]}"}"; do
        case $p/ in "$r"/*) echo ja; return ;; esac
        case $r/ in "$p"/*) part=1 ;; esac
    done
    [ $part = 1 ] && echo teilweise || echo nein
}

# ---- report rows ------------------------------------------------------------
ROWS=()        # "category<TAB>label<TAB>path<TAB>note"
CANDIDATES=()  # "category<TAB>path" - backup candidates for the space sum
add() { # category label path note [count-as-candidate]
    local cat=$1 label=$2 p=$3 note=$4
    [ -e "$p" ] || return 0
    ROWS+=("$cat"$'\t'"$label"$'\t'"$p"$'\t'"$note")
    case $cat in Kritisch|Wichtig|Optional) CANDIDATES+=("$cat"$'\t'"$p") ;; esac
}

# Known top-level directories (non-hidden) - everything else is "unclear".
declare -A TOP=(
    [Documents]=Kritisch [Dokumente]=Kritisch [Work]=Kritisch [Projects]=Kritisch
    [Studium]=Kritisch [Goodnotes]=Kritisch [Desktop]=Wichtig [Schreibtisch]=Wichtig
    [Pictures]=Wichtig [Bilder]=Wichtig [Videos]=Wichtig [Music]=Wichtig [Musik]=Wichtig
    [Downloads]=Optional [Templates]=Optional [Public]=Optional
    [knime-workspace]=APP ["VirtualBox VMs"]=VM [repos]=GIT [AnyDesk]=Optional
    [Nextcloud]=Kritisch
)

UNCLEAR=()

echo "# Backup-Inventur - $(hostname 2>/dev/null || uname -n), $NOW"
echo
echo "Nur Metadaten (Namen der obersten Ebene, Größen, Anzahlen, Datum)."
echo "Erzeugt von \`scripts/backup-inventory.sh\` (workstation-arch). Vor dem Teilen selbst durchsehen."
echo
echo "> **Ein vorhandener Nextcloud-Ordner ist kein Nachweis für eine erfolgreiche Synchronisation oder eine Sicherung auf dem Server.** Im Nextcloud-Client prüfen: alle Ordner \"Aktuell\", keine Fehler, keine ignorierten Dateien."
echo

echo "## Nextcloud"
echo
case $NC_STATE in
    unknown) echo "- Keine lesbare \`~/.config/Nextcloud/nextcloud.cfg\`: **Sync-Grenzen unbekannt** - Abdeckung überall \"unklar\"." ;;
    none) echo "- Client-Konfiguration vorhanden, aber **kein Sync-Ordner eingetragen** - nichts gilt als abgedeckt." ;;
    found)
        echo "- Sync-Ordner laut Client-Konfiguration:"
        for r in "${NC_PATHS[@]}"; do echo "  - \`$(rel "$r")\` ($(human "$(bytes "$r")"))"; done ;;
esac
for n in "${NC_NOTES[@]+"${NC_NOTES[@]}"}"; do echo "- $n"; done
[ -e "$H/.config/Nextcloud/sync-exclude.lst" ] && echo "- Eigene Ausschlussliste \`sync-exclude.lst\` vorhanden - dort ausgeschlossene Dateien liegen nur lokal."
echo "- Nicht prüfbar ohne Client: ob der letzte Sync fehlerfrei war, Konflikte, serverseitige Versionen."
echo

# ---- home top level -----------------------------------------------------------
while IFS= read -r -d '' d; do
    name=${d##*/}
    cat=${TOP[$name]-}
    case $cat in
        VM|GIT|APP) continue ;;              # own sections/rows below
        "") UNCLEAR+=("$d"); continue ;;
    esac
    add "$cat" "Home: $name" "$d" ""
done < <(find "$H" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 2>/dev/null | sort -z)

# loose files directly in ~ (summarised by extension, no names)
LOOSE=$(find "$H" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -printf '%f\n' 2>/dev/null \
    | awk -F. 'NF>1 { e=tolower($NF) } NF==1 { e="(ohne)" } { c[e]++ } END { for (k in c) printf "%s %d, ", k, c[k] }')
LOOSE_B=$(find "$H" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -printf '%s\n' 2>/dev/null | awk '{ s+=$1 } END { print s+0 }')

# ---- git repositories ------------------------------------------------------------
GIT_ROWS=()
while IFS= read -r -d '' g; do
    r=${g%/.git}
    # --no-optional-locks: `git status` would otherwise refresh (write) the index
    git_() { git --no-optional-locks -c core.fsmonitor=false -c core.untrackedCache=false -C "$r" "$@" 2>/dev/null; }
    git_ rev-parse --is-inside-work-tree >/dev/null || continue
    mod=$(git_ status --porcelain --untracked-files=no | wc -l)
    unt=$(git_ status --porcelain --untracked-files=normal | grep -c '^??')
    stash=$(git_ stash list | wc -l)
    remotes=$(git_ remote | wc -l)
    noup=0 ahead=0 gone=0
    while IFS='|' read -r br up track; do
        [ -z "$up" ] && { noup=$((noup+1)); continue; }
        case $track in *gone*) gone=$((gone+1)) ;; esac
        a=$(printf '%s' "$track" | sed -n 's/.*ahead \([0-9]*\).*/\1/p'); ahead=$((ahead + ${a:-0}))
    done < <(git_ for-each-ref --format='%(refname:short)|%(upstream:short)|%(upstream:track)' refs/heads)
    risk=""
    [ "$mod" -gt 0 ] && risk+="$mod geänderte, "
    [ "$unt" -gt 0 ] && risk+="$unt unversionierte, "
    [ "$stash" -gt 0 ] && risk+="$stash Stash, "
    [ "$ahead" -gt 0 ] && risk+="$ahead Commits nicht gepusht, "
    [ "$noup" -gt 0 ] && risk+="$noup Branch(es) ohne Upstream, "
    [ "$gone" -gt 0 ] && risk+="$gone Upstream gelöscht, "
    [ "$remotes" -eq 0 ] && risk+="KEIN Remote, "
    risk=${risk%, }
    cat=Reproduzierbar; [ -n "$risk" ] && cat=Kritisch
    GIT_ROWS+=("$cat"$'\t'"$r"$'\t'"${risk:-sauber, gepusht (Stand der lokalen Tracking-Infos, kein fetch)}")
    [ "$cat" = Kritisch ] && CANDIDATES+=("Kritisch"$'\t'"$r")
done < <(find "$H" -xdev -maxdepth 6 \( -path "$H/.cache" -o -path "$H/.local/share" -o -path "$H/.var" \
            -o -name node_modules -o -name .venv -o -path "$H/.local/opt" \) -prune \
            -o -name .git -print0 2>/dev/null | sort -z)

# ---- notebooks, databases, VMs, venvs --------------------------------------------
# grouped by directory - at most two levels below ~ (deeper, possibly
# telling folder names are summarised), never single file names
group_find() { # find-expression... -> "count  ~/dir[/sub]" lines, user data only (no dot dirs, no caches)
    find "$H" -xdev \( -path "$H/.*" -o -name node_modules -o -name .venv -o -name venv -o -name .git \) -prune \
        -o -type f \( "$@" \) -printf '%h\n' 2>/dev/null \
        | awk -v h="$H" '{ r = substr($0, length(h) + 2); n = split(r, a, "/");
                          if ($0 == h) print "~"; else if (n <= 2) print "~/" r; else print "~/" a[1] "/" a[2] "/..." }' \
        | sort | uniq -c | sort -rn
}
NB=$(group_find -name '*.ipynb')
DB=$(group_find -iname '*.db' -o -iname '*.sqlite' -o -iname '*.sqlite3' -o -iname '*.sql' -o -iname '*.mwb' -o -iname '*.accdb' -o -iname '*.mdb')
VD=$(group_find -iname '*.vdi' -o -iname '*.vmdk' -o -iname '*.vhd' -o -iname '*.vhdx' -o -iname '*.qcow2' -o -iname '*.ova' -o -iname '*.iso')

VM_ROWS=()
VMDIR="$H/VirtualBox VMs"
if [ -d "$VMDIR" ]; then
    while IFS= read -r -d '' v; do
        disks=$(find "$v" -maxdepth 1 -type f \( -iname '*.vdi' -o -iname '*.vmdk' -o -iname '*.vhd' \) 2>/dev/null | wc -l)
        snaps=0; [ -d "$v/Snapshots" ] && snaps=$(find "$v/Snapshots" -type f 2>/dev/null | wc -l)
        VM_ROWS+=("$v"$'\t'"$disks Festplatte(n), Snapshot-Dateien: $snaps")
        CANDIDATES+=("Kritisch"$'\t'"$v")
    done < <(find "$VMDIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi
add Wichtig "VirtualBox-Registrierung (VMs, Medien)" "$H/.config/VirtualBox" "klein; hilft beim Wiedereinbinden"
for d in "$H/.local/share/libvirt/images" "$H/.local/share/gnome-boxes"; do
    add Kritisch "VM-Images ($(basename "$(dirname "$d")"))" "$d" ""
done

VENV_ROWS=()
while IFS= read -r -d '' cfg; do
    v=${cfg%/pyvenv.cfg}; parent=${v%/*}
    deps=no
    for f in "$parent"/pyproject.toml "$parent"/requirements*.txt "$parent"/uv.lock "$parent"/Pipfile "$parent"/environment.yml; do
        [ -e "$f" ] && deps=yes
    done
    if [ $deps = yes ]; then
        VENV_ROWS+=("Reproduzierbar"$'\t'"$v"$'\t'"Abhängigkeitsliste im Projekt vorhanden")
    else
        VENV_ROWS+=("Unklar"$'\t'"$v"$'\t'"keine pyproject/requirements daneben - Paketliste vorher sichern (z. B. pip freeze)")
    fi
done < <(find "$H" -xdev -maxdepth 7 \( -path "$H/.cache" -o -name node_modules -o -name .git \) -prune \
            -o -name pyvenv.cfg -print0 2>/dev/null | sort -z)

# ---- application data ------------------------------------------------------------
add Kritisch "Thunderbird-Profil (lokale Mails, Filter, Adressbuch)" "$H/.thunderbird" "Profil-Ordner komplett sichern (Thunderbird geschlossen)"
add Kritisch "Thunderbird (zweiter Ordner)" "$H/thunderbird" ""
add Kritisch "KNIME-Workspace" "$H/knime-workspace" "Workflows/Daten"
add Wichtig "Anki-Sammlung" "$H/.local/share/Anki2" "nur verzichtbar, wenn mit AnkiWeb synchronisiert"
add Wichtig "Chromium-Profil (Lesezeichen, Erweiterungsdaten, Passwörter)" "$H/.config/chromium" "verzichtbar, wenn Chromium-Sync aktiv - Caches liegen in ~/.cache"
add Wichtig "IntelliJ-Einstellungen" "$H/.config/JetBrains" "Plugins/Caches unter ~/.local/share bzw. ~/.cache sind reproduzierbar"
add Wichtig "Neovim-Konfiguration" "$H/.config/nvim" "nur falls nicht aus einem Repo verlinkt"
add Wichtig "Obsidian-Einstellungen (Vault-Orte)" "$H/.config/obsidian" "Vaults selbst: wo liegen sie?"
add Wichtig "Planify (Flatpak)" "$H/.var/app/io.github.alainm23.planify" "lokale Aufgaben, falls nicht über CalDAV"
add Wichtig "GPG-Schlüsselbund" "$H/.gnupg" "enthält ggf. private Schlüssel"
add Wichtig "pass-Passwortspeicher" "$H/.password-store" ""
add Wichtig "Persönliche Schriften" "$H/.local/share/fonts" ""
add Optional "TeXstudio-Einstellungen" "$H/.config/texstudio" ""
add Optional "Jupyter-Einstellungen" "$H/.jupyter" ""
add Optional "GNOME-Schlüsselbund (gespeicherte App-Passwörter)" "$H/.local/share/keyrings" "neu erzeugbar; Passwörter gehören in Bitwarden"
add Reproduzierbar "Nextcloud-Client-Konfiguration" "$H/.config/Nextcloud" "neu anmelden, Ordner neu verknüpfen"
add Reproduzierbar "Bitwarden-Desktop" "$H/.config/Bitwarden" "Tresor liegt auf dem Server"
add Reproduzierbar "Bitwarden-CLI" "$H/.config/Bitwarden CLI" "Tresor liegt auf dem Server"
add Reproduzierbar "Caches" "$H/.cache" "verzichtbar"
add Reproduzierbar "Neovim-Plugins/Mason" "$H/.local/share/nvim" "Bootstrap installiert neu"
add Reproduzierbar "mise-Laufzeiten (Node/Python/Java/CLIs)" "$H/.local/share/mise" "REPO nutzt pacman/npm statt mise"
add Reproduzierbar "Flatpak (Benutzer-Installationen)" "$H/.local/share/flatpak" "Apps neu installieren"
add Reproduzierbar "JetBrains-Plugins/Indizes" "$H/.local/share/JetBrains" ""
add Reproduzierbar "KNIME-Programm" "$H/.local/opt/knime" "knime-install"
add Reproduzierbar "Maven-/Gradle-/npm-/cargo-Caches" "$H/.m2" ""
add Reproduzierbar "Gradle" "$H/.gradle" ""
add Reproduzierbar "npm" "$H/.npm" ""
add Reproduzierbar "cargo" "$H/.cargo" ""
add Reproduzierbar "Steam" "$H/.local/share/Steam" "Spiele neu laden; Spielstände meist in der Cloud"
add Reproduzierbar "Docker (Benutzer-Konfig)" "$H/.docker" "Container/Volumes liegen unter /var/lib/docker - siehe ungeklärte Punkte"

# Flatpak app data of other apps (per app id, not their content)
if [ -d "$H/.var/app" ]; then
    while IFS= read -r -d '' a; do
        id=${a##*/}
        case $id in io.github.alainm23.planify) continue ;; esac
        add Optional "Flatpak-Daten $id" "$a" "prüfen, ob dort eigene Daten liegen"
    done < <(find "$H/.var/app" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi

# hidden top-level directories in ~ that no list above knows
declare -A KNOWN_DOT=([.cache]=1 [.config]=1 [.local]=1 [.var]=1 [.thunderbird]=1 [.gnupg]=1
    [.password-store]=1 [.ssh]=1 [.m2]=1 [.gradle]=1 [.npm]=1 [.cargo]=1 [.docker]=1 [.jupyter]=1
    [.mozilla]=1 [.pki]=1 [.java]=1 [.vscode]=1 [.claude]=1 [.codex]=1 [.ipython]=1 [.texlive]=1)
while IFS= read -r -d '' d; do
    [ -n "${KNOWN_DOT[${d##*/}]-}" ] && continue
    b=$(bytes "$d"); [ "${b:-0}" -ge 1048576 ] && UNCLEAR+=("$d")
done < <(find "$H" -mindepth 1 -maxdepth 1 -type d -name '.*' -print0 2>/dev/null | sort -z)

# ---- configuration (presence only) -------------------------------------------------
CONF=()
conf() { CONF+=("$1"$'\t'"$2"); }
for f in .bashrc .bash_profile .profile .zshrc .config/fish/config.fish .config/starship.toml .gitconfig .config/git/config; do
    p=$H/$f; [ -e "$p" ] || continue
    if [ -L "$p" ]; then conf "\`~/$f\`" "Symlink -> $(rel "$(readlink -f "$p")") (über das verlinkte Repo gesichert, wenn gepusht)"
    else conf "\`~/$f\`" "Datei, $(human "$(bytes "$p")") - eigene Anpassungen? in dotfiles übernehmen"; fi
done
if [ -d "$H/.ssh" ]; then
    pub=$(find "$H/.ssh" -maxdepth 1 -type f -name '*.pub' 2>/dev/null | wc -l)
    priv=$(find "$H/.ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' 2>/dev/null | wc -l)
    other=$(find "$H/.ssh" -maxdepth 1 -type f ! -name '*.pub' ! -name 'id_*' ! -name 'known_hosts*' ! -name authorized_keys ! -name config 2>/dev/null | wc -l)
    conf "\`~/.ssh\`" "$pub öffentliche Schlüssel, $priv mögliche private Schlüssel (id_*), $other weitere Dateien, config: $([ -e "$H/.ssh/config" ] && echo ja || echo nein) - private Schlüssel nur sichern, wenn sie nicht in Bitwarden liegen"
fi
if [ -d "$H/.local/bin" ]; then
    lb_link=$(find "$H/.local/bin" -maxdepth 1 -type l 2>/dev/null | wc -l)
    lb_file=$(find "$H/.local/bin" -maxdepth 1 -type f 2>/dev/null | wc -l)
    lb_names=$(find "$H/.local/bin" -maxdepth 1 -type f -printf '%f, ' 2>/dev/null | sed 's/, $//')
    conf "\`~/.local/bin\`" "$lb_file Dateien (${lb_names:-keine}), $lb_link Symlinks - eigene Skripte sichern"
fi
[ -d "$H/bin" ] && conf "\`~/bin\`" "$(files "$H/bin") Dateien - eigene Skripte sichern"
if [ -d "$H/.config/systemd/user" ]; then
    units=$(find "$H/.config/systemd/user" -maxdepth 1 -type f \( -name '*.service' -o -name '*.timer' -o -name '*.path' -o -name '*.socket' \) -printf '%f, ' 2>/dev/null | sed 's/, $//')
    conf "systemd-Benutzer-Units" "${units:-keine eigenen Unit-Dateien} (aktivierte Fremd-Units sind nur Symlinks)"
fi
apps=$(find "$H/.local/share/applications" -maxdepth 1 -name '*.desktop' -printf '%f, ' 2>/dev/null | sed 's/, $//')
[ -n "$apps" ] && conf "Eigene Desktop-Einträge" "$apps"
auto=$(find "$H/.config/autostart" -maxdepth 1 -name '*.desktop' -printf '%f, ' 2>/dev/null | sed 's/, $//')
[ -n "$auto" ] && conf "Autostart" "$auto"
if command -v crontab >/dev/null 2>&1; then
    n=$(crontab -l 2>/dev/null | grep -cv '^\s*\(#\|$\)'); conf "crontab" "$n Einträge"
fi
if [ -e /etc/cups/printers.conf ]; then conf "Drucker (CUPS)" "printers.conf vorhanden - Druckernamen/Adressen notieren (Druckerdialog), in REPO neu anlegen"
else conf "Drucker (CUPS)" "keine printers.conf"; fi
if command -v nmcli >/dev/null 2>&1; then
    t=$(nmcli -t -f TYPE connection show 2>/dev/null | sort | uniq -c | awk '{ printf "%s %s, ", $1, $2 }' | sed 's/, $//')
    conf "NetworkManager-Profile" "${t:-keine} - WLAN-Passwörter, eduroam (CAT), VPN neu einrichten"
fi
[ -d "$H/.local/share/remmina" ] && conf "Remmina" "Verbindungen vorhanden"

# ---- output ---------------------------------------------------------------------
sz() { human "$(bytes "$1")"; }
echo "## Übersicht"
echo
echo "| Kategorie | Daten/Verzeichnis | Größe | Dateien | Neueste Änderung | Nextcloud-Abdeckung | Empfehlung |"
echo "|---|---|---|---|---|---|---|"
rec() { case $1 in Kritisch) echo "Unbedingt sichern" ;; Wichtig) echo "Sichern" ;; Optional) echo "Nach Bedarf" ;; Reproduzierbar) echo "Neu installieren / neu erzeugen" ;; *) echo "Manuell prüfen" ;; esac; }
for c in Kritisch Wichtig Optional Reproduzierbar; do
    if [ $c = Optional ] && [ -n "$LOOSE" ]; then
        echo "| Wichtig | Lose Dateien direkt in \`~\` (${LOOSE%, }) | $(human "$LOOSE_B") | - | - | $(coverage "$H/.loose-files") | einzeln durchsehen |"
    fi
    for row in "${ROWS[@]+"${ROWS[@]}"}"; do
        IFS=$'\t' read -r cat label p note <<<"$row"
        [ "$cat" = "$c" ] || continue
        cov=$(coverage "$p"); r=$(rec "$cat")
        [ "$cov" = ja ] && [ "$cat" != Reproduzierbar ] && r="im Sync-Ordner - Sync im Client bestätigen"
        [ "$cat" = Reproduzierbar ] && cov="nicht erforderlich"
        n=""; [ "$cat" != Reproduzierbar ] && n=$(files "$p")
        d=""; [ "$cat" != Reproduzierbar ] && d=$(newest "$p")
        echo "| $cat | $(cell "$label") (\`$(cell "$(rel "$p")")\`) | $(sz "$p") | ${n:--} | ${d:--} | $cov | $(cell "$r${note:+ - $note}") |"
    done
done
echo

echo "## Git-Repositories"
echo
echo "Stand der lokalen Tracking-Informationen (kein \`git fetch\`): \"gepusht\" heißt, der letzte bekannte Upstream-Stand enthält den Commit."
echo
if [ ${#GIT_ROWS[@]} -eq 0 ]; then echo "Keine gefunden."; else
    echo "| Kategorie | Repository | Größe | Nextcloud | Befund |"
    echo "|---|---|---|---|---|"
    for row in "${GIT_ROWS[@]}"; do
        IFS=$'\t' read -r cat p risk <<<"$row"
        echo "| $cat | \`$(cell "$(rel "$p")")\` | $(sz "$p") | $(coverage "$p") | $(cell "$risk") |"
    done
fi
echo

echo "## Virtuelle Maschinen"
echo
if [ ${#VM_ROWS[@]} -eq 0 ]; then echo "Keine VirtualBox-VMs unter \`~/VirtualBox VMs\`."; else
    echo "| Kategorie | VM | Größe | Inhalt | Empfehlung |"
    echo "|---|---|---|---|---|"
    for row in "${VM_ROWS[@]}"; do
        IFS=$'\t' read -r p info <<<"$row"
        echo "| Kritisch | \`$(cell "${p##*/}")\` | $(sz "$p") | $info | VM herunterfahren, Ordner kopieren oder als OVA exportieren |"
    done
fi
[ -n "$VD" ] && { echo; echo "Weitere VM-/Image-Dateien außerhalb (Anzahl je Ordner):"; echo; echo '```'; printf '%s\n' "$VD"; echo '```'; }
echo

echo "## Jupyter-Notebooks und lokale Datenbanken (Anzahl je Ordner)"
echo
if [ -n "$NB" ]; then echo "Notebooks (\`*.ipynb\`):"; echo; echo '```'; printf '%s\n' "$NB"; echo '```'; else echo "Keine Notebooks außerhalb versteckter Ordner."; fi
echo
if [ -n "$DB" ]; then echo "Datenbank-/Modelldateien (\`*.db *.sqlite* *.sql *.mwb ...\`):"; echo; echo '```'; printf '%s\n' "$DB"; echo '```'; else echo "Keine Datenbankdateien außerhalb versteckter Ordner."; fi
echo

echo "## Python-Umgebungen"
echo
if [ ${#VENV_ROWS[@]} -eq 0 ]; then echo "Keine \`pyvenv.cfg\` gefunden."; else
    for row in "${VENV_ROWS[@]}"; do IFS=$'\t' read -r cat p note <<<"$row"; echo "- $cat: \`$(rel "$p")\` ($(sz "$p")) - $note"; done
fi
echo

echo "## Konfigurationen (nur Vorhandensein)"
echo
for row in "${CONF[@]+"${CONF[@]}"}"; do IFS=$'\t' read -r k v <<<"$row"; echo "- $k: $(cell "$v")"; done
echo

# ---- space without double counting ------------------------------------------------
dedupe() { # stdin: paths -> drop paths below another listed path
    sort -u | awk '{ for (i in keep) if (index($0 "/", keep[i] "/") == 1) next; keep[NR]=$0; print }'
}
sum_for() { # categories... -> bytes of the deduplicated, not-in-Nextcloud candidates
    local want=" $* " list=() p
    while IFS= read -r p; do [ -n "$p" ] && list+=("$p"); done < <(
        for row in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
            IFS=$'\t' read -r cat p <<<"$row"
            case $want in *" $cat "*) ;; *) continue ;; esac
            [ "$(coverage "$p")" = ja ] && continue
            printf '%s\n' "$p"
        done | dedupe)
    [ ${#list[@]} -eq 0 ] && { echo 0; return; }
    du -scb -- "${list[@]}" 2>/dev/null | tail -1 | cut -f1
}
k=$(sum_for Kritisch); kw=$(sum_for Kritisch Wichtig); kwo=$(sum_for Kritisch Wichtig Optional)
echo "## Zusätzlicher Speicherbedarf für das Backup"
echo
echo "Ohne Doppelzählung (verschachtelte Pfade nur einmal) und ohne Pfade innerhalb eines Nextcloud-Sync-Ordners:"
echo
echo "| Umfang | Größe |"
echo "|---|---|"
echo "| Kritisch | $(human "$k") |"
echo "| Kritisch + Wichtig | $(human "$kw") |"
echo "| Kritisch + Wichtig + Optional | $(human "$kwo") |"
echo
echo "Lose Dateien in \`~\` ($(human "$LOOSE_B")) sind nicht enthalten. Bei unklarer Nextcloud-Abdeckung zählt alles mit."
echo

echo "## Priorisierte Backup-Checkliste"
echo
echo "1. Nextcloud-Client: alle Sync-Ordner \"Aktuell\", keine Fehler/Konflikte/ignorierten Dateien (Nachweis, nicht Ordner-Existenz)."
echo "2. Alle Zeilen **Kritisch** oben, die nicht \"ja\" bei Nextcloud haben: auf externes Medium kopieren."
echo "3. Git: jedes Repo mit Befund committen und pushen (oder als Ordner sichern)."
echo "4. VMs: herunterfahren, dann Ordner kopieren oder als OVA exportieren."
echo "5. Thunderbird schließen, Profilordner kopieren."
echo "6. **Wichtig**-Zeilen: sichern oder bewusst verwerfen (z. B. Chromium/Anki nur, wenn kein Sync)."
echo "7. Lose Dateien in \`~\` und die ungeklärten Ordner unten durchsehen."
echo "8. Notizen für die Neueinrichtung: Drucker, WLAN-/VPN-Profile, eigene Skripte aus \`~/.local/bin\`, Desktop-Einträge."
echo "9. Das Backup-Medium an einem zweiten Rechner öffnen und Stichproben prüfen - erst dann löschen."
echo

echo "## Nach der REPO-Installation neu erzeugbar"
echo
for row in "${ROWS[@]+"${ROWS[@]}"}"; do
    IFS=$'\t' read -r cat label p note <<<"$row"
    [ "$cat" = Reproduzierbar ] && echo "- $label (\`$(rel "$p")\`, $(sz "$p"))${note:+ - $note}"
done
echo "- Saubere, gepushte Git-Repositories (neu klonen; phase 2 klont die privaten selbst)"
echo "- Python-Umgebungen mit Abhängigkeitsliste (\`uv sync\` / \`pip install -r\`)"
echo "- Alle Programme: REPO-Bootstrap (pacman, Flatpak, npm) - siehe docs/migration/OMARCHY_PERSONAL_SOFTWARE_AUDIT.md"
echo

echo "## Ungeklärte Verzeichnisse (manuell prüfen)"
echo
if [ ${#UNCLEAR[@]} -eq 0 ]; then echo "Keine."; else
    echo "| Verzeichnis | Größe | Dateien | Neueste Änderung | Nextcloud |"
    echo "|---|---|---|---|---|"
    for p in "${UNCLEAR[@]}"; do echo "| \`$(cell "$(rel "$p")")\` | $(sz "$p") | $(files "$p") | $(newest "$p") | $(coverage "$p") |"; done
fi
for row in "${VENV_ROWS[@]+"${VENV_ROWS[@]}"}"; do
    IFS=$'\t' read -r cat p note <<<"$row"; [ "$cat" = Unklar ] && echo "- Python-Umgebung ohne Abhängigkeitsliste: \`$(rel "$p")\`"
done
echo "- Docker-Container/-Volumes (falls genutzt): liegen unter \`/var/lib/docker\`, ohne sudo nicht prüfbar - Datenbanken in Containern vorher exportieren."
echo "- Daten außerhalb von \`~\` (z. B. eigene Dateien unter \`/opt\`, \`/srv\`, \`/etc\`) prüft dieses Skript nicht."
