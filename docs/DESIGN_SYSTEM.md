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
| `background` | panels, bar, launcher window | Bar, Launcher |
| `surface` | element on a background (input field, button) | Launcher search field |
| `surfaceHover` | hovered surface | - (Power Menu v1) |
| `text` | primary text | Bar, Launcher |
| `textMuted` | secondary text (descriptions, hints) | Launcher generic names |
| `accent` | focus/selection fill | focused workspace, selected launcher row |
| `accentText` | text drawn on `accent` | same two places |
| `border` | panel/input outlines | Launcher |
| `error` | destructive/failed state | - (Power Menu v1) |

Add a role only when a real component needs one. No `success`/
`warning`/`overlay` yet because nothing draws them.

## Rules

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
  only see `Colors.<role>`. Don't build it before that second consumer
  exists.
