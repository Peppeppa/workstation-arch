// The current (and so far only) color scheme. Managed by Ansible: do
// not edit by hand, see roles/quickshell in workstation-arch.
//
// Values are exactly what shell.qml hardcoded before Central Color
// System v1, so introducing the scheme changed nothing visually:
//   background  #1e1e1e
//   surface     Qt.darker(#1e1e1e, 1.3) - the launcher input field,
//               resolved to its literal value
//   textMuted   #e0e0e0 at 70% alpha - same as the former `opacity:
//               0.7` on text, blends identically on any background
//   accent/border  both #3a6ea5 (launcher outline was the accent)
// surfaceHover/error are not drawn anywhere yet; defined now so Power
// Menu v1 doesn't invent its own.

ColorScheme {
    background: "#1e1e1e"
    surface: "#171717"
    surfaceHover: "#2a2a2a"

    text: "#e0e0e0"
    textMuted: "#b3e0e0e0"

    accent: "#3a6ea5"
    accentText: "#ffffff"
    border: "#3a6ea5"

    error: "#d9534f"
}
