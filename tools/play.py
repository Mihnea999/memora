#!/usr/bin/env python3
"""Memora's playful wallpapers: soft 3D shapes in many colours, lit per pixel
(numpy), so the light stays smooth at any size.

usage: play.py NAME MODE WIDTH HEIGHT OUT.png
  NAME: sorbet  (warm: coral, tangerine, magenta, gold; melting liquid blobs)
        lagoon  (cool: teal, cobalt, violet, mint; twisting satin ribbons)
        petal   (warm and cool: a flower of translucent glass petals)
        bubbles (every colour: soft glossy spheres floating at different depths)
  MODE: light | dark

Everything is measured in screen heights (y 0..1 from the top, x 0..W/H), so the
picture is the same at any resolution. Light is from the upper left.
"""
import math
import sys

import numpy as np
from PIL import Image


def hexc(h):
    h = h.lstrip("#")
    return srgb_to_lin(np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32))


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return a + (b - a) * t[..., None]


def mesh(X, Y, pts):
    """A mesh gradient: colours pinned at points, blended with soft weights."""
    acc, wsum = 0, 0
    for x, y, s, c in pts:
        w = np.exp(-((X - x) ** 2 + (Y - y) ** 2) / (s * s)) + 1e-4
        acc = acc + w[..., None] * hexc(c)
        wsum = wsum + w
    return acc / wsum[..., None]


L = np.array([-0.45, -0.6, 0.66], dtype=np.float32)
L /= np.linalg.norm(L)


# ------------------------------------------------------------------ sorbet --
# Warm liquid: three layers of metaballs, each a pillow of colour lying on the one
# behind it, with a glossy edge and a soft contact shadow.
def sorbet(mode):
    dark = mode == "dark"
    bg = ([(0.1, 0.1, 0.7, "#1a0710"), (1.5, 0.2, 0.7, "#2a0b16"), (0.9, 1.0, 0.7, "#12050c")] if dark else
          [(0.1, 0.1, 0.7, "#fff4ea"), (1.5, 0.15, 0.7, "#ffe6dc"), (0.9, 1.0, 0.7, "#fde2d0")])
    layers = [  # balls (x, y, size), colours (a, b) across the layer, threshold
        ([(1.20, 0.05, 0.34), (1.55, 0.30, 0.30), (1.62, -0.05, 0.30), (0.95, -0.12, 0.28)],
         ("#b0124f", "#e8336e") if dark else ("#f4729b", "#f7a0b8")),
        ([(-0.05, 1.02, 0.36), (0.35, 0.92, 0.28), (0.15, 0.62, 0.22), (0.70, 1.12, 0.30)],
         ("#ff5a3c", "#ff8a3d") if dark else ("#ff7a5c", "#ffa66b")),
        ([(1.35, 0.95, 0.26), (1.05, 1.08, 0.24), (1.62, 0.70, 0.24), (1.70, 1.05, 0.3)],
         ("#ffb21f", "#ffd457") if dark else ("#ffc24d", "#ffdc7a")),
        ([(0.55, 0.35, 0.16), (0.68, 0.48, 0.12), (0.47, 0.50, 0.10)],
         ("#e0336b", "#ff7b54") if dark else ("#ff8a80", "#ffb38a")),
        ([(-0.08, 0.12, 0.22), (0.18, -0.04, 0.2)],
         ("#ff9e2c", "#ffc94a") if dark else ("#ffb870", "#ffd9a0")),
    ]

    def shade(X, Y, px):
        col = mesh(X, Y, bg)
        for balls, (ca, cb) in layers:
            F = 0
            gx = gy = 0
            for x, y, s in balls:
                e = np.exp(-((X - x) ** 2 + (Y - y) ** 2) / (s * s))
                F = F + e
                gx = gx - 2 * (X - x) / (s * s) * e
                gy = gy - 2 * (Y - y) / (s * s) * e
            T = 0.45
            g = np.sqrt(gx * gx + gy * gy) + 1e-6
            dist = (F - T) / g                     # signed distance to the edge, approx.
            cov = smooth(-0.9 * px, 0.9 * px, dist)
            # Contact shadow on what lies behind, a little down and right.
            sd = np.clip(dist - 0.012, -1, 0)
            sh = np.exp(sd / 0.035) * (1 - cov)
            col = col * (1 - sh * (0.55 if dark else 0.22))[..., None]
            # A pillow: flat on top, rounding off within ~0.06 of the edge.
            k = smooth(0, 0.14, dist)
            slope = (1 - k) * 1.6
            nx, ny = -gx / g * slope, -gy / g * slope
            nz = np.ones_like(nx)
            n = np.sqrt(nx * nx + ny * ny + 1)
            nx, ny, nz = -nx / n, -ny / n, nz / n
            t = np.clip(0.5 + 0.9 * (X - Y - 0.3) / 2.2 + 0.25 * k, 0, 1)
            c = mix(hexc(ca), hexc(cb), t)
            diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
            c = c * (0.55 + 0.55 * diff)[..., None]
            # Gloss: a soft band of light on the upper-left rim, and a faint inner glow.
            rim = np.exp(-(np.maximum(dist, 0) / 0.012)) * np.clip(-(gx + gy) / g * 0.7 + 0.2, 0, 1)
            spec = np.clip(nx * L[0] + ny * L[1], 0, 1) ** 2 * (1 - k)
            c = c + (1 - c) * np.clip(0.45 * rim + 0.5 * spec, 0, 1)[..., None]
            col = col * (1 - cov[..., None]) + c * cov[..., None]
        return col
    return shade


