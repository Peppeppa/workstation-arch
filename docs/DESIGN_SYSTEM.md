# Design System

Deliberately small: one theme architecture (colors), a handful of font
roles, one text size - and one token scale for geometry and type sizes
(RICE v1).

## Direction (RICE v1)

**Hybrid**: Omarchy's functional clarity (compact bar, plain lists,
keyboard-first, calm surfaces) with a restrained REPO identity carried by
the themes and a consistent structure - not by effects. Binding:

- **No blur, no shadows, no permanent animations.** A later dialog
  transition is at most 120 ms and only on open/close; nothing moves while
  idle. No additional panel transparency (the bar's optional transparent
  background stays the only one).
- **English** is the one interface language. Existing German texts are
  moved over in the RICE phase that touches their surface - not in one sweep.
- Panels: radius 8 (base), controls 4; small window gaps, subtle 1 px
  borders.
- Colors only from the theme roles (below); contrast is to be validated
  WCAG-AA-oriented in a later step.
- Resource use is measured, not assumed: `docs/RICE_PERFORMANCE_BASELINE.md`.

## Design tokens (`quickshell/Style.qml`)

The third central source next to `Colors` (theme roles) and `Fonts`
(families, the one text size): **geometry and type sizes**. Pure values -
no state, no process; a text-size or theme switch updates every binding.
Values are the default text size's (11) and scale through `Fonts.px`
(`n * size / 11`) by two rules:

| Rule | Function | Meaning |
|---|---|---|
| type | `Style.text(n)` = `Fonts.px(n)` | follows the text size both ways (9 = smaller text) |
| geometry | `Style.grow(n)` = `max(n, Fonts.px(n))` | grows with the text size, never below its default (smaller text keeps click targets and padding) - the rule BarStyle already used |
| screen | `Style.fitWidth(w, available)` | a panel width class, at most `available - 2 x spacingXl`, never negative |

