#!/usr/bin/env python3
"""Generate the Ly login background (roles/display_manager/files/
workstation-background.dur) - an original, static pixel-art night scene.

Ly (a console TUI) cannot show images; its only background art is a
durdraw file (`animation = dur_file`). This writes ONE frame on a 240x67
console (1920x1080, 8x16 font) = 240x134 square pixels: each cell is a
space or U+2580 (upper half block) - upper pixel = foreground, lower
pixel = background.

The Linux console is not truecolor: the kernel maps an RGB foreground to
its 16 console colors and an RGB BACKGROUND to only 8 (a channel counts
only from 0x80; measured on the laptop: a dark-gray sky turned into
black/gray stripes). So the palette is the console's own, each color
written as an xterm-256 index (Ly reads .dur color maps as 256 colors and
converts them; 0-15 avoided) that the kernel maps exactly onto it - FG and
BG below. Dark gray exists only as a foreground (upper pixels). Only the
upper half block is used: with U+2584/U+2588 in the frame the console
rendered Ly's own text with wrong glyphs (laptop, 2026-10-06).

Deterministic (fixed seed, no dependencies): re-running gives the same
file. Usage:
    scripts/ly-background.py OUT.dur [--preview OUT.png]   (preview needs Pillow)
"""
import gzip
import json
import math
import sys

W, H = 240, 134            # pixels (H / 2 = 67 console lines)
HORIZON = 98               # first pixel row of the sea

# Console colors (what the screen shows) and the xterm-256 index that the
# kernel maps exactly onto each - rgb_foreground()/rgb_background() in
# drivers/tty/vt/vt.c.
BLACK, DARK, GRAY, BLUE, BROWN, RED, CYAN = "black", "dark", "gray", "blue", "brown", "red", "cyan"
VT = {BLACK: (0, 0, 0), DARK: (85, 85, 85), GRAY: (170, 170, 170), BLUE: (0, 0, 170),
      BROWN: (170, 85, 0), RED: (170, 0, 0), CYAN: (0, 170, 170)}
FG = {DARK: 238, GRAY: 248, BLUE: 17, BROWN: 94, RED: 88, CYAN: 23}       # max <= 0xaa: no bold
BG = {BLACK: 16, GRAY: 102, BLUE: 18, BROWN: 100, RED: 88, CYAN: 30}      # channels >= 0x80
SUN = [BROWN, BROWN, BROWN, RED, RED]       # top -> bottom bands


def rng(seed):
    """Small LCG - deterministic stars without the random module's version drift."""
    state = seed
    while True:
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        yield state


def ridge(x, base, amps):
    return base - sum(a * math.sin(x * f + p) for a, f, p in amps)


def scene():
    px = [[BLACK] * W for _ in range(H)]

    r = rng(82)
    for _ in range(45):                                   # stars, upper sky only
        x, y = next(r) % W, next(r) % (HORIZON - 45)
        px[y][x] = GRAY if next(r) % 6 == 0 else DARK

    cx, cy, rad = W // 2, HORIZON, 34
    far = [(4, 0.045, 0.3), (3, 0.11, 1.7), (1.5, 0.23, 0.9)]
    near = [(5, 0.031, 2.2), (2, 0.09, 0.4), (1, 0.27, 2.9)]
    for x in range(W):                                    # two ridge contours
        edge = abs(x - cx) / (W / 2)                      # rising away from the sun
        for amps, base, col in ((far, HORIZON - 6 - 16 * edge, BLUE),
                                (near, HORIZON - 2 - 10 * edge ** 1.5, DARK)):
            top = int(ridge(x, base, amps))
            prev = int(ridge(x - 1, base, amps))
            for y in range(min(top, prev), max(top, prev) + 1):
                if 0 <= y < HORIZON:
                    px[y][x] = col

    for y in range(cy - rad, cy):                         # sun with retro gaps
        for x in range(cx - rad, cx + rad + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                d = (y - (cy - rad)) / rad                # 0 top .. 1 horizon
                # gaps only on lower (odd) pixel rows: a black background
                # under a colored upper half stays visible on the console
                gap = d > 0.4 and y % 2 == 1 and (y // 2) % max(1, int(5 - 4 * d)) == 0
                px[y][x] = BLACK if gap else SUN[min(len(SUN) - 1, int(d * len(SUN)))]

    for depth in (2, 5, 10, 17, 26):                      # perspective grid on the sea
        for x in range(W):
            px[HORIZON + depth][x] = DARK
    for k in range(-6, 7):                                # rays from the vanishing point
        prev = cx
        for y in range(HORIZON, H):
            x = int(cx + k * 22 * (y - HORIZON + 1) / (H - HORIZON))
            lo, hi = sorted((prev, x))
            for xx in range(max(0, lo), min(W - 1, hi) + 1):
                px[y][xx] = DARK
            prev = x
    for depth in range(1, 30, 3):                         # sun glint, narrowing with depth
        half = max(1, int(rad * 0.6 * (1 - depth / 30)))
        for x in range(cx - half, cx + half + 1):
            px[HORIZON + depth][x] = BROWN
    # dark gray exists only as a foreground (upper half): a dark pixel in a
    # lower half moves up into its cell, so lines stay continuous
    for y in range(1, H, 2):
        for x in range(W):
            if px[y][x] == DARK:
                px[y][x] = BLACK
                if px[y - 1][x] == BLACK:
                    px[y - 1][x] = DARK
    return px


def cell(top, bottom):
    """(char, fg index, bg index, shown top, shown bottom) for two pixels.
    A lower dark-gray pixel becomes black (no dark background); a black
    upper pixel over a colored lower one becomes a full cell of that color
    (a black foreground is not expressible - RGB 0 means 'default')."""
    if bottom not in BG:
        bottom = BLACK
    if top == BLACK or top == bottom:
        return " ", BG[bottom], BG[bottom], bottom, bottom
    return "\u2580", FG[top], BG[bottom], top, bottom


def dur(px):
    lines = H // 2
    cells = [[cell(px[2 * y][x], px[2 * y + 1][x]) for x in range(W)] for y in range(lines)]
    contents = ["".join(c[0] for c in row) for row in cells]
    color_map = [[[cells[y][x][1], cells[y][x][2]] for y in range(lines)] for x in range(W)]   # [x][y]
    movie = {"DurMovie": {
        "formatVersion": 7, "colorFormat": "256", "encoding": "utf-8",
        "framerate": 1.0, "columns": W, "lines": lines, "name": "workstation-arch login",
        "frames": [{"frameNumber": 1, "delay": 0, "contents": contents, "colorMap": color_map}],
    }}
    raw = json.dumps(movie, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return gzip.compress(raw, compresslevel=9, mtime=0)   # mtime=0: byte-identical reruns


def main(argv):
    if not argv or argv[0].startswith("-"):
        sys.exit(__doc__)
    px = scene()
    with open(argv[0], "wb") as f:
        f.write(dur(px))
    if len(argv) == 3 and argv[1] == "--preview":
        from PIL import Image
        lines = H // 2                                    # as the console shows it
        img = Image.new("RGB", (W, H))
        for y in range(lines):
            for x in range(W):
                _, _, _, top, bottom = cell(px[2 * y][x], px[2 * y + 1][x])
                img.putpixel((x, 2 * y), VT[top])
                img.putpixel((x, 2 * y + 1), VT[bottom])
        img.resize((W * 8, H * 8), Image.NEAREST).save(argv[2])


if __name__ == "__main__":
    main(sys.argv[1:])