# ------------------------------------------------------------------ lagoon --
# Cool satin ribbons sweeping across, each twisting so its two faces show.
def lagoon(mode):
    dark = mode == "dark"
    bg = ([(0.2, 0.1, 0.8, "#040a14"), (1.4, 0.2, 0.8, "#0a0d24"), (0.8, 1.0, 0.8, "#03111a")] if dark else
          [(0.2, 0.1, 0.8, "#eef8fb"), (1.4, 0.2, 0.8, "#eceefd"), (0.8, 1.0, 0.8, "#e4f5f2")])
    # base y at x=0, tilt, width, twist freq/phase, wave, colours along x (front face), back face
    ribbons = [   # back to front
        (-0.05, 0.30, 0.07, 0.9, 0.3, 0.07, ["#5a3fd8", "#3f63e8", "#21a3d8"], "#1a1f6b") if dark else
        (-0.05, 0.30, 0.07, 0.9, 0.3, 0.07, ["#b3a3f7", "#9fb6f6", "#9ad8ee"], "#6b7fc8"),
        (0.18, 0.22, 0.14, 0.7, 2.1, 0.10, ["#0d8fb0", "#1f5fe8", "#7a4ff0"], "#0e1d5a") if dark else
        (0.18, 0.22, 0.14, 0.7, 2.1, 0.10, ["#7fd3e3", "#86a9f5", "#b59bf5"], "#5e7cc2"),
        (0.62, 0.05, 0.09, 0.8, 4.0, 0.09, ["#7a4ff0", "#2f7cf0", "#16c4c0"], "#14205e") if dark else
        (0.62, 0.05, 0.09, 0.8, 4.0, 0.09, ["#b9a2f6", "#8db5f7", "#86e0d6"], "#6a86c4"),
        (0.80, 0.14, 0.16, 0.95, 1.0, 0.08, ["#15c2a8", "#4fe0b0", "#2fa8e8"], "#0a3550") if dark else
        (0.80, 0.14, 0.16, 0.95, 1.0, 0.08, ["#86e3cf", "#aef0d0", "#92cdf3"], "#5f9ab8"),
    ]

    def shade(X, Y, px):
        col = mesh(X, Y, bg)
        x = X[0]
        for i, (y0, tilt, w0, fq, ph, amp, cols, back) in enumerate(ribbons):
            c_y = y0 + tilt * x + amp * np.sin(2 * math.pi * 0.42 * x + ph) + 0.03 * np.sin(2 * math.pi * 0.9 * x + 1.7 * i)
            w = w0 * (0.8 + 0.2 * np.sin(2 * math.pi * fq * 0.5 * x + ph))
            t = (Y - c_y[None, :]) / w[None, :]
            d = (1 - np.abs(t)) * w[None, :]           # distance inside the edge
            cov = smooth(-0.9 * px, 0.9 * px, d)
            # Soft shadow on what lies below the tube.
            below = np.maximum(Y - c_y[None, :] - w[None, :], 0)
            sh = np.exp(-below / 0.045) * (Y > c_y[None, :]) * (1 - cov)
            col = col * (1 - sh * (0.5 if dark else 0.18))[..., None]
            # Colour along the tube, turning to the second face colour towards its end.
            u = np.clip(x / 1.6, 0, 1)
            k = len(cols) - 1
            seg = np.minimum((u * k).astype(int), k - 1)
            f = u * k - seg
            ca = np.stack([hexc(c) for c in cols])
            front = ca[seg] + (ca[seg + 1] - ca[seg]) * f[:, None]
            # A tube: round across its width, lit from the upper left.
            tt = np.clip(t, -0.999, 0.999)
            ny, nz = tt, np.sqrt(1 - tt * tt)
            slope = np.gradient(c_y) / np.gradient(x)
            nx = -ny * slope[None, :] * 0.5
            diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
            base = front[None, :, :]
            shadowc = hexc(back)
            c = base * (0.35 + 0.75 * diff)[..., None] + shadowc * (0.25 * (1 - diff) * (1 - nz * 0.3))[..., None]
            # Light bouncing back into the underside, and a satin highlight.
            spec = np.exp(-((tt + 0.42) / 0.26) ** 2) * (0.38 if dark else 0.32)
            c = c + (1 - c) * spec[..., None]
            col = col * (1 - cov[..., None]) + c * cov[..., None]
        return col
    return shade


