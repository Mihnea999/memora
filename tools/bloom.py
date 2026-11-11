#!/usr/bin/env python3
"""Memora "Bloom": petals of coloured glass opening over a vivid wash of colour.

Bright, saturated colour everywhere, so the Liquid Glass of the menu bar, the
Dock and the widgets has something to bend and tint. The petals open from one
point just below the screen, where a warm light shines through them. The ones
at the back are out of focus, like a photo with a shallow depth of field; the
ones in front are thick, rounded glass: lit along a streak, bright at the rim
facing the light (with a faint warm fringe), showing what is behind them
shifted, and casting a coloured shade. Rendered per pixel (numpy), so it is
smooth at any size.

usage: bloom.py MODE WIDTH HEIGHT OUT.png      MODE: light | dark
"""
import math
import sys

import numpy as np
from PIL import Image

ROOT = (0.42, 1.10)            # where the petals open from (screen fractions)

# Petals, back to front: angle (degrees, -90 = straight up), length and half
# width (screen heights), bend, focus blur (screen heights; 0 = sharp).
SHAPES = [
    (-142, 1.45, 0.27, 0.06, 0.035),   # out of focus, behind
    (-40, 1.50, 0.25, -0.05, 0.035),
    (-162, 1.02, 0.13, 0.10, 0.0),
    (-20, 1.18, 0.13, -0.10, 0.0),
    (-122, 1.24, 0.16, 0.07, 0.0),
    (-62, 1.30, 0.16, -0.07, 0.0),
    (-93, 1.20, 0.15, 0.02, 0.0),
]
# Per mode: the wash (colour pools: x, y, radius, colour), and for each petal
# above its colour at the base, at the tip, and its opacity.
PAL = {
    "dark": {
        "base": "#080517",
        "pools": [(0.0, 0.0, 0.6, "#120a3d"), (1.0, 0.0, 0.55, "#2a0a55"),
                  (0.05, 1.0, 0.55, "#06185a"), (0.95, 1.0, 0.6, "#4a0a30"),
                  (0.5, 0.45, 0.4, "#1d0a48")],
        "colours": [("#2a2bd6", "#7a3cff", 0.55), ("#e0186a", "#ff8a2a", 0.55),
                    ("#0b3fd6", "#17d0ff", 0.88), ("#ff4a12", "#ffcc33", 0.90),
                    ("#3340ff", "#9a7bff", 0.86), ("#d90f6e", "#ff6a4a", 0.88),
                    ("#6a1bff", "#ff48b4", 0.86)],
        "root": ("#ff6a3a", 0.55), "glow": 0.30, "rim": 0.95, "streak": 0.45,
        "shade": 0.55, "lens": 0.03, "vignette": 0.42, "body": 0.62,
    },
    "light": {
        "base": "#f5eefa",
        "pools": [(0.0, 0.0, 0.6, "#dde3ff"), (1.0, 0.0, 0.55, "#ffd9ea"),
                  (0.05, 1.0, 0.55, "#cde4ff"), (0.95, 1.0, 0.6, "#ffdcc0"),
                  (0.5, 0.45, 0.4, "#f1e2ff")],
        "colours": [("#5b5cff", "#a98aff", 0.50), ("#ff4f8e", "#ffb054", 0.50),
                    ("#2563ff", "#2fd0ff", 0.90), ("#ff4a1c", "#ffc21f", 0.92),
                    ("#3f4dff", "#8a72ff", 0.90), ("#ec1c80", "#ff7046", 0.90),
                    ("#7c2cff", "#ff3fae", 0.90)],
        "root": ("#fff1e0", 0.65), "glow": 0.22, "rim": 1.0, "streak": 0.55,
        "shade": 0.28, "lens": 0.03, "vignette": 0.0, "body": 0.50,
    },
}

LIGHT = np.array([-0.55, -0.85])        # light from the upper left
LIGHT = LIGHT / np.linalg.norm(LIGHT)


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


def wash(p, x, y, aspect):
    """The background: colour pools blended by soft weights over the base, and
    the warm light at the heart of the flower."""
    base = lin(hexc(p["base"]))
    acc = np.zeros(x.shape + (3,), np.float32) + base * 0.35
    wsum = np.full(x.shape, 0.35, np.float32)
    for px, py, r, c in p["pools"]:
        dx, dy = (x - px * aspect), (y - py)
        w = np.exp(-(dx * dx + dy * dy) / (r * r))
        acc += w[..., None] * lin(hexc(c))
        wsum += w
    col = acc / wsum[..., None]
    rc, ra = lin(hexc(p["root"][0])), p["root"][1]
    dx, dy = x - ROOT[0] * aspect, (y - ROOT[1]) * 1.3
    g = ra * np.exp(-(dx * dx + dy * dy) / 0.22)
    return col + (rc - col) * g[..., None]