| Token | Base | At 9 | At 18 | Use |
|---|---|---|---|---|
| `panelRadius` | 8 | 8 | 13 | dialogs, menus, popups, toasts |
| `controlRadius` | 4 | 4 | 7 | buttons, rows, fields, hover plates |
| `smallRadius` | 2 | 2 | 3 | thumbnails, dots, small marks |
| `spacingXs` / `Sm` / `Md` / `Lg` / `Xl` | 2 / 4 / 8 / 12 / 16 | same | 3 / 7 / 13 / 20 / 26 | inside an element / related elements / rows, control padding / panel padding / dialog padding, screen edge |
| `compactRowHeight` | 28 | 28 | 46 | dense lists, popup rows, buttons |
| `standardRowHeight` | 32 | 32 | 52 | fields, dialog rows |
| `comfortableRowHeight` | 36 | 36 | 59 | menu / launcher rows |
| `narrowPanelWidth` | 280 | 280 | 458 | short action lists (power menu, today 260) |
| `standardPanelWidth` | 480 | 480 | 785 | menus, ordinary dialogs (today 460-500) |
| `widePanelWidth` | 560 | 560 | 916 | lists with columns (firewall, clipboard; today 540-560) |
| `body` | 13 | 11 | 21 | normal text of overlays/dialogs (= the overlays' `fontSize`) |
| `secondary` | 12 | 10 | 20 | labels, details, bar text |
| `caption` | 11 | 9 | 18 | hints, metadata |
| `sectionTitle` | 14 | 12 | 23 | a heading inside a panel (always >= body + 1) |
| `title` | 15 | 13 | 25 | the panel's title (always >= sectionTitle + 1) |
| `iconSmall` / `iconStandard` / `iconLarge` | 12 / 15 / 22 | 10 / 12 / 18 | 20 / 25 / 36 | glyph in a secondary line / next to body text / app icons |

Fonts stay `Fonts.family` / `Fonts.icons`; tokens only give sizes. The
values were chosen from what the components use today (radius 4 x46 and
8 x12; margins 10/8/6/4/12/16; rows 28/30/36; widths 260-620) so the later
migration moves most surfaces by a pixel or two, not by a redesign.
`qs ipc call shell style` prints the tokens at the current text size.

**When to use them**: every new QML component uses the tokens (no raw
pixel number for spacing, radius, row height, panel width or text size);
existing surfaces move to them in their RICE phase (bar: phase 2, OS menu and
dialogs: 3, launcher and small widgets: 4, toasts and lockscreen: 6). Until
then their own numbers stay - no partial edits outside a phase.

**Deliberate exceptions** (documented, revisited in their phase):

- Bar (phase 2 done): `bar/BarStyle.qml` is built on the tokens - edge
  inset and label padding `spacingMd`, icon <-> label and popup gap
  `spacingSm`, hover radius `controlRadius`, popup radius `panelRadius`
  (grows like every panel), type `secondary`/`body`. The bar popups (audio,
  Bluetooth, network, power, theme, timer, wallpaper picker, tray menu) use
  `Style` spacing/radius/type tokens wherever their value equals one at the
  default size. Bar-specific literals that stay: height 26 and icon slot 27
  (`Style.grow`), the 13 px bar glyph and 15 px tray image, hover inset 3,
  underline 2, drag threshold/corridor and the 120/140 ms durations, the
  popup padding 10, hairline borders 1. Popup literals that stay because
  they are no token step or bound to their own geometry: cards radius 6
  (between a popup's 8 and a row's 4), the 6/10/3 px gaps of the network/
  Bluetooth rows, 24 px row buttons, the battery track (8 px high, radius =
  half its height), the 6 px volume track, the signal bars, the 196/180 px
  QR plate.
- Dialogs and menus (phase 3 done): every centred question/form is a
  `ui/DialogFrame` (width class, `panelRadius`, `spacingXl` padding,
  `title` heading, clipped at the screen height) with `ui/DialogText`
  paragraphs (body / detail / hint / error) and `ui/DialogButtons` (right
  aligned, the keyboard selection = the primary button; the owner keeps
  stages, keys, focus and the close policy). Updater, snapshot slots,
  snapshot mode, firewall question and rule form, theme import use it; the
  OS menu (`standardPanelWidth`), power menu (`narrowPanelWidth`),
  clipboard, firewall and scratchpad windows (`widePanelWidth`), Appearance
  (`standardPanelWidth`) and the cheatsheet use the tokens. A button that is
  not usable right now is `PopupButton.muted` (muted text, no hover plate,
  still clickable so the owner can say why) - no `opacity`. The interface
  text of these surfaces is English (snapshot/firewall/updater/scratchpad
  were German). Stays: button height 24 (`Style.grow`; below
  `compactRowHeight`, buttons sit inside rows), the OS menu's fixed top
  edge, clipboard/scratchpad heights 420/380 (`Style.grow`), the Bluetooth
  popup dimming the other devices during a pairing (row `opacity`, the one
  remaining use; whole row incl. icons).
- Launcher and small surfaces (phase 4 done): menu/launcher rows (OS menu
  root 34 -> 36, search and Applications, power menu actions) =
  `comfortableRowHeight`, list rows 32 / fields 30 -> `standardRowHeight`,
  tabs/chips 28 = `compactRowHeight`; panel padding 10 -> `spacingLg`, row
  text inset 10 -> `spacingMd`, 6 px gaps -> `spacingSm`; app icons
  `iconLarge`; cheatsheet/scratchpad type on `body`/`secondary`/`caption`.
  Stays: thumbnails and cards radius 6 (Appearance wallpaper, picker grid),
  the wallpaper picker grid (620, 320x180 thumbnails), the scratchpad's 3 px
  marks and its own adjustable editor font, the bar's workspace dots and
  tray slots (bar geometry).
- The wallpaper picker's thumbnail grid (620) is wider than `widePanelWidth`
  by its content.
- hyprlock and Hyprland are not QML: their sizes are set in their
  templates from the same base values (Hyprland: phase 5, below; hyprlock:
  phase 6).

### Windows (Hyprland, RICE v1 phase 5)

`roles/hyprland` `conf/appearance.lua`, values in `roles/hyprland/defaults`
(per host overridable):

| Setting | Value | Token it follows |
|---|---|---|
| `general.gaps_in` | 4 (per side: 8 px between windows) | `spacingSm` / `spacingMd` |
| `general.gaps_out` | 8 (to the screen edge and the bar) | `spacingMd` |
| `general.border_size` | 1 | the 1 px hairline of every panel |
| `decoration.rounding` | 4 | `controlRadius` |
| border colors | `border_active` (focused) / `border` | theme roles |
| blur / shadow / animations | off | Direction |

Before: Hyprland's defaults (gaps 5/20, rounding 0). Square tiling again:
`hyprland_gaps_in: 0`, `hyprland_gaps_out: 0`, `hyprland_rounding: 0`.

### Toasts and lockscreen (RICE v1 phase 6)

- Toasts (`Notifications.qml`): panel radius `panelRadius`, padding
  `spacingLg`, icon gap `spacingMd`, type `body`/`secondary`/`caption`,
  8 px (`spacingMd`) from the screen's top/right edge below the bar - the
  same as Hyprland's `gaps_out`, so toasts line up with the windows. Width
  360 (`Style.grow`; a toast sits between the narrow and standard panel
  classes).
- Lockscreen (`hyprlock.conf`): input field rounding 4 (`controlRadius`),
  2 px `border_active` outline (the one 2 px outline: the field must be
  findable on a plain background), colors from the theme roles, fonts from
  `group_vars`. Clock 72 / date 18 px stay fixed: hyprlock is configured by
  Ansible, the text size is runtime state (`theme` helper) and never
  reaches it. Validated statically only - the unattended batch never locks
  the session.

**Rules for new QML components**

- Sizes from `Style`, colors from `Colors`, families from `Fonts` - nothing
  else; a missing token is added to `Style.qml` (and this table), never a
  local constant.
- Panels: `Style.fitWidth(<class>, screen width)`, radius `panelRadius`,
  padding `spacingLg`/`spacingXl`; rows at least `compactRowHeight`.
- No `opacity` to fake a muted or disabled color: use `foregroundMuted`.
- No blur, shadow, permanent animation or extra transparency.
- Interface text in English.

## Typography

Font names are defined once in `group_vars/all.yml`, by role:

| Role | Variable | Font | Used by |
|---|---|---|---|
| UI | `desktop_ui_font_family` (+ `_size` 11) | Adwaita Sans | GTK interface font, fontconfig `sans-serif` (Qt apps) |
| Shell | `desktop_shell_font_family` | FiraCode Nerd Font | our own surfaces: Quickshell (`Fonts.family`), hyprlock |
| Monospace | `desktop_monospace_font_family` | FiraCode Nerd Font Mono | fontconfig `monospace`, GTK monospace, Ghostty |
| Icon | `desktop_icon_font_family` | FiraCode Nerd Font Propo | Nerd Font glyphs next to text (`Fonts.icons`) |

Serif stays the distro default (documents). Quickshell components use
`font.family: Fonts.family` / `Fonts.icons` - never a font name literal.

Sizes: ONE desktop text size (presets 9-18 px, default 11), owned by the
`theme` helper (`theme text-size`, Appearance -> Text size). Quickshell
sizes are written for the default size and pass through `Fonts.px(n)`
(BarStyle for the bar, the `fontSize` handed down by shell.qml for the
overlays, `Fonts.px()` for rows/panels that hold text) - never a raw
pixel size for text. Ghostty and GTK follow through the helper (see
`docs/feature-architecture.md` "Appearance").

## Themes

### Theme directory contract (the registry)

```
themes/<id>/            directory name = stable theme id ([a-z0-9-])
  dark  | light         empty marker file - exactly one; the ONLY source of the mode
  theme.yml             data only: name, the 11 semantic colors, the 16 terminal colors
                        (+ source comments); optional `neovim:` block (see below)
  backgrounds/          wallpapers for this theme (may be empty; .gitkeep keeps it in git)
```

The set of valid directories *is* the theme list - nothing else lists
themes (no QML list, no Ansible list). Adding a theme = adding a valid
directory; it shows up in the bar's theme dialog the next time it opens.
Invalid directories (no/both markers, missing/unknown color, bad hex,
no `theme.yml`/`backgrounds/`) are skipped at runtime and fail
`bootstrap.sh` (`theme validate`), so they are caught early.

`backgrounds/` holds the theme's wallpapers (`*.png|jpg|jpeg|webp|gif`,
feature `wallpaper`): the directory is the list - no second registry.
The helper resolves the active theme's wallpaper (remembered per-theme
choice, else the first file in sorted order, else none = the theme's
`background` color) and ships it in `colors.json`; Quickshell draws it.
GIFs play animated. Own images can simply be dropped into the directory
(untracked files are never touched by git pull/bootstrap).

