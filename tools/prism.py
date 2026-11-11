#!/usr/bin/env python3
"""Memora "Prism": wide ribbons of neon-coloured glass flowing across the screen.

Colour at full strength, so the Liquid Glass of the menu bar, the Dock and the
widgets has something vivid to bend and tint. The ribbons sweep up from the
lower left in slow waves. The ones at the back are out of focus, like a photo
with a shallow depth of field; the ones in front are thick, rounded glass: lit
along a streak, bright at the rim facing the light, showing what is behind them
shifted, and casting a coloured shade. Rendered per pixel (numpy), so it is
smooth at any size.

usage: prism.py MODE WIDTH HEIGHT OUT.png      MODE: light | dark
"""
import math
import sys

import numpy as np
from PIL import Image

# Ribbons, back to front. Centre line (u = 0..1 across the screen, in screen
# heights): y = base + tilt * (u - 0.5) + amp * sin(2 pi freq u + phase).
# Then half width, and focus blur (screen heights; 0 = sharp).
SHAPES = [
    (0.22, -0.30, 0.10, 0.8, 0.5, 0.17, 0.040),   # out of focus, behind
    (0.92, -0.25, 0.09, 0.7, 2.5, 0.19, 0.040),
    (0.70, -0.60, 0.12, 0.9, 1.2, 0.090, 0.0),
    (0.40, -0.55, 0.13, 0.75, 2.6, 0.065, 0.0),
    (0.92, -0.70, 0.11, 1.0, 0.3, 0.095, 0.0),
    (0.52, -0.62, 0.10, 1.1, 3.8, 0.045, 0.0),
]
# Per mode: the wash (colour pools: x, y, radius, colour), and for each ribbon
# above its colour at the left, at the right, and its opacity.
PAL = {
    "dark": {
        "base": "#05030f",
        "pools": [(0.0, 0.0, 0.55, "#0a0636"), (1.0, 0.0, 0.5, "#2a0548"),
                  (0.0, 1.0, 0.5, "#001e4a"), (1.0, 1.0, 0.55, "#3a0326"),
                  (0.5, 0.5, 0.35, "#10052e")],
        "colours": [("#3a00ff", "#00c8ff", 0.55), ("#ff0066", "#ff8a00", 0.55),
                    ("#0047ff", "#00f0ff", 0.90), ("#b000ff", "#ff2fa8", 0.90),
                    ("#ff1f4b", "#ffd000", 0.92), ("#00ffa8", "#00b4ff", 0.88)],
        "glow": 0.40, "rim": 0.95, "streak": 0.50,
        "shade": 0.60, "lens": 0.03, "vignette": 0.35, "body": 0.60,
    },
    "light": {
        "base": "#f6f2ff",
        "pools": [(0.0, 0.0, 0.55, "#dfe6ff"), (1.0, 0.0, 0.5, "#ffdcf0"),
                  (0.0, 1.0, 0.5, "#d2f2ff"), (1.0, 1.0, 0.55, "#ffe4cc"),
                  (0.5, 0.5, 0.35, "#efe6ff")],
        "colours": [("#5a3bff", "#2fd4ff", 0.50), ("#ff2f86", "#ffa31f", 0.50),
                    ("#0a5cff", "#00e1ff", 0.92), ("#a200ff", "#ff2a9a", 0.92),
                    ("#ff2a45", "#ffc400", 0.94), ("#00e6a0", "#00a8ff", 0.90)],
        "glow": 0.28, "rim": 1.0, "streak": 0.55,
        "shade": 0.30, "lens": 0.03, "vignette": 0.0, "body": 0.55,
    },
}

LIGHT = np.array([-0.45, -0.89])        # light from above, a little to the left
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
    """The background: colour pools blended by soft weights over the base."""
    base = lin(hexc(p["base"]))
    acc = np.zeros(x.shape + (3,), np.float32) + base * 0.35
    wsum = np.full(x.shape, 0.35, np.float32)
    for px, py, r, c in p["pools"]:
        dx, dy = (x - px * aspect), (y - py)
        w = np.exp(-(dx * dx + dy * dy) / (r * r))
        acc += w[..., None] * lin(hexc(c))
        wsum += w
    return acc / wsum[..., None]


