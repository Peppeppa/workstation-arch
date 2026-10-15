# Omarchy -> REPO: personal software audit

Read-only inventory of the user's production Omarchy laptop (hostname
`x1carbon`, Omarchy 4.0.4, kernel `linux-omarchy`), compared with
workstation-arch `main` at `819286c`. 2026-10-15. Nothing was installed,
changed, written or executed on that laptop (section "Method and limits").
Nothing in REPO was changed for this audit; every recommendation in F is
a proposal only.

## How "personal" was decided

`pacman -Qqe` alone is not evidence: Omarchy installs ~160 packages as
explicit. The evidence used, strongest first:

1. **`/var/log/pacman.log` (complete since the install on 2026-08-12).**
   The Omarchy installer ran from the live medium (`pacman -r /mnt ...`,
   12:32-12:33): its package lists are the **Omarchy baseline** (158
   names). Everything installed by a later command is a candidate.
2. **Command shape of later transactions.** Omarchy's own scripts and
   menu installs run `pacman -S --noconfirm --needed <pkg>` (or
   `--ask 4` for migrations); the user's own commands have other shapes
   (`pacman -S texstudio`, `pacman -S --needed --noconfirm bitwarden ...`
   from a personal bootstrap script, yay builds via `pacman -U
   ~/.cache/yay/...`). Same-minute groups next to an Omarchy update
   (`omarchy`/`omarchy-settings` reinstall, `mise` -> `mise-bin`,
   `quickshell-git` -> `quickshell`) are Omarchy migrations.
3. **Removals.** On install day the user removed Omarchy defaults
   (`aether cliamp libreoffice-fresh xournalpp pinta obsidian obs-studio
   kdenlive lazydocker`) - a clear signal of what they did *not* want.
4. **Non-pacman state**: user Flatpaks, mise config + installs,
   `~/.local/bin`, `~/.local/opt`, `~/.local/share/applications`, user
   systemd units, the old `dotfiles-stow` manifest.

Classes: **confirmed** (a user-shaped command or user-only location),
**probable** (evidence points to the user, but not conclusively),
**Omarchy default**, **dependency/system**, **uncertain**.

## What REPO actually provisions (normalized)

| Mechanism | REPO support | Where |
|---|---|---|
| pacman, official repos | yes - the baseline | `roles/*/defaults/main.yml` `*_packages` |
| AUR | one pinned exception (`networkmanager-fortisslvpn`) + `yay` for the user's own runtime installs (OS menu -> Packages), never baseline | `roles/network`, `roles/packages` |
| Flatpak (Flathub, system) | yes: IntelliJ IDEA Ultimate, LocalSend | `roles/apps` `apps_flatpak_packages` |
| Chromium web apps | yes: WhatsApp, Zoom, Discord | `roles/apps` `apps_webapps` |
| Python | `python` + `uv`; one locked uv env (Data Science: pandas ... JupyterLab, Streamlit) | `roles/development` |
| Neovim tooling | Mason packages, headless | `roles/apps` `apps_nvim_mason_packages` |
| npm/pnpm/bun globals, pipx, cargo install, go install, AppImages, mise | **not supported** (no such mechanism exists) | - |
| User dotfiles | private `dotfiles-provision` (Stow; currently only `bash`) | phase 2 |

Relevant REPO packages for this comparison: `chromium thunderbird nautilus
neovim obsidian bitwarden zathura texstudio anki planify nextcloud-client
mpv imv loupe gnome-disk-utility github-cli lazygit jdk25-openjdk maven
gradle python uv nodejs npm gcc gdb make rust nasm docker docker-compose
docker-buildx lazydocker mariadb-clients texlive-{bin,basic,latex,
latexrecommended,latexextra,fontsrecommended,langgerman,mathscience,
bibtexextra,binextra,luatex} biber stow virtualbox ghostty starship zoxide
fzf eza bat tealdeer btop fastfetch curl rsync networkmanager +VPN plugins
openfortivpn`.

## A. Confirmed personal software missing from REPO