Every shipped theme carries two plain test wallpapers (1920x1080 PNG,
one solid color each, no alpha) for exercising the picker and per-theme
persistence - derived from the theme's own roles, not a second palette:
`test-01.png` = `colors.background`, `test-02.png` = `colors.border` (the
one role clearly distinct from `background` in every theme; `surface` is
nearly identical to it in several). Regenerate them from `theme.yml`
when those two colors change.

### One implementation: the `theme` helper

`~/.local/bin/theme` (`roles/theme/templates/theme.j2`, Python, user
level, on demand only) owns discovery, contract validation, rendering,
the state and applying it. Ansible only deploys it and calls
`theme validate` + `theme apply`; the bar calls `theme status --json`,
`theme toggle`, `theme select <dark|light> <id>`, `theme wallpaper
list|set <file>`. Nothing else renders theme colors or picks wallpapers.

### Runtime vs. initial deployment

- **Ansible = initial deployment / provisioning only**: installs the
  helper, deploys the app config *bases* (which merely include the
  generated files), creates the state from `group_vars` if missing,
  validates the theme directories and runs `theme apply` once per
  bootstrap (a no-op when nothing changed). It never renders theme
  colors, never touches an existing state, and is never the way to
  switch themes.
- **Runtime = the `theme` helper + native interfaces**: switching, picking
  and applying happen only through the helper (bar clicks/dialog or
  the CLI), which talks to Quickshell IPC, `hyprctl`, GSettings and
  signals - no sudo, no bootstrap, no daemon.

