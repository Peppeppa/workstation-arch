#!/usr/bin/env bash
# Regression test for the `theme` helper (roles/theme/templates/theme.j2):
# discovery/validation of every shipped theme, rendering, the state rules
# (malformed state never written, never a traceback), wallpaper fallback
# and the serialisation of concurrent changes.
#
# Safe anywhere, also on a running desktop: the helper is rendered against
# a temporary COPY of themes/, runs with a temporary XDG_CONFIG_HOME, and
# hyprctl/gsettings/qs/pgrep/pkill/notify-send/nvim are no-op stubs first on
# PATH (and XDG_RUNTIME_DIR is temporary) - nothing reaches a live session. Needs python3 + python-yaml + jinja2
# (installed with Ansible). Run by tests/run.sh.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { # name, condition result (0 = ok)
    if [ "$2" -ne 0 ]; then echo "FAIL $1"; fail=1; fi
}

cp -r "$repo/themes" "$tmp/themes"
mkdir -p "$tmp/stub" "$tmp/cfg/workstation"
for b in hyprctl gsettings qs pgrep pkill notify-send nvim; do
    printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/$b"
    chmod +x "$tmp/stub/$b"
done
python3 - "$repo/roles/theme/templates/theme.j2" "$tmp/theme" "$tmp/themes" <<'EOF' || exit 1
import sys, jinja2
src, dst, themes = sys.argv[1:]
with open(src) as f:
    text = jinja2.Template(f.read(), keep_trailing_newline=True).render(theme_dir=themes)
with open(dst, "w") as f:
    f.write(text)
EOF
chmod +x "$tmp/theme"
mkdir -p "$tmp/run"
export XDG_CONFIG_HOME="$tmp/cfg" XDG_DATA_HOME="$tmp/data" XDG_RUNTIME_DIR="$tmp/run" PATH="$tmp/stub:$PATH"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
T="$tmp/theme"
state="$tmp/cfg/workstation/theme-state"

# Registry: every shipped theme is valid, both modes are populated.
"$T" validate; check "theme validate (shipped themes)" $?
n_dark=$("$T" list dark | wc -l); n_light=$("$T" list light | wc -l)
n_dirs=$(find "$tmp/themes" -mindepth 1 -maxdepth 1 -type d | wc -l)
[ $((n_dark + n_light)) -eq "$n_dirs" ] && [ "$n_dark" -ge 1 ] && [ "$n_light" -ge 1 ]
check "all $n_dirs theme directories valid ($n_dark dark, $n_light light)" $?
dark=$("$T" list dark | head -1); light=$("$T" list light | head -1)

# Malformed state: exit 1 with a message, state untouched, no traceback.
bad_state() { # name, content, command (default: toggle)
    printf '%b' "$2" > "$state"
    before=$(sha256sum "$state")
    out=$("$T" ${3:-toggle} 2>&1); rc=$?
    [ $rc -eq 1 ] && [ "$before" = "$(sha256sum "$state")" ] && ! grep -q Traceback <<< "$out"
    check "malformed state rejected cleanly: $1 (rc $rc: ${out:0:80})" $?
    out=$("$T" status --json 2>&1); rc=$?
    ! grep -q Traceback <<< "$out"
    check "status survives: $1" $?
}
bad_state "empty file" ""
bad_state "unknown dark theme" "dark=nope\nlight=$light\nmode=dark\n"
bad_state "light theme in dark slot" "dark=$light\nlight=$light\nmode=dark\n"
bad_state "invalid mode" "dark=$dark\nlight=$light\nmode=blue\n" apply
bad_state "not UTF-8 theme id" "dark=\xff\xfe\nlight=$light\nmode=dark\n"
bad_state "binary garbage" "\xff\xfe\x00\x01"
# A damaged byte next to a valid state is no reason to fail: the state is
# rewritten cleanly (it crashed with a UnicodeDecodeError before).
printf 'dark=%s\nlight=%s\nmode=dark\n\xff\xfe\n' "$dark" "$light" > "$state"
out=$("$T" toggle 2>&1); rc=$?
[ $rc -eq 0 ] && grep -qx 'mode=light' "$state" && ! grep -q Traceback <<< "$out"
check "valid state with a damaged line: toggle works, state rewritten" $?

# Valid state: apply renders every output; select of an unknown id fails.
printf 'dark=%s\nlight=%s\nmode=dark\n' "$dark" "$light" > "$state"
"$T" apply >/dev/null; check "apply with a valid state" $?
for f in colors.json hyprland.lua hyprlock.conf ghostty; do
    [ -s "$tmp/cfg/workstation/theme/$f" ]; check "output $f rendered" $?