# ------------------------------------------------------------------- petal --
# A flower of translucent glass petals, warm on one side turning cool on the other.
def petal(mode):
    dark = mode == "dark"
    bg = ([(0.2, 0.1, 0.8, "#0b0716"), (1.5, 0.3, 0.8, "#120a1c"), (0.8, 1.1, 0.8, "#060a16")] if dark else
          [(0.2, 0.1, 0.8, "#fbf6fb"), (1.5, 0.3, 0.8, "#f6f1fb"), (0.8, 1.1, 0.8, "#eef4fb")])
    ring = (["#ff5e5b", "#ff8a3d", "#ffc23d", "#ff4f9a", "#c04fe8", "#6a5cf5", "#2f8ff0", "#1fc8c0", "#4fe0a0"]
            if dark else
            ["#ff7f7a", "#ffa066", "#ffcf66", "#ff7fb3", "#c77ff0", "#8a80f7", "#62a9f4", "#5fd6cf", "#7fe8b8"])
    cx, cy = 1.0, 0.52
    petals = []
    n = 9
    for layer, (R, a0, scale) in enumerate([(0.36, 0.0, 1.0), (0.22, math.pi / n, 0.7)]):
        for i in range(n):
            ang = a0 + 2 * math.pi * i / n - math.pi / 2
            petals.append((ang, R * scale + 0.0, R, 0.13 * scale + 0.04 * (1 - layer), ring[(i * 2 + layer * 4) % len(ring)], layer))

    def shade(X, Y, px):
        col = mesh(X, Y, bg)
        # A glow behind the flower.
        r2 = (X - cx) ** 2 + (Y - cy) ** 2
        glow = np.exp(-r2 / 0.12) * (0.25 if dark else 0.0)
        col = col + hexc("#7a4fd0") * glow[..., None]
        for ang, a, R, b, c, layer in petals:
            ux, uy = math.cos(ang), math.sin(ang)
            mx, my = cx + ux * a * 0.95, cy + uy * a * 0.95
            u = (X - mx) * ux + (Y - my) * uy
            v = -(X - mx) * uy + (Y - my) * ux
            q = np.sqrt((u / a) ** 2 + (v / b) ** 2)
            dist = (1 - q) * np.minimum(a, b)
            cov = smooth(-0.9 * px, 0.9 * px, dist)
            base = hexc(c)
            along = np.clip(0.5 + 0.5 * u / a, 0, 1)    # 0 at the centre, 1 at the tip
            # Glass: thin in the middle, thicker and brighter towards its rim.
            inner = smooth(0.0, 0.9, q)
            alpha = (0.55 + 0.25 * inner) * (0.85 + 0.15 * along) if dark else (0.42 + 0.22 * inner)
            pc = base * (0.75 + 0.45 * along)[..., None]
            rim = np.exp(-np.maximum(dist, 0) / 0.004) * 0.6
            lit = np.clip(-(u / a * ux + v / b * -uy) * 0.0 + 0.5 - 0.5 * ((X - mx) * L[0] + (Y - my) * L[1]) / (a + b) * 3, 0, 1)
            pc = pc + (1 - pc) * np.clip(rim * (0.5 + 0.5 * lit) + 0.25 * np.exp(-((q - 0.55) / 0.25) ** 2) * lit, 0, 1)[..., None]
            if dark:   # light passes through and adds up
                col = col * (1 - (cov * alpha * 0.55)[..., None]) + pc * (cov * alpha)[..., None]
            else:      # tinted glass over paper
                a_ = (cov * alpha)[..., None]
                col = col * (1 - a_) + (0.6 * pc + 0.4 * col * pc / np.maximum(pc.max(-1, keepdims=True), 1e-3)) * a_
        return col
    return shade