Rendered files (all in `~/.config/workstation/theme/`), each consumer
includes its file instead of being re-templated:

| Consumer | File | Included via | Live apply |
|---|---|---|---|
| Quickshell | `colors.json` (+ wallpaper) | `Colors.qml` (`FileView`); `Wallpaper.qml` reads `Colors.data.wallpaper` | `qs ipc call theme reload` - bindings update in place, no Quickshell reload (coffee mode etc. survive) |
| Hyprland | `hyprland.lua` | `dofile` in `hyprland.lua` (pcall: missing -> Hyprland defaults) | `hyprctl reload` |
| hyprlock | `hyprlock.conf` | `source =` in `hyprlock.conf` | read at every lock |
| Ghostty | `ghostty` | `config-file = ?...` in `config.ghostty` | `SIGUSR2` to Ghostty: every open window recolors, no restart |
| GTK | - | GSettings `color-scheme` + `gtk-theme` (`Adwaita`/`Adwaita-dark`), no CSS; GTK3 resolves the name `Adwaita-dark` only via `gnome-themes-extra` (`roles/theme`) - without it GTK3 apps fall back to light | immediate for GTK4/libadwaita; GTK3 apps on restart |

A switch validates the target first, renders every output in memory,
stages all changed outputs *and* the state as temp files, and renames
them into place only once all staged - then applies live. An invalid
theme never reaches any consumer; a write failure changes nothing.

