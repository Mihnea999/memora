#!/usr/bin/env python3
"""Memora "Orbs": glossy spheres of vivid colour, with clean edges.

Made for Liquid Glass. The glass bends what is behind it along its rounded rim
and splits it a little into colours; that only shows where something crisp and
contrasting passes under the rim. So the spheres have sharp edges against a
deep background, and are placed so their edges run under the menu bar (top),
the Dock (bottom centre) and the widgets (right): there the glass visibly
curves the outline and fringes it with colour. A few out-of-focus spheres at
the back give depth. Rendered per pixel (numpy), so it is smooth at any size.

usage: orbs.py MODE WIDTH HEIGHT OUT.png      MODE: light | dark
"""
import sys

import numpy as np
from PIL import Image

# Spheres, back to front: centre (x as a fraction of the width, y of the
# height), radius (screen heights), focus blur (screen heights; 0 = sharp),
# and colour index (into the palette's sphere colours).
ORBS = [
    (0.56, 0.42, 0.30, 0.060, 0),     # soft, far behind
    (0.06, 0.88, 0.22, 0.050, 1),
    (0.18, 0.28, 0.40, 0.0, 2),       # big, crosses the menu bar
    (0.83, 0.82, 0.44, 0.0, 3),       # big, lower right
    (0.63, 0.06, 0.22, 0.0, 4),       # under the menu bar
    (0.96, 0.24, 0.17, 0.0, 5),       # top right, by the widgets
    (0.43, 0.97, 0.19, 0.0, 6),       # under the Dock
    (0.47, 0.55, 0.095, 0.0, 7),
    (0.29, 0.74, 0.075, 0.0, 8),
    (0.71, 0.40, 0.050, 0.0, 9),
]
# Each sphere colour: (lit, shaded).
PAL = {
    "dark": {
        "bg": ("#0a0820", "#04030c"), "wash": [(0.5, 0.45, 0.6, "#1a0f4a", 0.6)],
        "orbs": [("#7a3cff", "#2a0a80"), ("#ff2d8a", "#6a0838"),
                 ("#8a5cff", "#2e0fa8"), ("#ff8a1f", "#d0104e"),
                 ("#2fd8ff", "#0a38d8"), ("#ffe14a", "#ff6a00"),
                 ("#3dffb0", "#0080a8"), ("#ff4fd0", "#9a00c8"),
                 ("#4f9dff", "#1a1fd0"), ("#fff3a0", "#ffb000")],
        "spec": 0.75, "rim": 0.40, "shadow": 0.70, "vignette": 0.40,
    },
    "light": {
        "bg": ("#f4f0ff", "#e8e6f5"), "wash": [(0.5, 0.45, 0.6, "#ffffff", 0.5)],
        "orbs": [("#b08cff", "#6a3cff"), ("#ff7ab8", "#e0186a"),
                 ("#9c7bff", "#4a1fe0"), ("#ffa640", "#f0205a"),
                 ("#5fe0ff", "#1060ff"), ("#ffe45a", "#ff8a00"),
                 ("#6bffc2", "#00a0c0"), ("#ff70dc", "#b000e0"),
                 ("#7ab2ff", "#2a3bff"), ("#fff4a8", "#ffbe1a")],
        "spec": 0.85, "rim": 0.45, "shadow": 0.30, "vignette": 0.0,
    },
}

LIGHT = np.array([-0.40, -0.62, 0.68])   # from the upper left, towards the viewer
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


def render(mode, W, H):
    p = PAL[mode]
    aspect = W / H
    out = np.zeros((H, W, 3), np.uint8)
    rng = np.random.default_rng(5)
    chunk = 240
    px = 1.0 / H
    bg0, bg1 = lin(hexc(p["bg"][0])), lin(hexc(p["bg"][1]))
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        y = ((np.arange(y0, y1, dtype=np.float32) + 0.5) / H)[:, None]
        x = ((np.arange(W, dtype=np.float32) + 0.5) / H)[None, :]
        col = bg0 + (bg1 - bg0) * (y + 0 * x)[..., None]
        for wx, wy, wr, wc, wa in p["wash"]:
            g = wa * np.exp(-((x - wx * aspect) ** 2 + (y - wy) ** 2) / (wr * wr))
            col = col + (lin(hexc(wc)) - col) * g[..., None]
        for ox, oy, r, blur, ci in ORBS:
            lit, shd = lin(hexc(p["orbs"][ci][0])), lin(hexc(p["orbs"][ci][1]))
            dx, dy = x - ox * aspect, y - oy
            dist = np.sqrt(dx * dx + dy * dy)
            soft = max(0.9 * px, blur)
            crisp = 0.9 * px / soft
            # Soft shadow below and to the right, in the sphere's own dark colour.
            sdx, sdy = dx - r * 0.10, dy - r * 0.16
            sd = np.sqrt(sdx * sdx + sdy * sdy) - r
            shadow = p["shadow"] * np.exp(-np.maximum(sd, 0) / (0.05 + r * 0.15)) * smooth(r * 0.1, -r * 0.3, sd) * crisp
            col = col * (1 - shadow[..., None] * (1 - shd * 0.8))
            # Its colour glows a little on what is around it.
            glow = 0.18 * np.exp(-np.maximum(dist - r, 0) / (0.06 + r * 0.25))
            col = col + (lit - col) * glow[..., None] * 0.35
            # The sphere: shaded from its lit to its shaded colour, a soft broad
            # highlight, a crisp specular spot, and a rim of reflected light.
            q = np.clip(dist / r, 0, 1)
            nx, ny = dx / r, dy / r
            nz = np.sqrt(np.clip(1 - q * q, 0, 1))
            diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
            c = shd + (lit - shd) * (diff ** 1.3)[..., None]
            # Reflected light from below gives the shaded side some colour back.
            bounce = np.clip(ny, 0, 1) * (1 - nz) * 0.35
            c = c + (lit - c) * bounce[..., None]
            hx, hy = nx - LIGHT[0] * 0.75, ny - LIGHT[1] * 0.75
            broad = np.exp(-(hx * hx + hy * hy) / 0.10) * 0.35
            spot = np.exp(-(hx * hx + hy * hy) / 0.006) * p["spec"]
            rim = (1 - nz) ** 4 * p["rim"] * (0.5 + 0.5 * np.clip(-ny, 0, 1))
            white = np.clip(lit * 0.3 + 0.75, 0, 1)
            c = c + (white - c) * (np.clip(broad + spot + rim, 0, 1) * crisp)[..., None]
            cov = smooth(r + soft, r - soft, dist)
            col = col * (1 - cov[..., None]) + c * cov[..., None]
        if p["vignette"]:
            vx, vy = (x / aspect - 0.5) * 1.5, (y - 0.5) * 1.5
            col = col * (1 - p["vignette"] * np.clip(vx * vx + vy * vy - 0.3, 0, 1))[..., None]
        s8 = srgb(col) * 255
        s8 += rng.normal(0, 0.9, s8.shape)             # grain: no banding
        out[y0:y1] = np.clip(s8 + 0.5, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    mode, W, H, path = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    Image.fromarray(render(mode, W, H)).save(path)
