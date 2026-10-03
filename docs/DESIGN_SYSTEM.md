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

## Themes (Theme Architecture v1)

Three layers, one direction of data:

1. **Theme palette** - `themes/<id>.yml`: pure data (`name`, `mode`,
   `colors`), nothing executable. Each file says where its values come
   from and which original palette color fills which role.
2. **Semantic colors** - the contract in `roles/theme/defaults/main.yml`
   (`theme_roles`). Every theme fills exactly these roles; `roles/theme`
   validates *all* theme files on every provisioning run (missing/unknown
   role, non-`#rrggbb` value, wrong mode -> the run stops).
3. **Adapters** - templates that turn the active palette (`theme_colors`)
   into each consumer's format. They only ever reference roles, never a
   theme by name.

### Selection (source of truth)

`group_vars/all.yml` (host-overridable): `theme_dark` (preferred dark
theme id), `theme_light` (preferred light theme id), `theme_mode`
(`dark`|`light`). The active theme is the one for `theme_mode`. Core, not
a feature flag - the desktop always has colors; a later switcher is the
optional part.

| id | Name | Mode | Source |
|---|---|---|---|
| `retro-82` (default dark) | Retro 82 | dark | OldJobobo, `retro-82.nvim` palette |
| `solarized-dark` | Solarized Dark | dark | Ethan Schoonover, `altercation/solarized` |
| `catppuccin-mocha` | Catppuccin Mocha | dark | `catppuccin/palette` |
| `rose-pine-dawn` (default light) | Rosé Pine Dawn | light | `rose-pine/palette` (the light Rosé Pine variant) |
| `catppuccin-latte` | Catppuccin Latte | light | `catppuccin/palette` |

New theme = one new file with the 9 roles. No QML/Ansible/app changes.

### Semantic roles

| Role (`themes/*.yml`) | QML (`Colors.`) | Meaning | Consumers |
|---|---|---|---|
| `background` | `background` | base layer | bar, launcher, power menu, toasts, lockscreen |
| `surface` | `surface` | element on the base | launcher search field, lockscreen input |
| `foreground` | `foreground` | primary text | everywhere |
| `foreground_muted` | `foregroundMuted` | secondary text | hints, app names, coffee hover, lockscreen date |
| `accent` | `accent` | selection/focus fill | focused workspace, selected rows, lockscreen check |
| `accent_foreground` | `accentForeground` | text on `accent` | same places |
| `border` | `border` | passive outline | inactive Hyprland border, toasts |
| `border_active` | `borderActive` | emphasized outline | active Hyprland border, focused overlays (launcher, power menu), lockscreen input |
| `error` | `error` | destructive/failed/critical | power menu danger icons, critical toasts, lockscreen fail |

Add a role only when something draws it (no `success`/`warning`/
`surface_alt` yet).

### Coverage

| Consumer | Adapter | Notes |
|---|---|---|
| Quickshell | `roles/quickshell/templates/Colors.qml.j2` | one `Colors` singleton for every component |
| Hyprland | `hyprland.lua.j2` `general.col.*` | active/inactive window border |
| hyprlock | `hyprlock.conf.j2` `$variables` | |
| GTK | GSettings `color-scheme` + `gtk-theme` (`Adwaita`/`Adwaita-dark`) | mode only - native Adwaita, no custom CSS |
| Ghostty | - | **Coverage v2**: needs a 16-color ANSI palette per theme (all five upstreams publish one, Retro 82 incl. a Ghostty file); today only its font is managed |
| Zathura, Thunar, ... | - | not themed by us (GTK apps follow the GTK mode) |

### Runtime switching (prepared, not built)

A switch = change `theme_mode` (or a pick) and re-render the adapters.
What each consumer then needs, all without logout:

- Quickshell: new `Colors.qml` + reload (already automatic via the
  `roles/quickshell` reload handler) - every binding follows.
- Hyprland: picks up a changed `hyprland.lua` itself (`hyprctl reload`
  as fallback).
- hyprlock: reads its config at every lock - nothing to do.
- GTK: `gsettings set ... color-scheme` is live for libadwaita/GTK4
  (via the portal); plain GTK3 apps pick up `gtk-theme` on restart.
- Ghostty (once covered): `reload_config` / restart.

Today that means `./bootstrap.sh -e theme_mode=light` (or a host_vars
change). A switcher should reuse these adapters, not reimplement them -
no daemon, no watcher.

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
- Theme files are data: no templates, no code, no downloads; themes are
  only ever read from the repo.
- Purely declarative at runtime: no process, timer, polling or file
  watcher for theming.