### Runtime state

`~/.config/workstation/theme-state`:

```
dark=retro-82
light=rose-pine-dawn
mode=dark
wallpaper.retro-82=sunset.png      # per-theme wallpaper choice (optional lines)
```

`group_vars/all.yml` `theme_dark` / `theme_light` / `theme_mode` are only
the **initial** values: `bootstrap.sh` creates the state from them if it
doesn't exist and otherwise leaves the user's choice alone. A host can
override the initial values in host_vars.

### Bar UI

The theme widget (`bar/widgets/Theme/`, see `docs/feature-architecture.md`
"Bar") shows a moon (dark) / sun (light) from `Colors.mode`. Left click:
`theme toggle`. Right click: the theme popup (`Theme/Popup.qml`) - "Dark
theme" / "Light theme" dropdowns listing only themes with that marker,
current choice checked; picking one persists it and applies it
immediately only if that mode is active (never switches the mode). With
the wallpaper feature the popup also shows the active theme's wallpapers
as thumbnails (click = `theme wallpaper set`). Escape / click outside
closes. Discovery runs once per open.

### Bar look (RICE v1)

Geometry and type sizes live in `bar/BarStyle.qml` (on the `Style` tokens; values at the default text size below); colors stay the
semantic roles. Omarchy-style compact bar:

| Element | Value |
|---|---|
| Bar height / edge inset | 26 px / 8 px (`spacingMd`) |
| Icon widget slot / glyph | 27 px / 13 px (`Fonts.icons`); tray: 24 px slot / 15 px image |
| Labels | 12 px `Fonts.family`, 8 px padding each side |
| Hover | `surface` plate, inset 3 px, radius 4 (`controlRadius`) |
| Normal text / icons | `foreground_strong` (bright in dark themes, full-contrast dark in light themes) |
| Active (on / connected / focused) | `accent` |
| Muted (off / nothing happening) | `foreground_muted` |
| Warning (battery low) | `error` |
| Popup open | 2 px `accent` underline under the widget |
| Popups | `background`, 1 px `border_active`, radius 8 (`panelRadius`), padding 10, 4 px (`spacingSm`) below the bar |
| Drag | lifted widget on a `surface` plate with `border_active`; landing place outlined in `accent`; neighbours slide 120 ms (only during a drag) |
| Tooltips | none: **bar widgets do not show hover tooltips by default.** `BarWidget.tooltip` stays as an opt-in for a widget explicitly meant to have one (or whose function is not understandable without); no substitute labels |

Background: `solid` (`background`, default) or `transparent` (bar
setting, `qs ipc call bar setBackground ...`; until a settings menu
exists: right click on free bar space flips it - see
`docs/feature-architecture.md` "Bar"); transparent drops only the bar's
own fill, never adds blur or shadow. No permanent animation.

### OS menu and Applications

`mainMod+Space` opens the OS menu (`osmenu/`, see
`docs/feature-architecture.md` "OS menu"): a plain vertical list
(Applications, Appearance, Network, Settings, System) in the launcher's
panel style - 34 px rows, `accent` fill + `accent_foreground` on the
selected row, a chevron on entries that open a page. Escape always closes
the whole menu.