def petal_field(s, x, y, aspect, off=(0.0, 0.0)):
    """A petal: signed distance (screen heights, < 0 inside), outward normal,
    how far along it a point is (0 at the root, 1 at the tip) and where across
    it (-1..1, edge to edge)."""
    ang, length, b, bend = math.radians(s[0]), s[1], s[2], s[3]
    ca, sa = math.cos(ang), math.sin(ang)
    dx, dy = x - (ROOT[0] * aspect + off[0]), y - (ROOT[1] + off[1])
    u = dx * ca + dy * sa              # along the petal, from the root
    v = -dx * sa + dy * ca             # across it
    t = np.clip(u / length, 0, 1)
    v = v - bend * length * t * t      # curving as it opens
    half = b * np.sqrt(np.clip(np.sin(math.pi * t ** 0.72), 0, 1))
    d = np.abs(v) - half
    d = np.where(u > length, np.hypot(u - length, v), d)
    d = np.where(u < 0, np.hypot(u, v), d)
    gy, gx = np.gradient(d)
    n = np.sqrt(gx * gx + gy * gy) + 1e-9
    across = np.clip(v / np.maximum(half, 1e-4), -1, 1)
    return d, gx / n, gy / n, t, across


def render(mode, W, H):
    p = PAL[mode]
    aspect = W / H
    out = np.zeros((H, W, 3), np.uint8)
    rng = np.random.default_rng(11)
    chunk, pad = 240, 2
    px = 1.0 / H
    rc = lin(hexc(p["root"][0]))
    warm = np.array([1.0, 0.55, 0.85], np.float32)
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        ya, yb = max(0, y0 - pad), min(H, y1 + pad)  # padded rows, for the gradients
        ys = (np.arange(ya, yb, dtype=np.float32) + 0.5) / H
        xs = (np.arange(W, dtype=np.float32) + 0.5) / H
        x, y = np.meshgrid(xs, ys)
        col = wash(p, x, y, aspect)
        for s, (ca_, cb_, alpha) in zip(SHAPES, p["colours"]):
            c0, c1, blur = lin(hexc(ca_)), lin(hexc(cb_)), s[4]
            d, nx, ny, along, across = petal_field(s, x, y, aspect)
            soft = max(0.9 * px, blur)
            cov = smooth(soft, -soft, d)
            crisp = 0.9 * px / soft                   # 1 in focus, small when blurred
            inner = np.maximum(-d, 0)
            c = c0 + (c1 - c0) * smooth(0.05, 0.95, along)[..., None]
            # Its light spills onto what is behind, in its own colour.
            spill = p["glow"] * np.exp(-np.maximum(d, 0) / 0.09) * (1 - cov)
            col = col + (c - col) * spill[..., None] * 0.5
            if crisp > 0.5:
                # Coloured shade cast down-right onto what is behind.
                sd = petal_field(s, x, y, aspect, (0.008, 0.016))[0]
                shade = p["shade"] * np.exp(-np.maximum(sd, 0) / 0.025) * smooth(0.04, -0.01, sd) * (1 - cov)
                col = col * (1 - shade[..., None] * (1 - c * 0.5) * 0.55)
            # Refraction: behind the glass, the wash is seen shifted near the rim.
            bend = p["lens"] * np.exp(-inner / 0.04) * crisp
            behind = col * 0.6 + wash(p, x - nx * bend, y - ny * bend, aspect) * 0.4
            # The glass body: rounded across its width, brighter towards the tip,
            # and lit from within near the root by the warm light.
            round_ = np.sqrt(np.clip(1 - across * across, 0, 1))
            body_l = p["body"] + 0.30 * along + 0.28 * round_
            tint = c * body_l[..., None]
            tint = tint + (rc - tint) * (0.35 * np.exp(-along / 0.18))[..., None]
            body = behind * (1 - alpha) + tint * alpha
            # Light: a streak along the lit side, a bright rim facing the light
            # with a warm fringe just inside it, a fainter rim opposite.
            facing = np.clip(-(nx * LIGHT[0] + ny * LIGHT[1]), 0, 1)
            streak = (np.exp(-((across + 0.42) / 0.13) ** 2) * smooth(0.10, 0.45, along)
                      * (1 - smooth(0.75, 0.97, along)) * p["streak"] * crisp)
            rim = np.exp(-inner / 0.0020) * (0.30 + 0.70 * facing) * p["rim"] * crisp
            fringe = np.exp(-((inner - 0.0045) / 0.0022) ** 2) * facing * 0.35 * crisp
            back = np.exp(-inner / 0.0035) * (1 - facing) * 0.30 * crisp
            white = np.clip(c * 0.4 + 0.65, 0, 1)
            body = body + (white - body) * np.clip(rim + back + streak, 0, 1)[..., None]
            body = body + (warm - body) * np.clip(fringe, 0, 1)[..., None] * 0.6
            # Thickness: the far edge darkens a little.
            body = body * (1 - 0.25 * np.exp(-inner / 0.014) * (1 - facing) * crisp)[..., None]
            col = col * (1 - cov[..., None]) + body * cov[..., None]
        if p["vignette"]:
            vx, vy = (x / aspect - 0.5) * 1.5, (y - 0.5) * 1.5
            col = col * (1 - p["vignette"] * np.clip(vx * vx + vy * vy - 0.3, 0, 1))[..., None]
        col = col[y0 - ya: y0 - ya + (y1 - y0)]
        s8 = srgb(col) * 255
        s8 += rng.normal(0, 0.9, s8.shape)             # grain: no banding
        out[y0:y1] = np.clip(s8 + 0.5, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    mode, W, H, path = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    Image.fromarray(render(mode, W, H)).save(path)
