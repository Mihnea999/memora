#!/usr/bin/env python3
"""Memora "Candy": columns of glass capsules over a wash of vivid colour.

Each capsule is a lens: it shows the colour behind it turned over and
magnified, is frosted towards its rim, and catches a thin line of light along
the edge facing the light. The columns are of different widths and the
capsules in them are cut at different heights, with a few round ones among
them, so their edges run everywhere, under the menu bar, the Dock and the
widgets alike, for the Liquid Glass to bend. Magenta, pink, peach, yellow and
lime; no blue. Rendered per pixel (numpy), so it is smooth at any size.

usage: candy.py MODE WIDTH HEIGHT OUT.png      MODE: light | dark
"""
import math
import sys

import numpy as np
from PIL import Image

GAP = 0.011                  # between columns and capsules, screen heights

# Colour ramps, 0..1 (the wash behind runs through them in slow waves).
PAL = {
    "light": {
        "ramp": ["#ff0a7a", "#ff3d9e", "#ff6f6f", "#ffa02a", "#ffe01a", "#b6f01e", "#4fdc4a"],
        "gap": 0.62, "gapTo": "#fff3f7", "rim": 0.80, "frost": 0.15, "edge": "#ffffff",
        "core": "#fff8f0", "coreA": 0.28,
        "dark": False,
    },
    "dark": {
        "ramp": ["#c0006a", "#f0108a", "#ff4f7a", "#ff8a1f", "#ffcc0a", "#a8e60a", "#2fcf3a"],
        "gap": 0.95, "gapTo": "#1c0418", "rim": 0.55, "frost": 0.25, "edge": "#ffd6ea",
        "core": "#ffe6f2", "coreA": 0.22,
        "dark": True,
    },
}


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def ramp(cols, t):
    n = len(cols) - 1
    t = np.clip(t, 0, 0.99999) * n
    i = np.floor(t).astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    return cols[i] + (cols[np.minimum(i + 1, n)] - cols[i]) * f[..., None]


def field(u, v):
    """Where in the ramp the wash is, at screen position u, v (0..1)."""
    t = (0.50 + 0.30 * np.sin(2 * math.pi * (0.55 * u + 0.75 * v) + 0.8)
         + 0.16 * np.sin(2 * math.pi * (1.4 * v - 0.6 * u) + 2.1)
         + 0.08 * np.sin(2 * math.pi * (2.3 * u + 0.3 * v) + 4.0))
    return np.clip(t, 0, 1)


def layout(aspect):
    """Columns (x0, x1) and, in each, capsules (y0, y1), screen heights."""
    rng = np.random.default_rng(21)
    widths = []
    while sum(widths) + GAP * len(widths) < aspect + 0.3:
        widths.append(float(rng.uniform(0.12, 0.23)))
    x = -0.12
    cols = []
    for w in widths:
        caps = []
        y = -rng.uniform(0.15, 0.6)
        while y < 1.2:
            if rng.random() < 0.18:
                h = w                                   # a round one
            else:
                h = float(rng.uniform(0.35, 0.95))
            caps.append((y, y + h))
            y += h + GAP
        cols.append((x, x + w, caps))
        x += w + GAP
    return cols


def render(mode, W, H):
    p = PAL[mode]
    aspect = W / H
    cols_lin = np.stack([lin(hexc(c)) for c in p["ramp"]])
    gap_to = lin(hexc(p["gapTo"]))
    edge_c = lin(hexc(p["edge"]))
    out = np.zeros((H, W, 3), np.uint8)
    rng = np.random.default_rng(5)
    chunk = 240
    px = 1.0 / H
    columns = layout(aspect)
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        y = ((np.arange(y0, y1, dtype=np.float32) + 0.5) / H)[:, None] + np.zeros((1, W), np.float32)
        x = ((np.arange(W, dtype=np.float32) + 0.5) / H)[None, :] + np.zeros((y1 - y0, 1), np.float32)
        u, v = x / aspect, y
        wash = ramp(cols_lin, field(u, v))
        # Between the capsules: the wash, softened towards light (or dark).
        col = wash + (gap_to - wash) * p["gap"]
        for cx0, cx1, caps in columns:
            r = (cx1 - cx0) / 2
            ccx = (cx0 + cx1) / 2
            for cy0, cy1 in caps:
                # Capsule: distance to its vertical centre segment, minus r.
                ccy = (cy0 + cy1) / 2
                hh = (cy1 - cy0) / 2
                sy = np.clip(y - ccy, -(hh - r), hh - r)
                d = np.hypot(x - ccx, y - ccy - sy) - r
                cov = smooth(0.9 * px, -0.9 * px, d)
                if not cov.any():
                    continue
                inner = np.maximum(-d, 0)
                # The lens: the wash behind, turned over and magnified.
                lu = (ccx - (x - ccx) * 0.9) / aspect
                lv = ccy - (y - ccy) * 0.95
                c = ramp(cols_lin, field(lu, lv))
                # Rounded across its width: brighter down the middle.
                across = np.clip((x - ccx) / r, -1, 1)
                round_ = np.sqrt(1 - across * across)
                c = c * (0.86 + 0.20 * round_)[..., None]
                # A soft bright core, as light gathers in the middle of the lens.
                along = (y - ccy) / max(hh, 1e-6)
                core = p["coreA"] * round_ ** 2 * np.exp(-(along * along) * 2.5)
                c = c + (lin(hexc(p["core"])) - c) * core[..., None]
                # Frosted towards the rim: the rim takes the softened wash.
                frost = p["frost"] * np.exp(-inner / (r * 0.28))
                c = c + (col - c) * frost[..., None]
                # A thin line of light along the rim, brightest up and to the left.
                nx = x - ccx
                ny = y - ccy - sy
                nl = np.hypot(nx, ny) + 1e-9
                facing = np.clip(-(nx * -0.5 + ny * -0.86) / nl, 0, 1)
                line = np.exp(-inner / 0.0022) * (0.25 + 0.75 * facing) * p["rim"]
                c = c + (edge_c - c) * np.clip(line, 0, 1)[..., None]
                col = col * (1 - cov[..., None]) + c * cov[..., None]
        s8 = srgb(col) * 255
        s8 += rng.normal(0, 0.9, s8.shape)             # grain: no banding
        out[y0:y1] = np.clip(s8 + 0.5, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    mode, W, H, path = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    Image.fromarray(render(mode, W, H)).save(path)