Applications (`osmenu/AppsPage.qml` + `osmenu/AppModel.qml`, the former
`Launcher.qml`) lists `DesktopEntries.applications`
(Quickshell's own XDG parser) - no app list of our own. Shown is an entry
that passes, in this order:

1. its own metadata: `NoDisplay=true` and `Hidden=true` are dropped by
   Quickshell (e.g. imv - it needs a file -, Xwayland, portals, pinentry,
   quickshell). Quickshell 0.3.1 does not evaluate `OnlyShowIn`,
   `NotShowIn` or `TryExec`; the entries that depend on them are in rule 3.
2. categories: `Settings`, `DesktopSettings`, `Debugger` are hidden
   (settings dialogs, debuggers - e.g. Qt D-Bus viewer).
3. a small denylist of desktop-file ids (`hiddenIds`), each annotated with
   the package that brings it: avahi-discover/bssh/bvnc (avahi), lstopo
   (hwloc), Qt Designer/Linguist/Assistant (qt6-tools via VirtualBox),
   qv4l2/qvidcap (v4l-utils via ffmpeg), Software Token / (small)
   (stoken-gui, stoken-gui-small: stoken via openconnect). Nautilus adds only "Files" (its
   autorun helper is `NoDisplay`).

Hiding an entry never uninstalls anything - those packages are
dependencies. New apps appear without any change here.

Each row (34 px) is only `[icon] Name`: the entry's icon
(`Quickshell.iconPath(icon, true)`, resolved in the session icon theme
`QS_ICON_THEME` = Papirus; Flatpak icons via `XDG_DATA_DIRS`), 22 px,
decoded asynchronously, or a muted generic application glyph when the
theme has none; then the name (`accent_foreground` on the selected row).
No generic name/comment is shown - the search still matches name, generic
name and keywords.

Open, the menu's transparent surface covers the focused output below the
bar strip (like the bar popups): a click outside the panel closes it,
Escape too. Closed, the window is unmapped - no surface, no input region.
The Appearance window and its wallpaper picker follow the same pattern.

Hover affordances inside popup rows (the X that forgets a known Wi-Fi
network or Bluetooth device) are part of the row, not tooltips.

Icon theme: Papirus (`papirus-icon-theme`, official `extra`;
`group_vars/all.yml` `desktop_icon_theme`) - one consistent style that
covers our apps under their own `Icon=` names (checked against the
package's file list: Chromium, Ghostty, Thunderbird, Nautilus, Bitwarden,
Obsidian, VirtualBox, Flatpak IntelliJ, mpv, Zathura, btop, Neovim,
Xarchiver). Missing there (Yazi): the app's own icon via hicolor. No
icon copies of our own, no per-app overrides. GTK keeps Adwaita.

### Shipped themes

| id | Name | Mode | Source |
|---|---|---|---|
| `retro-82` (initial dark) | Retro 82 | dark | OldJobobo, `retro-82.nvim` palette |
| `solarized-dark` | Solarized Dark | dark | Ethan Schoonover, `altercation/solarized` |
| `catppuccin-mocha` | Catppuccin Mocha | dark | `catppuccin/palette` |
| `rose-pine-dawn` (initial light) | Rosé Pine Dawn | light | `rose-pine/palette` (the light Rosé Pine variant) |
| `catppuccin-latte` | Catppuccin Latte | light | `catppuccin/palette` |

### Semantic roles

| Role (`theme.yml`) | QML (`Colors.`) | Meaning | Consumers |
|---|---|---|---|
| `background` | `background` | base layer | bar, OS menu, Appearance, power menu, toasts, theme dialog, lockscreen |
| `surface` | `surface` | element on the base | search field, dropdown buttons, highlighted connected rows, lockscreen input |
| `foreground` | `foreground` | primary text | everywhere |
| `foreground_strong` | `foregroundStrong` | high-emphasis text/icons (bright in dark themes) | bar widgets' normal state |
| `foreground_muted` | `foregroundMuted` | secondary text | hints, labels, coffee hover, lockscreen date |
| `accent` | `accent` | selection/focus fill | focused workspace, selected rows, lockscreen check |
| `accent_foreground` | `accentForeground` | text on `accent` | same places |
| `border` | `border` | passive outline | inactive Hyprland border, toasts, closed dropdowns |
| `border_active` | `borderActive` | emphasized outline | active Hyprland border, focused overlays, lockscreen input |
| `error` | `error` | destructive/failed/critical | power menu danger icons, critical toasts, lockscreen fail, dialog errors |
| `success` | `success` | positive/enabling action | Firewall "Aktivieren" |

Add a role only when something draws it.

### Terminal palette contract

Every `theme.yml` also has a mandatory `terminal:` block with exactly the
16 ANSI colors `black, red, green, yellow, blue, magenta, cyan, white,
bright_black, ..., bright_white` (palette 0-15), taken from the theme's
own terminal palette (source in the file) - never assembled from the
semantic roles. Consumer: Ghostty. Ghostty's background/foreground are
the semantic `background`/`foreground`; cursor = `foreground` on
`background`; selection = `accent` / `accent_foreground` (the semantic
selection pair) - no extra per-app fields.

### Theme sources (Omarchy theme repositories)

Omarchy theme repositories are theme **data sources** - never a runtime
dependency, never vendored into this repository.

| | Where | Owner |
|---|---|---|
| Manifest | `themes/sources.yml`: `id`, `name`, `url`, `commit` (exact, tested), `mode` | this repository (edited by `theme import`/`remove`; the user commits it) |
| Source | `~/.local/share/workstation/themes/sources/<id>/` (shallow checkout at the pinned commit) | upstream data |
| Compiled theme | `~/.local/share/workstation/themes/compiled/<id>/`: marker, `theme.yml`, `btop.theme`, `backgrounds` -> the source's `backgrounds/`, `source.json` (url, commit, used / ignored files) | the `theme` helper |
| Selection | `~/.config/workstation/theme-state` - the only runtime theme state | the user |

**Repositories are untrusted data.** The helper fetches with hooks,
submodules, symlinks, filters, credential helpers, the user's git config
and every protocol except https switched off, and only READS known files:
palette from `colors.toml`, else `alacritty.toml`, else `ghostty.conf`
(+ `hyprland.conf`'s active border as accent) -> our roles (derived only
where the source has no value, by contrast) + the 16 terminal colors;
`neovim.lua` as TEXT -> the `neovim:` block (plugin, name, colorscheme,
regex-checked; plugin options are not taken); `btop.theme` color lines
only; `backgrounds/` referenced. Nothing is executed, sourced or installed
because a repository mentions it (Waybar, Walker, Mako, Alacritty, Foot,
GTK CSS, Chromium/icon themes, editors ...): listed as ignored.

**Bundled + source.** A manifest id that also exists under `themes/`
associates that bundled theme with its repository (Retro 82, Solarized
Dark): the bundled `theme.yml` and marker stay authoritative, the source
adds its backgrounds (the wallpaper list is the union; local files win a
name clash) and payloads. Bundled themes are never removable.

**Import / remove** (Settings -> Appearance -> Theme -> Import, or
`theme import <url> dark|light`, `theme remove <id>`): the user picks the
mode; id and name come from the repository name (`omarchy-retro-82-theme`
-> `retro-82` / Retro 82); an existing id is refused, never overwritten.
Remove deletes source, compiled theme and manifest entry - refused for the
selected dark/light theme. No Ansible, no sudo, no automatic commit.

**Provisioning**: `theme sync-sources` (roles/theme) fetches every entry
at its pinned commit and compiles it - network only when one is missing;
afterwards themes work offline. No updating: pins move only by an explicit
new import.

### App payloads (Neovim)

A theme may name the real port of itself for an app that has one - as
data, never code (the idea of Omarchy themes carrying `neovim.lua`, without
executable files in the theme directory):

```yaml
neovim:
  plugin: "catppuccin/nvim"        # lazy.nvim plugin "owner/repo" (regex-checked)
  name: "catppuccin"               # optional lazy.nvim name
  colorscheme: "catppuccin-mocha"  # the exact colorscheme of THIS theme
```

The background (dark/light) is the marker file's, never repeated here. The
helper renders `neovim.lua` (lazy.nvim spec: every theme's plugin, lazy,
+ LazyVim's colorscheme hook) and `neovim-current.lua`; running Neovims
get `doautocmd User WorkstationTheme` over their own RPC sockets. A theme
without the block gets Neovim's `default` colorscheme in its mode.

| Theme | Neovim port | colorscheme |
|---|---|---|
| retro-82 | `oldjobobo/retro-82.nvim` (the palette's own author) | `retro-82` |
| solarized-dark | `maxmx03/solarized.nvim` | `solarized` + background dark |
| catppuccin-mocha | `catppuccin/nvim` | `catppuccin-mocha` |
| rose-pine-dawn | `rose-pine/neovim` | `rose-pine-dawn` |
| catppuccin-latte | `catppuccin/nvim` | `catppuccin-latte` |

### Coverage

| App | Status |
|---|---|
| Quickshell, Hyprland borders, hyprlock, GTK mode, Ghostty | themed, live switch |
| Neovim (LazyVim with `lua/plugins/workstation-theme.lua`) | the theme's own Neovim port, live switch (explicit event, no watcher) |
| Shell tools (Starship, bat, eza, fzf, lazygit) | follow through Ghostty's 16-color palette (Starship default config: named ANSI colors; `BAT_THEME=ansi`) |
| btop | follows the theme at btop's start: `~/.config/btop/themes/workstation.theme` -> the helper's `btop.theme` (the source's own btop theme, else one from the palette); `btop.conf` only created if missing. No live reload exists |
| GTK/libadwaita apps (Nautilus, ...) | follow the GTK light/dark preference natively (libadwaita: `color-scheme`; GTK3: `gtk-theme`) |
| Qt apps (Anki, Nextcloud, VirtualBox, ...) | follow light/dark through Qt's `xdgdesktopportal` platform theme (`QT_QPA_PLATFORMTHEME`, session env from Hyprland's config): the portal's `color-scheme`, live by its signal. Fusion's own dark/light palette, not the theme's colors (no qt6ct/Kvantum: no extra package or config). Before (measured): light palette in the dark theme. Quickshell and the polkit agent are started without it. Anki reads the mode only at its own start (restart it after a switch) |
| Cursor | Adwaita 24 px for the whole session (`XCURSOR_THEME`/`XCURSOR_SIZE`, `group_vars` `desktop_cursor_*`; Hyprland syncs gsettings) |
| Zathura | deferred: its config isn't repo-managed and a running window only re-reads colors via its own `:source` command (no signal/IPC) |
| Browsers, Thunderbird, Bitwarden, Flatpaks | not themed by design (no CSS/app hacks; native preference only) |

### Performance

Zero idle cost: no process, timer, watcher or polling. The helper runs
for a moment on a click / dialog open / bootstrap and exits; 5 or 50
theme directories only matter while the dialog is opening.

## Rules

- Components never hardcode a color (hex, `Qt.rgba`, `Qt.darker` of a
  theme color, `opacity` to fake muted text) and never branch on
  dark/light or on a theme name. If no role fits, add one to the
  contract and every theme.
- Allowed locally: `"transparent"` (absence of a fill).
- One selection language: keyboard selection and mouse hover are the
  same state, drawn as `accent` fill + `accentForeground`. Unavailable
  entries use `foregroundMuted` (when not selected); they stay
  selectable, activating them does nothing.
- Icons: Nerd Font glyphs via `Fonts.icons`, always next to a text
  label - no icon library.
- Theme directories are data/assets only: no templates, no code, no
  downloads; read only from the repo's `themes/`.
- Purely declarative at runtime: no process, timer, polling or file
  watcher for theming.
