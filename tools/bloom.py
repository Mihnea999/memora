#!/usr/bin/env python3
"""Memora "Bloom": big petals of coloured glass over a vivid wash of colour.

Bright, saturated colour everywhere, so the Liquid Glass of the menu bar, the
Dock and the widgets has something to bend and tint. Each petal is a pane of
tinted glass: it shows what is behind it shifted a little (refraction), lights
up along the rim that faces the light, and leaves a coloured shade on what is
behind it. Rendered per pixel (numpy), so it is smooth at any size.

usage: bloom.py MODE WIDTH HEIGHT OUT.png      MODE: light | dark
"""
import math
import sys

import numpy as np
from PIL import Image

# The wash: colour pools (x, y in screen fractions, radius, colour), blended
# smoothly into one another. Then the petals, drawn back to front, all opening
# from one point just below the screen: (angle in degrees, 0 = right, -90 = up;
# length and half width in screen heights; colour at the base, colour at the tip;
# opacity).
ROOT = (0.40, 1.12)
PAL = {
    "dark": {
        "base": "#090619",
        "pools": [(0.0, 0.0, 0.6, "#120a3d"), (1.0, 0.0, 0.55, "#2a0a55"),
                  (0.1, 1.0, 0.55, "#071a5a"), (0.95, 1.0, 0.6, "#4a0a35"),
                  (0.45, 0.85, 0.35, "#2a0a58")],
        "petals": [
            (-158, 1.05, 0.15, "#0b3fd6", "#17c6ff", 0.88),
            (-36, 1.30, 0.16, "#ff3b1f", "#ffb02e", 0.90),
            (-128, 1.20, 0.17, "#2a3bff", "#7d6bff", 0.86),
            (-60, 1.25, 0.17, "#d4127a", "#ff6a4a", 0.88),
            (-96, 1.18, 0.16, "#6a1bff", "#ff3fae", 0.86),
        ],
        "body": 0.70, "glow": 0.30, "rim": 0.9, "sheen": 0.32, "shade": 0.55, "lens": 0.03, "vignette": 0.40,
    },
    "light": {
        "base": "#f4eefa",
        "pools": [(0.0, 0.0, 0.6, "#dfe4ff"), (1.0, 0.0, 0.55, "#ffdcec"),
                  (0.1, 1.0, 0.55, "#cfe6ff"), (0.95, 1.0, 0.6, "#ffe0c6"),
                  (0.45, 0.85, 0.35, "#ecdcff")],
        "petals": [
            (-158, 1.05, 0.15, "#2563ff", "#2fc8ff", 0.90),
            (-36, 1.30, 0.16, "#ff4a1c", "#ffb81f", 0.92),
            (-128, 1.20, 0.17, "#3f4dff", "#8a72ff", 0.90),
            (-60, 1.25, 0.17, "#ec1c80", "#ff7046", 0.90),
            (-96, 1.18, 0.16, "#7c2cff", "#ff3fae", 0.90),
        ],
        "body": 0.52, "glow": 0.22, "rim": 1.0, "sheen": 0.45, "shade": 0.28, "lens": 0.03, "vignette": 0.0,
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


def petal_field(pt, x, y, aspect, off=(0.0, 0.0)):
    """Signed distance (screen heights, < 0 inside) and outward normal of a petal:
    narrow at the root, widest two thirds out, rounded at the tip, slightly bent.
    Also returns how far along it a point is (0 at the root, 1 at the tip)."""
    ang, length, b = math.radians(pt[0]), pt[1], pt[2]
    ca, sa = math.cos(ang), math.sin(ang)
    dx, dy = x - (ROOT[0] * aspect + off[0]), y - (ROOT[1] + off[1])
    u = dx * ca + dy * sa              # along the petal, from the root
    v = -dx * sa + dy * ca             # across it
    t = np.clip(u / length, 0, 1)
    v = v - 0.10 * length * t * t      # a gentle bend
    # Width profile: sin-like swell, full round tip.
    half = b * np.sqrt(np.clip(np.sin(math.pi * np.clip(t, 0, 1) ** 0.75), 0, 1))
    d = np.abs(v) - half
    d = np.where(u > length, np.hypot(u - length, v), d)
    d = np.where(u < 0, np.hypot(u, v) + 0.0, d)
    gy, gx = np.gradient(d)
    n = np.sqrt(gx * gx + gy * gy) + 1e-9
    return d, gx / n, gy / n, t, v / max(b, 1e-6)


def render(mode, W, H):
    p = PAL[mode]
    dark = mode == "dark"
    aspect = W / H
    out = np.zeros((H, W, 3), np.uint8)
    rng = np.random.default_rng(11)
    chunk = 240
    pad = 2
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        ya, yb = max(0, y0 - pad), min(H, y1 + pad)  # padded rows, for the gradients
        ys = (np.arange(ya, yb, dtype=np.float32) + 0.5) / H
        xs = (np.arange(W, dtype=np.float32) + 0.5) / H
        x, y = np.meshgrid(xs, ys)
        col = wash(p, x, y, aspect)
        px = 1.0 / H
        for pt in p["petals"]:
            c0, c1, alpha = lin(hexc(pt[3])), lin(hexc(pt[4])), pt[5]
            d, nx, ny, along, across = petal_field(pt, x, y, aspect)
            cov = smooth(0.9 * px, -0.9 * px, d)
            inner = np.maximum(-d, 0)
            c = c0 + (c1 - c0) * smooth(0.05, 0.95, along)[..., None]
            # Its light spills onto what is behind, in its own colour.
            spill = p["glow"] * np.exp(-np.maximum(d, 0) / 0.09) * (1 - cov)
            col = col + (c - col) * spill[..., None] * 0.5
            # Coloured shade cast down-right onto what is behind.
            sd = petal_field(pt, x, y, aspect, (0.008, 0.016))[0]
            shade = p["shade"] * np.exp(-np.maximum(sd, 0) / 0.025) * smooth(0.04, -0.01, sd) * (1 - cov)
            col = col * (1 - shade[..., None] * (1 - c * 0.5) * 0.55)
            # Refraction: behind the glass the wash is seen shifted near the rim,
            # where the glass bends.
            bend = p["lens"] * np.exp(-inner / 0.04)
            behind = wash(p, x - nx * bend, y - ny * bend, aspect)
            behind = col * 0.6 + behind * 0.4
            # The glass body: tinted, brighter towards its middle and its tip.
            body_l = p["body"] + 0.35 * along + 0.20 * (1 - np.clip(np.abs(across), 0, 1))
            tint = c * body_l[..., None]
            body = behind * (1 - alpha) + tint * alpha
            # Light: a bright rim on the side facing the light, a fainter one opposite,
            # a soft sheen just inside the lit edge.
            facing = np.clip(-(nx * LIGHT[0] + ny * LIGHT[1]), 0, 1)
            rim = np.exp(-inner / 0.0022) * (0.30 + 0.70 * facing) * p["rim"]
            back = np.exp(-inner / 0.0035) * (1 - facing) * 0.30
            sheen = np.exp(-((inner - 0.020) / 0.016) ** 2) * facing * p["sheen"]
            lit = np.clip(c * 0.45 + 0.62, 0, 1)
            body = body + (lit - body) * np.clip(rim + back + sheen, 0, 1)[..., None]
            # Thickness: the far edge darkens a little.
            body = body * (1 - 0.22 * np.exp(-inner / 0.014) * (1 - facing))[..., None]
            col = col * (1 - cov[..., None]) + body * cov[..., None]
        if p["vignette"]:
            vx, vy = (x / aspect - 0.5) * 1.5, (y - 0.5) * 1.5
            col = col * (1 - p["vignette"] * np.clip(vx * vx + vy * vy - 0.3, 0, 1))[..., None]
        col = col[y0 - ya: y0 - ya + (y1 - y0)]
        s = srgb(col) * 255
        s += rng.normal(0, 0.9, s.shape)             # grain: no banding
        out[y0:y1] = np.clip(s + 0.5, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    mode, W, H, path = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    Image.fromarray(render(mode, W, H)).save(path)
