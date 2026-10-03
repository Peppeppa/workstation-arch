# Design System

Deliberately small: one theme architecture (colors) and a handful of
font roles. Sizes/spacing are still a couple of constants in `shell.qml`.

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

## Themes

### Theme directory contract (the registry)

```
themes/<id>/            directory name = stable theme id ([a-z0-9-])
  dark  | light         empty marker file - exactly one; the ONLY source of the mode
  theme.yml             data only: name + the 9 semantic colors (+ source comments)
  backgrounds/          wallpapers for this theme (may be empty; .gitkeep keeps it in git)
```

The set of valid directories *is* the theme list - nothing else lists
themes (no QML list, no Ansible list). Adding a theme = adding a valid
directory; it shows up in the bar's theme dialog the next time it opens.
Invalid directories (no/both markers, missing/unknown color, bad hex,
no `theme.yml`/`backgrounds/`) are skipped at runtime and fail
`bootstrap.sh` (`theme validate`), so they are caught early.

`backgrounds/` is part of the contract but not used yet: a later
wallpaper step picks a file from the *active* theme's `backgrounds/`
(e.g. `theme status` exposing them, the dialog offering a choice, a
`background=` line in the state) - the same helper, no new registry.

### One implementation: the `theme` helper

`~/.local/bin/theme` (`roles/theme/templates/theme.j2`, Python, user
level, on demand only) owns discovery, contract validation, rendering,
the state and applying it. Ansible only deploys it and calls
`theme validate` + `theme apply`; the bar calls `theme status --json`,
`theme toggle`, `theme select <dark|light> <id>`. Nothing else renders
theme colors.

Rendered files (all in `~/.config/workstation/theme/`), each consumer
includes its file instead of being re-templated:

| Consumer | File | Included via | Live apply |
|---|---|---|---|
| Quickshell | `colors.json` | `Colors.qml` (`FileView`) | `qs ipc call theme reload` - bindings update in place, no Quickshell reload (coffee mode etc. survive) |
| Hyprland | `hyprland.lua` | `dofile` in `hyprland.lua` (pcall: missing -> Hyprland defaults) | `hyprctl reload` |
| hyprlock | `hyprlock.conf` | `source =` in `hyprlock.conf` | read at every lock |
| GTK | - | GSettings `color-scheme` + `gtk-theme` (`Adwaita`/`Adwaita-dark`), no CSS | immediate for GTK4/libadwaita |

A switch validates the target first, then writes the files atomically
(only if changed), then the state, then applies live - an invalid theme
never reaches any consumer.

### Runtime state

`~/.config/workstation/theme-state`:

```
dark=retro-82
light=rose-pine-dawn
mode=dark
```

`group_vars/all.yml` `theme_dark` / `theme_light` / `theme_mode` are only
the **initial** values: `bootstrap.sh` creates the state from them if it
doesn't exist and otherwise leaves the user's choice alone. A host can
override the initial values in host_vars.

### Bar UI

Left of the clock (fixed slots, nothing shifts): `[coffee][theme]`, both
invisible until hovered. Theme icon = moon (dark) / sun (light) from
`Colors.mode`. Left click: `theme toggle`. Right click: theme dialog
(`ThemeDialog.qml`) - "Dark theme" / "Light theme" dropdowns listing only
themes with that marker, current choice checked; picking one persists it
and applies it immediately only if that mode is active (never switches
the mode). Escape / click outside closes. Discovery runs once per open.

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
| `background` | `background` | base layer | bar, launcher, power menu, toasts, theme dialog, lockscreen |
| `surface` | `surface` | element on the base | launcher search field, dropdown buttons, lockscreen input |
| `foreground` | `foreground` | primary text | everywhere |
| `foreground_muted` | `foregroundMuted` | secondary text | hints, labels, coffee hover, lockscreen date |
| `accent` | `accent` | selection/focus fill | focused workspace, selected rows, lockscreen check |
| `accent_foreground` | `accentForeground` | text on `accent` | same places |
| `border` | `border` | passive outline | inactive Hyprland border, toasts, closed dropdowns |
| `border_active` | `borderActive` | emphasized outline | active Hyprland border, focused overlays, lockscreen input |
| `error` | `error` | destructive/failed/critical | power menu danger icons, critical toasts, lockscreen fail, dialog errors |

Add a role only when something draws it. Not covered yet (Coverage v2):
Ghostty colors (needs a 16-color ANSI palette per theme).

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
