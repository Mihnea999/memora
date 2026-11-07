#!/usr/bin/env python3
"""Memora "Ember" and "Tide": layered sheets of colour folding across the screen,
lit like satin. Rendered per pixel (numpy), so the light is smooth at any size.

usage: flow.py NAME MODE WIDTH HEIGHT OUT.png
  NAME: ember (warm: apricot, coral, rose) | tide (cool: teal, blue, indigo)
  MODE: light | dark
"""
import math
import sys

import numpy as np
from PIL import Image

# Palettes: background top/bottom, then sheets from the back to the front.
# Each sheet is (left colour, right colour).
PAL = {
    ("ember", "dark"): {
        "bg": ("#0d0608", "#1e0b10"),
        "sheets": [("#4a0f22", "#7a1a2e"), ("#a3203a", "#d93c3c"), ("#e8553a", "#ff7e45"),
                   ("#ff8a4c", "#ffb07a")],
        "glow": ("#d81b60", 0.12), "rim": 0.7, "ao": 0.6, "shade": "#1a0408",
    },
    ("ember", "light"): {
        "bg": ("#fff3ea", "#fcdccb"),
        "sheets": [("#f9bea2", "#f5a088"), ("#f2806e", "#ea5e60"), ("#f0743f", "#f79455"),
                   ("#fab088", "#fdcdaa")],
        "glow": ("#ffffff", 0.35), "rim": 0.65, "ao": 0.4, "shade": "#d9826a",
    },
    ("tide", "dark"): {
        "bg": ("#04070d", "#08101d"),
        "sheets": [("#0e2150", "#163a80"), ("#1c4fb0", "#2f74e0"), ("#1f8fd0", "#2fb4e0"),
                   ("#4cc9d8", "#86e0e0")],
        "glow": ("#5b3dd8", 0.12), "rim": 0.6, "ao": 0.6, "shade": "#020610",
    },
    ("tide", "light"): {
        "bg": ("#f4f8fd", "#e6eff9"),
        "sheets": [("#c3d6f5", "#a8c4f0"), ("#7ea6ec", "#5e8ee6"), ("#4fa6e0", "#6cc0e6"),
                   ("#a2dceb", "#c6ecf2")],
        "glow": ("#ffffff", 0.35), "rim": 0.6, "ao": 0.4, "shade": "#7fa3d6",
    },
}


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def edge(k, u, n):
    """Top edge of sheet k (fraction of the height) at horizontal position u (0..1)."""
    f = k / max(1, n - 1)
    base = 0.26 + 0.50 * f
    tilt = -0.55 + 0.25 * f          # sweeps up to the right
    w = (0.11 - 0.03 * f) * np.sin(2 * math.pi * (0.55 + 0.12 * f) * u + 1.1 + 2.0 * k)
    w += 0.03 * np.sin(2 * math.pi * (1.2 + 0.15 * k) * u + 2.4 * k + 0.4)
    return base + tilt * (u - 0.5) + w


def render(name, mode, W, H):
    p = PAL[(name, mode)]
    dark = mode == "dark"
    out = np.zeros((H, W, 3), dtype=np.uint8)
    u = (np.arange(W, dtype=np.float32) + 0.5) / W
    n = len(p["sheets"])
    edges = [edge(k, u, n).astype(np.float32) for k in range(n)]
    bg0, bg1 = srgb_to_lin(hexc(p["bg"][0])), srgb_to_lin(hexc(p["bg"][1]))
    sheets = [(srgb_to_lin(hexc(a)), srgb_to_lin(hexc(b))) for a, b in p["sheets"]]
    glow_c, glow_a = srgb_to_lin(hexc(p["glow"][0])), p["glow"][1]
    # Shadows take the colour of the light around them, never grey.
    shade_c = srgb_to_lin(hexc(p.get("shade", "#000000")))
    px = 1.0 / H                       # one pixel, in height fractions
    rng = np.random.default_rng(7)
    chunk = 256
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        v = ((np.arange(y0, y1, dtype=np.float32) + 0.5) / H)[:, None]
        tv = v + 0 * u[None, :]
        col = bg0 + (bg1 - bg0) * tv[..., None]
        for k in range(n):
            e = edges[k][None, :]
            d = v - e                                  # > 0 inside the sheet
            cov = smooth(-0.8 * px, 0.8 * px, d)       # antialiased edge
            a, b = sheets[k]
            # Colour runs along the sheet, a little brighter where it faces the light.
            t = np.clip(u[None, :] * 0.85 + 0.1 * np.sin(3.1 * v + k), 0, 1)
            c = a + (b - a) * t[..., None]
            # Satin: a lit rim where the sheet curls over, the surface turning
            # away just below it, and a long soft sheen running along the fold.
            dd = np.maximum(d, 0)
            lit = np.clip(c * 1.6 + 0.08, 0, 1)
            rim = np.exp(-dd / 0.0022) * p["rim"]
            curl = 1 - 0.30 * np.exp(-((dd - 0.028) / 0.026) ** 2)
            sheen_at = 0.07 + 0.035 * np.sin(2 * math.pi * 0.8 * u[None, :] + k)
            sheen = np.exp(-((dd - sheen_at) / 0.045) ** 2) * (0.22 if dark else 0.16)
            body = 1 - (0.25 if dark else 0.08) * smooth(0.0, 0.45, dd)
            c = c * (curl * body)[..., None]
            c = c + (lit - c) * np.clip(rim + sheen, 0, 1)[..., None]
            # Ambient occlusion on the sheet just above this one's edge.
            ao = p["ao"] * np.exp(-np.maximum(-d, 0) / 0.035) * (1 - cov)
            col = col * (1 - ao[..., None] * (1 - shade_c))
            col = col * (1 - cov[..., None]) + c * cov[..., None]
        # One soft light, upper right.
        gx, gy = (u[None, :] - (0.8 if dark else 0.15)) * (W / H), v - (0.05 if dark else 0.1)
        g = np.exp(-(gx * gx + gy * gy) / 0.18) * glow_a
        col = col + (glow_c - col) * g[..., None] * (0.6 if dark else 1)
        # Vignette in the dark, so the corners settle.
        if dark:
            vx, vy = (u[None, :] - 0.5) * 1.6, (v - 0.45) * 1.6
            col = col * (1 - 0.35 * np.clip(vx * vx + vy * vy - 0.25, 0, 1))[..., None]
        s = lin_to_srgb(col) * 255
        s += rng.normal(0, 0.9, s.shape)               # grain: no banding in gradients
        out[y0:y1] = np.clip(s + 0.5, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    name, mode, W, H, path = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    Image.fromarray(render(name, mode, W, H)).save(path)
