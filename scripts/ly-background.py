#!/usr/bin/env python3
"""Generate the Ly login background (roles/display_manager/files/
workstation-background.dur) - an original, static pixel-art night scene.

Ly (a console TUI) cannot show images; its only background art is a
durdraw file (`animation = dur_file`). This writes ONE frame of half-block
characters: each cell is U+2580 (upper half block) with the foreground =
the upper pixel and the background = the lower pixel, so a 240x67 console
(1920x1080, 8x16 font) holds 240x134 square pixels.

Colors are xterm-256 indices, because Ly reads .dur color maps as 256
colors and converts them itself (6x6x6 cube 0/95/135/175/215/255 + the
gray ramp 8..238) - only dark tones, so the login box stays readable.
Indices 0-15 are avoided: Ly maps those to the console's 16 colors.

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

SKY = [232, 233, 234, 17]                  # top -> horizon (gray ramp, then navy)
STAR_DIM, STAR, STAR_TEAL = 238, 244, 66
SUN = [166, 130, 130, 94, 94, 52]           # top -> bottom bands (muted sunset)
MOUNT_FAR, MOUNT_NEAR = 17, 16              # navy silhouette, black front ridge
SEA, GRID, GLINT = 16, 23, 94               # black sea, dark teal grid, sun glint


def rng(seed):
    """Small LCG - deterministic stars without the random module's version drift."""
    state = seed
    while True:
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        yield state


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def sky(x, y):
    # flat gray/navy steps; only a narrow 4x4 ordered dither around each step
    edges = [int(HORIZON * f) for f in (0.38, 0.62, 0.84)]   # band k starts at edges[k-1]
    band = sum(y >= e for e in edges)
    for k, e in enumerate(edges):
        if 0 <= e - y <= 4 and (4 - (e - y)) * 3 > BAYER[y % 4][x % 4]:
            band = k + 1
    return SKY[band]


def ridge(x, base, amps):
    return base - sum(a * math.sin(x * f + p) for a, f, p in amps)


def scene():
    px = [[sky(x, y) if y < HORIZON else SEA for x in range(W)] for y in range(H)]

    r = rng(82)
    for _ in range(55):                                   # stars, upper sky only
        x, y = next(r) % W, next(r) % (HORIZON - 45)
        kind = next(r) % 12
        px[y][x] = STAR_TEAL if kind == 0 else STAR if kind < 2 else STAR_DIM

    far = [(4, 0.045, 0.3), (3, 0.11, 1.7), (1.5, 0.23, 0.9)]
    near = [(5, 0.031, 2.2), (2, 0.09, 0.4), (1, 0.27, 2.9)]
    for x in range(W):
        edge = abs(x - W // 2) / (W / 2)                      # ridges rise away from the sun
        top_far = int(ridge(x, HORIZON - 6 - 16 * edge, far))
        top_near = int(ridge(x, HORIZON - 2 - 10 * edge ** 1.5, near))
        for y in range(max(0, top_far), HORIZON):
            px[y][x] = MOUNT_FAR
        for y in range(max(0, top_near), HORIZON):
            px[y][x] = MOUNT_NEAR

    cx, cy, rad = W // 2, HORIZON, 34                     # sun on the horizon
    for y in range(cy - rad, cy):
        for x in range(cx - rad, cx + rad + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                d = (y - (cy - rad)) / rad                # 0 top .. 1 horizon
                gap = d > 0.45 and (y - (cy - rad)) % max(2, int(9 - 8 * d)) == 0
                if not gap:
                    px[y][x] = SUN[min(len(SUN) - 1, int(d * len(SUN)))]

    cx = W // 2
    for depth in (2, 5, 10, 17, 26):                      # perspective grid on the sea
        for x in range(W):
            px[HORIZON + depth][x] = GRID
    for k in range(-6, 7):                                # rays from the vanishing point
        prev = cx
        for y in range(HORIZON, H):
            x = int(cx + k * 22 * (y - HORIZON + 1) / (H - HORIZON))
            lo, hi = sorted((prev, x))
            for xx in range(max(0, lo), min(W - 1, hi) + 1):
                px[y][xx] = GRID
            prev = x
    for depth in range(1, 30, 3):                         # sun glint, narrowing with depth
        half = max(1, int(rad * 0.6 * (1 - depth / 30)))
        for x in range(cx - half, cx + half + 1):
            px[HORIZON + depth][x] = GLINT
    return px


def dur(px):
    lines = H // 2
    contents = ["▀" * W for _ in range(lines)]
    color_map = [[[px[2 * y][x], px[2 * y + 1][x]] for y in range(lines)] for x in range(W)]
    movie = {"DurMovie": {
        "formatVersion": 7, "colorFormat": "256", "encoding": "utf-8",
        "framerate": 1.0, "columns": W, "lines": lines, "name": "workstation-arch login",
        "frames": [{"frameNumber": 1, "delay": 0, "contents": contents, "colorMap": color_map}],
    }}
    raw = json.dumps(movie, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return gzip.compress(raw, compresslevel=9, mtime=0)   # mtime=0: byte-identical reruns


def xterm_rgb(i):
    """Ly's own 256 -> RGB conversion (src/animations/DurFile.zig), for the preview."""
    if i < 232:
        i -= 16
        lv = [0, 95, 135, 175, 215, 255]
        return lv[i // 36 % 6], lv[i // 6 % 6], lv[i % 6]
    g = 8 + 10 * (i - 232)
    return g, g, g


def main(argv):
    if not argv or argv[0].startswith("-"):
        sys.exit(__doc__)
    px = scene()
    with open(argv[0], "wb") as f:
        f.write(dur(px))
    if len(argv) == 3 and argv[1] == "--preview":
        from PIL import Image
        img = Image.new("RGB", (W, H))
        img.putdata([xterm_rgb(c) for row in px for c in row])
        img.resize((W * 8, H * 8), Image.NEAREST).save(argv[2])


if __name__ == "__main__":
    main(sys.argv[1:])