# ----------------------------------------------------------------- bubbles --
# Glossy spheres of every colour at different depths; the far ones out of focus.
def bubbles(mode):
    dark = mode == "dark"
    bg = ([(0.2, 0.1, 0.8, "#0a0a1a"), (1.5, 0.2, 0.8, "#140a20"), (0.8, 1.1, 0.8, "#05101a")] if dark else
          [(0.2, 0.1, 0.8, "#f5f3fd"), (1.5, 0.2, 0.8, "#fdf2f4"), (0.8, 1.1, 0.8, "#eef7f8")])
    P = {  # (lit, shadow side)
        "coral": ("#ff8a70", "#e0334f"), "gold": ("#ffd66b", "#f08a1f"), "magenta": ("#ff7ac4", "#c21d7a"),
        "teal": ("#5ff0dc", "#0b8fa0"), "cobalt": ("#6fa0ff", "#2440c8"), "violet": ("#b48cff", "#5a2fc0"),
        "mint": ("#a8f5c8", "#2fb88a"), "tangerine": ("#ffb15c", "#f05a1f"),
    }
    # x, y, r, colour, focus blur (0 = sharp); listed back to front.
    balls = [
        (0.18, 0.22, 0.07, "violet", 0.03), (1.38, 0.12, 0.06, "gold", 0.025), (0.86, 0.86, 0.05, "teal", 0.02),
        (1.50, 0.62, 0.08, "magenta", 0.03), (0.50, 0.08, 0.05, "mint", 0.02), (0.06, 0.66, 0.09, "cobalt", 0.03),
        (1.10, 0.30, 0.16, "cobalt", 0.0), (0.40, 0.66, 0.20, "coral", 0.0), (1.26, 0.80, 0.24, "teal", 0.0),
        (0.80, 0.42, 0.11, "gold", 0.0), (1.52, 0.30, 0.10, "violet", 0.0), (0.22, 0.38, 0.08, "magenta", 0.0),
        (0.70, 1.00, 0.13, "mint", 0.0), (0.98, 0.64, 0.06, "tangerine", 0.0),
    ]

    def shade(X, Y, px):
        col = mesh(X, Y, bg)
        for x, y, r, name, bl in balls:
            lit_c, dark_c = hexc(P[name][0]), hexc(P[name][1])
            dx, dy = (X - x) / r, (Y - y) / r
            d2 = dx * dx + dy * dy
            d = np.sqrt(d2)
            soft = max(0.9 * px / r, bl / r)
            cov = smooth(1 + soft, 1 - soft, d)
            if bl == 0:   # a soft shadow cast down-right on the ground behind
                sdx, sdy = (X - x - 0.03 * r * 4) / r, (Y - y - 0.05 * r * 4) / r
                sd = np.sqrt(sdx * sdx + sdy * sdy)
                sh = smooth(1.35, 0.6, sd) * (1 - cov) * (0.35 if dark else 0.14)
                col = col * (1 - sh[..., None])
            nz = np.sqrt(np.clip(1 - d2, 0, 1))
            nx, ny = np.clip(dx, -1, 1), np.clip(dy, -1, 1)
            diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
            if bl:   # out of focus: no hard rim, just a soft turn of colour
                diff = smooth(-1.2, 1.2, -(dx * 0.6 + dy * 0.75)) * 0.9 + 0.05
            c = mix(dark_c, lit_c, smooth(0.05, 0.95, diff))
            # Light passing through: the rim facing away glows in the lit colour.
            back = np.clip(-(nx * L[0] + ny * L[1]), 0, 1) * (1 - nz) ** 2 * (bl == 0)
            c = c + (lit_c * 1.1 - c) * np.clip(back * 1.2, 0, 1)[..., None]
            spec = np.exp(-(((dx + 0.38) ** 2 + (dy + 0.42) ** 2) / 0.05)) * (0.75 if bl == 0 else 0.25)
            c = c + (1 - c) * spec[..., None]
            if dark and bl == 0:   # a faint glow around each sphere
                glow = np.exp(-np.maximum(d - 1, 0) * 6) * (1 - cov) * 0.12
                col = col + lit_c * glow[..., None]
            a = cov * (0.75 if bl else 1.0)
            col = col * (1 - a[..., None]) + c * a[..., None]
        return col
    return shade


SCENES = {"sorbet": sorbet, "lagoon": lagoon, "petal": petal, "bubbles": bubbles}


def render(name, mode, W, H):
    shade = SCENES[name](mode)
    out = np.zeros((H, W, 3), dtype=np.uint8)
    xs = ((np.arange(W, dtype=np.float32) + 0.5) / H)
    px = 1.0 / H
    rng = np.random.default_rng(11)
    chunk = 192
    for y0 in range(0, H, chunk):
        y1 = min(H, y0 + chunk)
        ys = ((np.arange(y0, y1, dtype=np.float32) + 0.5) / H)
        X, Y = np.meshgrid(xs, ys)
        col = shade(X, Y, px)
        if mode == "dark":   # the corners settle
            vx, vy = (X / (W / H) - 0.5) * 1.6, (Y - 0.5) * 1.6
            col = col * (1 - 0.3 * np.clip(vx * vx + vy * vy - 0.3, 0, 1))[..., None]
        s = lin_to_srgb(col) * 255
        s += rng.normal(0, 1.0, s.shape)          # grain: no banding in the gradients
        out[y0:y1] = np.clip(s + 0.5, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    name, mode, W, H, path = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    Image.fromarray(render(name, mode, W, H)).save(path)