| Package / tool | Source on Omarchy | Evidence | Purpose | In REPO? | Recommended action |
|---|---|---|---|---|---|
| `tailscale` | pacman (extra); `tailscaled.service` enabled; Omarchy's `omarchy-tailscale-receive` user unit + admin web app | installed 2026-08-12 18:40, six hours after setup, via the Omarchy menu | mesh VPN to the user's own devices / Homelab | no | ask - a new always-on system daemon; would be an opt-in feature (`tailscale_enabled`), owner = tailscaled, NetworkManager stays network owner |
| `bitwarden-cli` | pacman (extra) | personal install script 2026-08-12 14:47 (with bitwarden, nextcloud-client, thunderbird, stow) | `bw` command line vault access | no (only `bitwarden`) | add to `roles/apps` |
| `bind` | pacman (extra) | `pacman -S --noconfirm bind` 2026-09-15 | `dig`, `nslookup`, `host` | no | add to `roles/base` (or `roles/network`) |
| `wget` | pacman (extra) | `pacman -Su wget` 2026-10-05 | downloads (course material / scripts expect it) | no (`curl` only) | add to `roles/base` |
| `pimsync` | pacman (extra) | personal script 2026-09-01 20:11 (with anki, todoman); config `~/.config/pimsync/pimsync.conf`, in old `dotfiles-stow` | CalDAV/CardDAV sync to local files | no | ask - overlaps with Planify (own CalDAV); config also missing in `dotfiles-provision` (D) |
| `todoman` | pacman (extra) | same transaction as pimsync; config in old `dotfiles-stow` | CLI task manager on pimsync's data | no | ask - together with pimsync |
| `mysql-workbench` | pacman (extra) | `pacman -S --noconfirm mysql-workbench` 2026-10-05 (deps as `--asdeps`) | visual DB design (DB course) | no (`mariadb-clients` only) | ask - optional app in `roles/apps` / `roles/development` |
| `texmaker` | pacman (extra) | `pacman -S --noconfirm texmaker` 2026-10-15 | second LaTeX editor | no (TeXstudio is) | ask - duplicate of TeXstudio; keep only if really used |
| `tectonic` | pacman (extra) | `pacman -S --noconfirm tectonic` 2026-10-14 | self-contained XeTeX engine | no (TeX Live + latexmk path via VimTeX) | ask |
| GeForce NOW | Flatpak (user), `com.nvidia.geforcenow` | user-scope Flatpak (REPO only has system Flatpaks) | cloud gaming | no - REPO notes it as "plain web page until added" | ask: Flathub app (`apps_flatpak_packages`) or Chromium web app (`apps_webapps`) |
| KNIME Analytics Platform | manual tarball `~/.local/opt/knime`, wrapper `~/.local/bin/knime` (`GDK_BACKEND=x11`), own `.desktop` | user-only location, `~/knime-workspace` | data-analytics workbench (course) | no | ask - source must be decided first (official tarball vs. Flathub vs. AUR; checked in that order per Package Source Policy) |
| `basher` | own repository `~/repos/peppeppa/basher`, wrapper `~/.local/bin/basher` | user's own repo + wrapper | personal tool | no (not in `dotfiles-provision` `config/repositories.txt`) | ask - if still used: add the checkout to `repositories.txt` + wrapper in `dotfiles-provision` |
| Claude Code CLI | mise (`claude = "latest"`), URL handler `.desktop` | user's mise config, several versions installed | AI coding CLI | no | ask - REPO has no npm-global/mise mechanism; source needs a decision |
| Codex CLI | mise (`codex = "latest"`) | user's mise config | AI coding CLI | no | ask - same as Claude Code |
| `mokutil` | pacman (extra) | `pacman -S mokutil` 2026-09-25, right after `virtualbox` | Secure Boot MOK enrollment (signing vbox modules) | no | do not migrate - REPO's recovery design assumes Secure Boot off (`docs/recovery-design.md`; Secure Boot untested per `docs/release/RELEASE_NOTES_v1.0.0.md`) |

## B. Probable additions (uncertain origin)