done
"$T" select dark ../../etc >/dev/null 2>&1; [ $? -eq 1 ]; check "select rejects a path as theme id" $?
"$T" wallpaper set ../../x.png >/dev/null 2>&1; [ $? -eq 1 ]; check "wallpaper set rejects a path" $?

# Wallpaper: per-theme choice, fallback to the first file when it is gone.
wp() { python3 -c "import json,sys; w=json.load(open(sys.argv[1]))['wallpaper']; print(w['file'] if w else 'none')" "$tmp/cfg/workstation/theme/colors.json"; }
files=$(ls "$tmp/themes/$dark/backgrounds" | grep -iE '\.(png|jpe?g|webp|gif)$' | sort)
if [ "$(wc -l <<< "$files")" -ge 2 ]; then
    first=$(head -1 <<< "$files"); second=$(sed -n 2p <<< "$files")
    "$T" wallpaper set "$second" >/dev/null; [ "$(wp)" = "$second" ]; check "wallpaper set" $?
    rm "$tmp/themes/$dark/backgrounds/$second"; "$T" apply >/dev/null
    [ "$(wp)" = "$first" ]; check "missing chosen wallpaper falls back to the first file" $?
fi
for f in "$tmp/themes/$dark/backgrounds/"*; do rm -f "$f"; done
"$T" apply >/dev/null; [ "$(wp)" = none ]; check "theme without backgrounds: no wallpaper" $?

# A theme.yml that is not UTF-8 makes only that theme invalid.
printf '\xff\xfe' >> "$tmp/themes/$light/theme.yml"
out=$("$T" validate 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "^$light: theme.yml is unreadable" <<< "$out" && ! grep -q Traceback <<< "$out"
check "unreadable theme.yml reported, not a crash" $?
cp "$repo/themes/$light/theme.yml" "$tmp/themes/$light/theme.yml"

# Text size: one preference; a state without it means the default; only
# the presets are accepted; it reaches Quickshell (colors.json) and
# Ghostty (font-size, scaled from Ghostty's 12 pt default).
printf 'dark=%s\nlight=%s\nmode=dark\n' "$dark" "$light" > "$state"
[ "$("$T" text-size)" = 11 ]; check "text-size default without a state entry" $?
"$T" text-size 16 >/dev/null; check "text-size 16 accepted" $?
grep -qx 'text-size=16' "$state" && grep -q '"text_size": 16' "$tmp/cfg/workstation/theme/colors.json" \
    && grep -qx 'font-size = 17.5' "$tmp/cfg/workstation/theme/ghostty"
check "text-size in state, colors.json and Ghostty (17.5 pt)" $?
before=$(sha256sum "$state")
"$T" text-size 13 >/dev/null 2>&1; [ $? -eq 1 ] && [ "$before" = "$(sha256sum "$state")" ]
check "text-size outside the presets rejected, state untouched" $?
"$T" text-size 11 >/dev/null && grep -qx 'font-size = 12' "$tmp/cfg/workstation/theme/ghostty"
check "default text size = Ghostty's own default" $?
bad_state "text-size not a number" "dark=$dark\nlight=$light\nmode=dark\ntext-size=big\n"

# Neovim: every theme maps to its own colorscheme + background (marker),
# the spec lists each plugin once; a malformed neovim block is invalid.
printf 'dark=%s\nlight=%s\nmode=dark\n' "$dark" "$light" > "$state"
nv="$tmp/cfg/workstation/theme"
ok=0
for id in $("$T" list dark) $("$T" list light); do
    mode=dark; [ -e "$tmp/themes/$id/light" ] && mode=light
    want=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["neovim"]["colorscheme"])' "$tmp/themes/$id/theme.yml")
    "$T" select "$mode" "$id" >/dev/null && "$T" mode "$mode" >/dev/null || ok=1
    grep -qx "    colorscheme = \"$want\"," "$nv/neovim-current.lua" && grep -qx "    background = \"$mode\"," "$nv/neovim-current.lua" || ok=1