def ribbon(s, x, y, aspect, k, off=(0.0, 0.0)):
    """A ribbon: signed distance (screen heights, < 0 inside), outward normal,
    where along it a point is (0 at the left, 1 at the right) and where across
    it (-1..1, edge to edge). Its width swells and narrows as it flows."""
    base, tilt, amp, freq, phase, w0 = s[:6]
    u = (x - off[0]) / aspect
    yy = y - off[1]
    a = 2 * math.pi * freq
    yc = base + tilt * (u - 0.5) + amp * np.sin(a * u + phase)
    slope = (tilt + amp * a * np.cos(a * u + phase)) / aspect
    half = w0 * (0.70 + 0.40 * (0.5 + 0.5 * np.sin(2 * math.pi * 0.55 * u + 1.7 * k)))
    v = yy - yc
    d = (np.abs(v) - half) / np.sqrt(1 + slope * slope)
    gy, gx = np.gradient(d)
    n = np.sqrt(gx * gx + gy * gy) + 1e-9
    across = np.clip(v / half, -1, 1)
    return d, gx / n, gy / n, np.clip(u, 0, 1), across


def render(mode, W, H):
    p = PAL[mode]
    aspect = W / H
    out = np.zeros((H, W, 3), np.uint8)
    rng = np.random.default_rng(11)
    chunk, pad = 240, 2
    px = 1.0 / H
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        ya, yb = max(0, y0 - pad), min(H, y1 + pad)  # padded rows, for the gradients
        ys = (np.arange(ya, yb, dtype=np.float32) + 0.5) / H
        xs = (np.arange(W, dtype=np.float32) + 0.5) / H
        x, y = np.meshgrid(xs, ys)
        col = wash(p, x, y, aspect)
        for k, (s, (ca_, cb_, alpha)) in enumerate(zip(SHAPES, p["colours"])):
            c0, c1, blur = lin(hexc(ca_)), lin(hexc(cb_)), s[6]
            d, nx, ny, along, across = ribbon(s, x, y, aspect, k)
            soft = max(0.9 * px, blur)
            cov = smooth(soft, -soft, d)
            crisp = 0.9 * px / soft                   # 1 in focus, small when blurred
            inner = np.maximum(-d, 0)
            c = c0 + (c1 - c0) * smooth(0.0, 1.0, along)[..., None]
            # Its light spills onto what is behind, in its own colour.
            spill = p["glow"] * np.exp(-np.maximum(d, 0) / 0.08) * (1 - cov)
            col = col + (c - col) * spill[..., None] * 0.5
            if crisp > 0.5:
                # Coloured shade cast below onto what is behind.
                sd = ribbon(s, x, y, aspect, k, (0.006, 0.018))[0]
                shade = p["shade"] * np.exp(-np.maximum(sd, 0) / 0.025) * smooth(0.04, -0.01, sd) * (1 - cov)
                col = col * (1 - shade[..., None] * (1 - c * 0.5) * 0.55)
            # Refraction: behind the glass, the wash is seen shifted near the rim.
            bend = p["lens"] * np.exp(-inner / 0.035) * crisp
            behind = col * 0.6 + wash(p, x - nx * bend, y - ny * bend, aspect) * 0.4
            # The glass body: rounded across its width.
            round_ = np.sqrt(np.clip(1 - across * across, 0, 1))
            tint = c * (p["body"] + 0.45 * round_)[..., None]
            body = behind * (1 - alpha) + tint * alpha
            # Light: a streak along the upper side, a bright rim facing the light,
            # a fainter rim opposite.
            facing = np.clip(-(nx * LIGHT[0] + ny * LIGHT[1]), 0, 1)
            streak = np.exp(-((across + 0.45) / 0.14) ** 2) * p["streak"] * crisp
            streak = streak * (0.6 + 0.4 * np.sin(2 * math.pi * 1.3 * along + k))
            rim = np.exp(-inner / 0.0020) * (0.30 + 0.70 * facing) * p["rim"] * crisp
            back = np.exp(-inner / 0.0035) * (1 - facing) * 0.30 * crisp
            white = np.clip(c * 0.35 + 0.68, 0, 1)
            body = body + (white - body) * np.clip(rim + back + streak, 0, 1)[..., None]
            # Thickness: the lower edge darkens a little, in the ribbon's own colour.
            body = body * (1 - 0.30 * np.exp(-inner / 0.014) * (1 - facing) * crisp)[..., None]
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