| Candidate | Evidence | Confidence | Note |
|---|---|---|---|
| `openai-codex-desktop` | Omarchy repo package; `--noconfirm --needed` 2026-08-19 19:25, after an Omarchy update - menu install or Omarchy default rollout | medium | only in the `[omarchy]` repo - REPO never uses Omarchy as a package source; would need another source (ask) |
| `cliamp` | Omarchy default, removed by the user on install day, reinstalled 2026-08-24 with `pacman -S --noconfirm cliamp` | medium-high that the user wants it | `[omarchy]` repo only -> not migratable as is |
| `crush` (mise) | installed under mise but not in the mise config | low-medium | probably a one-off trial |
| `vim` | `--noconfirm --needed vim` 2026-08-19 19:05, directly before `pacman -Syyuu` + Omarchy reinstall | low (looks like an Omarchy update step) | REPO has Neovim; add only if wanted |
| `pandoc` | `pacman -S --noconfirm pandoc-cli` 2026-10-14 - **not installed now** (the transaction did not complete) | medium that it is wanted | ask - `pandoc-cli` is in extra |
| `mysql` (AUR server) | yay build 2026-10-05 18:52 - **not installed now** | low | REPO has `mariadb-clients`; a DB server would rather be Docker (`roles/development`) |
| `texlive-lang-german` | four failed attempts 2026-10-15 (the package name is `texlive-langgerman`) | high that German TeX is wanted | already covered by REPO |

## C. Personal tools already covered by REPO

| Omarchy personal addition | REPO coverage |
|---|---|
| `bitwarden`, `nextcloud-client`, `thunderbird`, `stow` | `roles/apps` / `roles/base` |
| `intellij-idea-ultimate-edition` (AUR build via yay) | Flathub `com.jetbrains.IntelliJ-IDEA-Ultimate` (`roles/apps`) - different source, same product |
| `github-cli`, `anki`, `virtualbox` | `roles/development`, `roles/apps`, `roles/virtualization` |
| `texstudio`, `texlive-bin/-basic/-latex/-latexrecommended/-fontsrecommended/-bibtexextra`, `biber` | `roles/development` (a superset: + latexextra, langgerman, mathscience, binextra, luatex) |
| `flatpak` + Planify (user Flatpak) | Flatpak/Flathub (`roles/apps`); Planify as the Arch package |
| mise runtimes Java / Node 26 / Python + Jupyter stack in mise's Python | `jdk25-openjdk`, `nodejs`/`npm`, `python` + uv Data Science env (JupyterLab, pandas, Streamlit, pydeck, jsonpath-ng, mysql-connector, ...) - Arch versions instead of mise pins |
| `uv` (standalone in `~/.local/bin`) | `uv` from extra |
| `hypr-cheatsheet` (old dotfiles) | Quickshell cheatsheet (`roles/hyprland` + `cheatsheet/`) |
| `ghostty` (switched to on install day) | default terminal |
| Docker (Omarchy default, kept) | `roles/development` (on demand, no docker group) |

## D. Configuration gaps

Only user-specific functionality:

- **pimsync + todoman configuration** lives in the old `dotfiles-stow`
  (`pimsync/`, `todoman/`), not in `dotfiles-provision` (which has only
  `bash`). If they are kept, both configs move to `dotfiles-provision`
  (Stow) - the CalDAV credentials must stay out of it (pimsync can read
  the password from a command, e.g. `bw`).
- **KNIME**: wrapper (`GDK_BACKEND=x11`) + desktop entry + workspace
  location - only after the source decision.
- **basher**: checkout + `~/.local/bin` wrapper - `dotfiles-provision`.
- **Tailscale**: the node must be logged in once by the user (account
  state, never in a repository) - only if the feature is wanted.
