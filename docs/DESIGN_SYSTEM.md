# Design System

Deliberately small. Today it covers colors only (Central Color System
v1); sizes/spacing are still a couple of constants in `shell.qml`.

## Central color source

All Quickshell colors live in `roles/quickshell/files/quickshell/`:

| File | Role |
|---|---|
| `ColorScheme.qml` | the **contract**: which semantic roles exist (`required` - a scheme missing one fails at load) |
| `DefaultDark.qml` | the current **color scheme**: pure color values, nothing else |
| `Colors.qml` | `pragma Singleton` - the **appearance decision**: which scheme is active; re-exports its roles |

Components read `Colors.<role>` and nothing else:

```qml
color: Colors.background
border.color: Colors.border
```

## Semantic roles

| Role | Meaning | Used by today |
|---|---|---|
| `background` | panels, bar, launcher window | Bar, Launcher, Power Menu |
| `surface` | element on a background (input field, button) | Launcher search field |
| `surfaceHover` | hovered surface | - (unused: in Launcher/Power Menu hover moves the selection instead) |
| `text` | primary text | Bar, Launcher, Power Menu |
| `textMuted` | secondary text (descriptions, hints) | Launcher generic names, Power Menu header + unavailable items |
| `accent` | focus/selection fill | focused workspace, selected launcher/power menu row + button |
| `accentText` | text drawn on `accent` | same two places |
| `border` | panel/input outlines | Launcher, Power Menu |
| `error` | destructive/failed state | Power Menu icons of Logout/Reboot/Shutdown |

Add a role only when a real component needs one. No `success`/
`warning`/`overlay` yet because nothing draws them.

## Rules

- One selection language: keyboard selection and mouse hover are the
  same state, drawn as `accent` fill + `accentText`. Unavailable
  entries use `textMuted` (when not selected); they stay selectable,
  activating them does nothing.
- Icons: glyphs from the already-installed JetBrainsMono Nerd Font
  (`font.family: "JetBrainsMono Nerd Font Propo"`), always next to a
  text label - no icon library/theme dependency.
- Components never hardcode a theme color (hex, `Qt.rgba`, `Qt.darker`
  of a theme color, `opacity` to fake a muted color). If no role fits,
  add one to `ColorScheme.qml` and every scheme.
- Allowed locally: `"transparent"` (absence of a fill, not a color), and
  a value that is truly component-specific - with a comment saying why.
- **Color scheme != theme/appearance.** A scheme is data only. Choosing
  the active scheme (and later dark vs. light) happens only in
  `Colors.qml`. Components never branch on dark/light.
- Purely declarative: a QML singleton evaluated at load. No process,
  timer, polling, or file watcher for theming - ever, without first
  justifying it against `docs/idle-baseline.md`.

## Later: dark/light and more schemes (not built)

- More schemes = more `ColorScheme { ... }` files next to
  `DefaultDark.qml`.
- `appearance` (dark/light) + `preferred_dark_scheme` /
  `preferred_light_scheme` would only change the `scheme:` binding in
  `Colors.qml`. Every role there is already a binding, so Bar/Launcher/
  Power Menu need no change.
- System-wide consistency: today Quickshell is the **only** place in
  this repo that sets colors (Hyprland, mako, Ghostty, GTK/Qt all run
  their own defaults). Once a second consumer gets colors, the scheme
  values should move into one Ansible variable file and be rendered
  (Jinja, like `hyprland.lua.j2`) into `DefaultDark.qml`, mako's config,
  Hyprland's border colors, Ghostty, GTK/Qt settings - one source, many
  generated outputs. Components stay untouched by that move, since they
  only see `Colors.<role>`.
- Second consumer now exists: `roles/hyprland/files/hyprlock.conf`
  (lockscreen) keeps its colors in one `$variable` block mirroring
  `DefaultDark.qml` by hand. Deliberately not generated yet (Lock/Idle
  v1 scope); that block is the first thing the generation step above
  should take over, together with the theme switcher.
