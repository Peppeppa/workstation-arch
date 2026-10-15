# Backup inventory before erasing the Omarchy laptop

`scripts/backup-inventory.sh` lists what on a machine may not be covered by
Nextcloud - before its disk is erased (`docs/release/X1_CARBON_INSTALL.md`,
section 0). The owner runs it on that machine; nobody else connects to it.

## What it does - and does not

- **Read-only, metadata only:** names of the home's top-level and
  application directories, sizes, file counts, newest modification dates,
  git status counters. No file contents; files directly in `~` are counted
  by extension, folders deeper than two levels are summarised (`~/A/B/...`).
- **Not printed:** git remote URLs, the Nextcloud server and account,
  Wi-Fi names, key material. Of `~/.config/Nextcloud/nextcloud.cfg` it reads
  only the sync folders' `localPath`/`paused` lines.
- **No sudo, no network, no temporary files, writes nothing** (also not
  `.git/index`: git runs with `--no-optional-locks`). Bash, coreutils,
  find/du/awk, git, and `nmcli` for counts.
- **A Nextcloud sync folder is not proof of a backup.** The report says
  which folders the client is configured to sync; whether they really are on
  the server, the client has to show (all folders "up to date", no errors, no
  ignored files, not paused).

## Run it

On the Omarchy laptop, as yourself (not root), in a terminal:

```sh
curl -fsSLo ~/backup-inventory.sh https://raw.githubusercontent.com/Peppeppa/workstation-arch/main/scripts/backup-inventory.sh
less ~/backup-inventory.sh                      # read it first - it is yours to check
bash ~/backup-inventory.sh > ~/backup-inventory.md
```

It can take a few minutes on a large home (every directory is measured with
`du`). Read `~/backup-inventory.md` before sharing it: top-level folder names,
repository paths, VM names and the names of your own scripts/units/launchers
are in it. Delete both files when you no longer need them.

## The report

| Section | Content |
|---|---|
| Nextcloud | the configured sync folders, paused folders, virtual-files folders (placeholders: content only on the server), own exclude list |
| Übersicht | one row per directory: category, size, files, newest change, Nextcloud coverage (`ja` inside a sync folder, `teilweise` contains one, `nein`, `unklar` = client config not readable), recommendation |
| Git-Repositories | per repository: changed/untracked files, stashes, commits not pushed, branches without upstream, no remote - from local tracking data (no `git fetch`) |
| Virtuelle Maschinen | VirtualBox VMs with disk count and snapshot files; other disk images by folder |
| Notebooks / databases | `*.ipynb`, `*.db`/`*.sqlite`/`*.sql`/`*.mwb` ... counted per folder |
| Python-Umgebungen | each venv: reproducible (a `pyproject.toml`/`requirements*.txt`/`uv.lock` next to it) or unclear |
| Konfigurationen | presence only: shell files (symlink into a repo or own file), `~/.ssh` (counts), `~/.local/bin` scripts, own systemd user units, launchers, autostart, crontab, CUPS printers, NetworkManager profiles by type |
| Speicherbedarf | backup size for Kritisch / +Wichtig / +Optional - nested paths counted once, paths inside a sync folder left out |
| Checkliste, neu erzeugbar, ungeklärt | prioritised steps; what REPO recreates; directories the script does not know (check by hand) |

Categories: **Kritisch** (unique data: documents, workspaces, mail profile,
VMs, unpushed git work) - **Wichtig** (worth keeping unless synced elsewhere:
browser profile, Anki, IDE settings, keys) - **Optional** (downloads, app
data of single Flatpaks) - **Reproduzierbar** (caches, plugin and runtime
directories, clean pushed repositories: recreated by REPO or a re-download).

Not covered by the script: Docker volumes under `/var/lib/docker` (root
only), data outside `~`, whether Chromium/Anki sync is switched on.

Test: `tests/backup-inventory.sh` (artificial home with planted secrets: none
may appear in the report; the home must be unchanged afterwards).