- Not gaps (checked): no personal systemd user units/timers (all enabled
  user units are Omarchy's or PipeWire's); no pipx/uv tools/npm globals/
  cargo/go binaries/AppImages; `/usr/local/bin` holds only Omarchy's
  `mkinitcpio` shim; the personal bash aliases are already in
  `dotfiles-provision` (`stow/bash`); `~/.config/{Codex,opencode,
  github-copilot,BraveSoftware,google-chrome*,microsoft-edge*,kitty,
  alacritty,fish}` exist without an installed program (Omarchy skeleton or
  editor-plugin data).

## E. Deliberately excluded

- **Omarchy itself**: `omarchy*`, `omarchy-nvim`, `linux-omarchy*`,
  `limine` + `limine-snapper-sync`, `sddm`, `uwsm`, `omacalc`, `omacut`,
  `omawrite`, `herdr`, `tensaku`, `tobi-try`, `ttfx`, `ttf-ia-writer`,
  Omarchy user units (`omarchy-*`), `mise-bin` swap, the
  `quickshell-git` -> `quickshell` migration, Omarchy's `--needed` post-
  install steps (`libvips`, `zbar`).
- **Omarchy desktop defaults with a REPO owner**: `foot` (Ghostty),
  `ufw`/`ufw-docker` (nftables `roles/firewall`), `fcitx5*` (no input
  method needed), `udiskie` (gvfs/Nautilus), `hyprpicker`,
  `gpu-screen-recorder`, `yaru-icon-theme`, `tmux`, `tldr` (tealdeer),
  `pamixer`, `wtype`, `xdg-terminal-exec`, `systemd-resolved`.
- **Hardware of this X1 Carbon** (`vulkan-intel`, `intel-media-driver`,
  `vpl-gpu-rt`, `thermald`, `sof-firmware`): Omarchy's hardware
  detection, not personal. Relevant only if this machine becomes a REPO
  host - then as its `host_vars` (like `graphics_vaapi_packages` on the
  T440p), measured on the machine, not copied.
- **Old bootstrap path**: the `update-config` alias (curl | bash of the
  old `bootstrapper`) - replaced by `dotfiles-provision`.
- `mokutil` (see A), `moonlight-qt`, `dotnet-runtime`, `ruby`,
  `localsend` (REPO has it via Flathub), `cups*` (see F "ask").

## F. Proposed minimal changes (not implemented)

**Add to REPO base provisioning**
- `bind`, `wget` -> `roles/base` (small CLI tools, official extra).
- `bitwarden-cli` -> `roles/apps` next to `bitwarden`.

**Make optional in REPO (feature flag, per host)**
- `tailscale` as `tailscale_enabled` (system daemon, opt-in) - only after
  the user confirms (see below).

**Install manually after migration (user runtime choice, OS menu ->
Packages)**
- `vim`, `crush`, one-off tools of section B the user still wants.

**Do not migrate**
- `mokutil`, everything in E, Omarchy-repo-only packages as they are
  (`cliamp`, `openai-codex-desktop`), `update-config`.

**Ask the user before deciding**
1. Tailscale - still used? Then opt-in feature on which hosts?
2. pimsync + todoman - still used next to Planify? Then packages + configs
   to `dotfiles-provision`.
3. MySQL Workbench - needed for the course (`roles/development`)?
4. Texmaker and Tectonic next to TeXstudio + TeX Live - keep?
5. pandoc - wanted (the install attempt did not complete)?
6. GeForce NOW - Flathub app or a web app?
7. KNIME - needed; which source?
8. basher - still used? Then into `dotfiles-provision`.
9. Claude Code / Codex CLIs (and the Codex desktop app) - how to source
   them without a mise/npm-global mechanism?
10. Printing - Omarchy brought CUPS (enabled, user adjusted cups packages
    on 2026-09-01 in an Omarchy-shaped transaction); REPO has none. Is
    printing needed?

## Counts

Counted per package/tool (TeX Live parts individually):

| | |
|---|---|
| Confirmed personal additions | 34 |
| ... already covered by REPO | 19 |
| ... missing from REPO | 15 (of which `mokutil` is "do not migrate") |
| Probable / uncertain (B) | 7 |
| User decisions needed (F) | 10 |

## Method and limits