done
check "neovim-current.lua follows every theme exactly" $ok
plugins=$(grep -h '^  plugin:' "$tmp"/themes/*/theme.yml | sort -u | wc -l)
[ "$(grep -c 'lazy = true, priority = 1000' "$nv/neovim.lua")" -eq "$plugins" ]
check "neovim.lua lists each theme plugin once ($plugins)" $?
if command -v luac >/dev/null; then luac -p "$nv/neovim.lua" "$nv/neovim-current.lua"; check "neovim outputs are valid Lua" $?; fi
cp "$tmp/themes/$dark/theme.yml" "$tmp/nv.bak"
sed -i 's|^  plugin: .*|  plugin: "x\\" os.execute()"|' "$tmp/themes/$dark/theme.yml"
"$T" validate >/dev/null 2>&1; [ $? -eq 1 ]; check "malformed neovim plugin makes the theme invalid" $?
cp "$tmp/nv.bak" "$tmp/themes/$dark/theme.yml"

# Theme sources: the compiler on fixture repositories (offline) - data
# only: commented-out Lua ignored, color tables taken, non-color btop lines
# and symlinked files dropped, unknown files reported, ids/names derived.
python3 - "$T" "$tmp" <<'EOF' || fail=1
import os, sys
from importlib.machinery import SourceFileLoader
t = SourceFileLoader("theme", sys.argv[1]).load_module()
tmp = sys.argv[2]
bad = []
def check(name, cond):
    if not cond:
        bad.append(name)
src = os.path.join(tmp, "fixture")
os.makedirs(os.path.join(src, "backgrounds"))
open(os.path.join(src, "colors.toml"), "w").write(
    'background = "#101010"\nforeground = "#e0e0e0"\naccent = "#ff8800"\n'
    + "".join('color%d = "#%02x%02x%02x"\n' % (i, i * 10, i * 10, i * 10) for i in range(16)))
open(os.path.join(src, "neovim.lua"), "w").write(
    '-- return { "evil/commented.nvim", colorscheme = "nope" }\n'
    'return {\n  { "owner/shade.nvim", branch = "v2", name = "shade",\n'
    '    opts = { colors = { bg = "#101010", fg = "#E0E0E0", ["end"] = "x" } } },\n'
    '  { "LazyVim/LazyVim", opts = { colorscheme = "shade" } },\n}\n')
open(os.path.join(src, "btop.theme"), "w").write(
    'theme[main_bg]="#101010"\ntheme[x]="$(touch /tmp/pwned)"\nos.execute("x")\n')
open(os.path.join(src, "waybar.css"), "w").write("* {}")
os.symlink("/etc/passwd", os.path.join(src, "ghostty.conf"))
os.makedirs(t.SOURCES_DIR, exist_ok=True)
entry = {"id": "fixture", "name": "Fixture", "url": "https://example.org/x/omarchy-fixture-theme",
         "commit": "0" * 40, "mode": "dark"}
report = t.compile_source(src, entry)
theme, errors = t.load_theme("fixture")
check("compiled theme valid: %s" % errors, theme is not None)
if theme:
    n = theme["neovim"] or {}
    check("neovim plugin from code, not comment", n.get("plugin") == "owner/shade.nvim" and n.get("colorscheme") == "shade")
    check("neovim branch/name", n.get("branch") == "v2" and n.get("name") == "shade")
    check("neovim colors = hex pairs only", n.get("colors") == {"bg": "#101010", "fg": "#e0e0e0"})
    check("accent from colors.toml", theme["colors"]["accent"] == "#ff8800")
with open(os.path.join(t.COMPILED_DIR, "fixture", "btop.theme")) as f:
    check("btop keeps color lines only", f.read() == 'theme[main_bg]="#101010"\n')
check("symlinked ghostty.conf not read", "ghostty.conf" not in report["used"])
check("unknown files reported", "waybar.css" in report["ignored"])
check("id/name derived", t.derive_id_name("https://github.com/o/omarchy-retro-82-theme") == ("retro-82", "Retro 82"))
for url in ("http://x/y", "https://h/a@b", "https://h/../x", "file:///etc", "https://h/a b"):
    try:
        t.check_url(url)
        bad.append("url accepted: " + url)
    except t.ThemeError:
        pass
print("\n".join("FAIL theme sources: " + b for b in bad))
sys.exit(1 if bad else 0)
EOF

# Concurrency: an even number of parallel toggles ends in the start mode
# (it lost updates before the helper serialised its writes).
printf 'dark=%s\nlight=%s\nmode=dark\n' "$dark" "$light" > "$state"
lost=0
for round in $(seq 20); do
    for i in 1 2 3 4 5 6 7 8; do "$T" toggle >/dev/null 2>&1 & done
    wait
    grep -qx 'mode=dark' "$state" || { lost=1; printf 'dark=%s\nlight=%s\nmode=dark\n' "$dark" "$light" > "$state"; }
done
[ $lost -eq 0 ]; check "20 rounds of 8 parallel toggles each end in the start mode" $?

[ $fail -eq 0 ] && echo "theme-helper: all checks passed"
exit $fail