- Only read-only commands over SSH (`BatchMode`): `pacman -Q*`/`-Qi`/`-Sl`
  (local databases, no sync), `grep` of `/var/log/pacman.log`, `flatpak
  list`, `systemctl [--user] list-unit-files`, `ls`/`cat` of
  non-secret wrapper scripts, `.desktop` `Name`/`Exec` lines, the mise
  config (no secrets in it). No sudo, no files written, no discovered
  program executed, no package database synced.
- Not read: credentials, browser profiles, `pimsync.conf`/todoman config
  contents, SSH keys, personal documents. Home directory listed one level
  only.
- `pacman.log` covers the whole life of the system, so the baseline split
  is reliable; whether an Omarchy-menu install was the user's choice or an
  Omarchy rollout is inferred from timing and command shape (marked
  "probable" where it matters).
- Packages removed again before today (e.g. `qpdf`, `cups-pdf`) are not
  listed as wanted software.
- SSH to the laptop was refused once for ~2 minutes in the middle of the
  audit (sshd not reachable, ping fine) and came back by itself; nothing
  was done to it from here.

## Decisions and implementation (2026-10-15)

The user's decisions on section F, implemented in the same change as this
section (structurally tested; not provisioned on a host yet):

| Item | Decision | Implemented as |
|---|---|---|
| `bitwarden-cli`, `bind`, `wget` | add | `roles/apps` / `roles/base` |
| LaTeX in Neovim | complete it | already there: VimTeX + latexmk + biber/biblatex + Zathura SyncTeX (forward `\lv`, inverse Ctrl+click) - a biblatex/biber test document built on the laptop. Added: `texlab` (pacman, completion/diagnostics/navigation; VimTeX's omni completion dropped as a second source) |
| Pandoc | add (was missing) | `pandoc-cli` (`roles/development`) |
| Texmaker, Tectonic | not needed | dropped - the TeX Live/latexmk toolchain builds everything, Neovim + TeXstudio are the editors |
| MySQL Workbench | add | `mysql-workbench` (official extra, `roles/development`); no server |
| Claude Code | add | npm package `@anthropic-ai/claude-code` into `~/.local` (`roles/apps`), `~/.npmrc` initialised when missing; no mise |
| Codex CLI | add | `openai-codex` (official extra) |
| Printing | default on | `roles/printing`, `printing_enabled: true`, CUPS socket-activated, local only |
| GeForce NOW | web app, not Flatpak | `apps_webapps` `geforce-now-web` -> https://play.geforcenow.com/ |
| KNIME | manual download | `knime-install <archive>` (no Arch/Flathub package; never automatic) |
| Gaming | enable for future installs | existing `roles/gaming`: `gaming_enabled: true` + `vulkan-intel`/`lib32-vulkan-intel` for `laptop` and `workstation` |
| Tailscale, pimsync, todoman, basher | do not migrate | - |

### The seven uncertain candidates (section B)

Documented only - nothing installed.

| Candidate | Audit evidence | In REPO? | Origin (best estimate) | Action |
|---|---|---|---|---|
| `openai-codex-desktop` | `[omarchy]` repo, Omarchy-style install after an Omarchy update | no (the Codex **CLI** is now) | uncertain: menu install or Omarchy rollout | none; the desktop app has no source outside the Omarchy repo - ask if wanted |
| `cliamp` | Omarchy default, removed on day 1, reinstalled 2026-08-24 by hand | no | probably personal | none - `[omarchy]` repo only; ask if wanted |
| `crush` (mise) | installed under mise, not in the mise config | no | probable one-off trial | none |
| `vim` | installed right before an Omarchy system update | no (Neovim) | probably an Omarchy update step | none |
| `pandoc` | install attempt 2026-10-14 did not complete | **yes, now** (`pandoc-cli`) | personal | done |
| `mysql` (AUR server) | yay build 2026-10-05, not installed | no, deliberately (client only) | personal attempt | none - a server would be a Docker container |
| `texlive-lang-german` | four failed attempts (wrong name) | **yes** (`texlive-langgerman`) | personal | none |
