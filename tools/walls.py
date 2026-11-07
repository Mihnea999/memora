#!/usr/bin/env python3
"""Memora wallpapers, drawn as SVG (render with rsvg-convert at 8K).

usage: walls.py NAME MODE > out.svg
  NAME: horizon | aurora | glass | dunes     MODE: light | dark

Each picture is one calm idea: few shapes, a restrained palette, smooth light.
Dark versions are deep, never pure black; light versions are airy, never pure
white, so the menu bar and Dock read well over them.
"""
import math
import sys

W, H = 3840, 2400


def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<defs>{defs}</defs>{body}</svg>')


def lin(id_, stops, x1=0, y1=0, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def rad(id_, stops, cx=0.5, cy=0.5, r=0.5):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{id_}" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


def blur(id_, sd):
    return f'<filter id="{id_}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{sd}"/></filter>'


def wave(y0, amp, phase, freq=1.0, steps=48):
    """A smooth wave across the full width, as a path of cubic segments."""
    pts = [(-200 + i * (W + 400) / steps, y0 + amp * math.sin(phase + freq * 2 * math.pi * i / steps)) for i in range(steps + 1)]
    d = f"M {pts[0][0]:.1f} {pts[0][1]:.1f}"
    for a, b in zip(pts, pts[1:]):
        mx = (a[0] + b[0]) / 2
        d += f" C {mx:.1f} {a[1]:.1f}, {mx:.1f} {b[1]:.1f}, {b[0]:.1f} {b[1]:.1f}"
    return d


# ----------------------------------------------------------------- horizon --
# A glowing horizon: the sky above, the curve of a planet below, one line of light.
def horizon(mode):
    dark = mode == "dark"
    sky = ([(0, "#05060c", 1), (0.55, "#0d1230", 1), (1, "#23306b", 1)] if dark else
           [(0, "#e9edf6", 1), (0.55, "#dbe3f3", 1), (1, "#c3d2f0", 1)])
    defs = lin("sky", sky)
    defs += rad("glow", [(0, "#7da2ff" if dark else "#ffffff", 0.75 if dark else 0.95), (0.35, "#4d6fe0" if dark else "#e8eeff", 0.35), (1, "#000000" if dark else "#ffffff", 0)], 0.5, 0.68, 0.5)
    defs += lin("ground", [(0, "#0b1022" if dark else "#f4f6fb", 1), (1, "#04050a" if dark else "#e3e8f2", 1)])
    defs += lin("rim", [(0, "#ffffff", 0), (0.5, "#ffffff", 0.95), (1, "#ffffff", 0)], 0, 0, 1, 0)
    defs += blur("b40", 40) + blur("b8", 8)
    body = f'<rect width="{W}" height="{H}" fill="url(#sky)"/>'
    body += f'<rect width="{W}" height="{H}" fill="url(#glow)"/>'
    cx, cy, r = W / 2, 1620 + 7600, 7600   # top of the planet at 2/3 of the height
    body += f'<circle cx="{cx}" cy="{cy}" r="{r + 60}" fill="none" stroke="{"#9fb8ff" if dark else "#a9c0ff"}" stroke-width="160" opacity="{0.35 if dark else 0.45}" filter="url(#b40)"/>'
    body += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#ground)"/>'
    body += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="url(#rim)" stroke-width="6" filter="url(#b8)"/>'
    body += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="url(#rim)" stroke-width="2.5"/>'
    return svg(defs, body)


# ------------------------------------------------------------------ aurora --
# Ribbons of light drifting across a deep field: silk, not stripes.
def aurora(mode):
    dark = mode == "dark"
    bg = [(0, "#070611", 1), (1, "#120d24", 1)] if dark else [(0, "#f3f1f8", 1), (1, "#e6e8f5", 1)]
    defs = lin("bg", bg, 0, 0, 1, 1)
    defs += blur("soft", 70) + blur("veil", 160)
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>'
    bands = ["#3b6cff", "#8a4dff", "#1fc8c8"] if dark else ["#7aa0ff", "#b48cff", "#6fd8d0"]
    for i, c in enumerate(bands):
        y0 = 900 + i * 360
        top = wave(y0, 260 - i * 50, 0.8 + i * 1.3, 0.9 + i * 0.15)
        defs += lin(f"a{i}", [(0, c, 0), (0.25, c, 0.85 if dark else 0.75), (0.7, c, 0.6), (1, c, 0)], 0, 0, 1, 0)
        body += f'<path d="{top} L {W + 200} {H} L -200 {H} Z" fill="url(#a{i})" opacity="{0.22 if dark else 0.18}" filter="url(#veil)"/>'
        body += f'<path d="{top}" fill="none" stroke="url(#a{i})" stroke-width="{220 - i * 40}" filter="url(#soft)"/>'
    return svg(defs, body)


# ------------------------------------------------------------------- glass --
# Three discs of tinted glass overlapping in the light.
def glass(mode):
    dark = mode == "dark"
    bg = [(0, "#0a0b11", 1), (1, "#16141e", 1)] if dark else [(0, "#f5f5f8", 1), (1, "#e4e6ee", 1)]
    defs = lin("bg", bg, 0, 0, 1, 1)
    defs += blur("sh", 90)
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>'
    discs = [(1380, 1260, 900, "#ff8a5c", "#ff4f8b"), (2460, 1080, 1000, "#4f7dff", "#7a5cff"), (2050, 1880, 620, "#2fd0c0", "#3a9cff")]
    for i, (x, y, r, c1, c2) in enumerate(discs):
        a = 0.62 if dark else 0.58
        defs += lin(f"g{i}", [(0, c1, a), (1, c2, a * 0.9)], 0, 0, 1, 1)
        defs += lin(f"e{i}", [(0, "#ffffff", 0.9 if not dark else 0.7), (0.45, "#ffffff", 0.05), (1, "#ffffff", 0.35)], 0, 0, 1, 1)
        defs += rad(f"h{i}", [(0, "#ffffff", 0.35 if not dark else 0.22), (1, "#ffffff", 0)], 0.32, 0.28, 0.5)
        body += f'<circle cx="{x + 30}" cy="{y + 60}" r="{r}" fill="#000" opacity="{0.25 if not dark else 0.5}" filter="url(#sh)"/>'
        body += f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#g{i})"/>'
        body += f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#h{i})"/>'
        body += f'<circle cx="{x}" cy="{y}" r="{r - 3}" fill="none" stroke="url(#e{i})" stroke-width="6"/>'
    return svg(defs, body)


# ------------------------------------------------------------------- dunes --
# Sand at first light (or under the moon): long soft ridges, one warm sun.
def dunes(mode):
    dark = mode == "dark"
    sky = ([(0, "#080a14", 1), (0.6, "#1b1a30", 1), (1, "#3a2a3a", 1)] if dark else
           [(0, "#f7f2ec", 1), (0.6, "#f2e2d2", 1), (1, "#ecc9ad", 1)])
    layers = ["#2e2333", "#241b2a", "#1a1420", "#110d16"] if dark else ["#e7bf9b", "#d9a783", "#c88d6b", "#b07558"]
    defs = lin("sky", sky)
    defs += rad("sun", [(0, "#fff4e2" if not dark else "#f5dcc4", 1), (0.12, "#ffe6c4" if not dark else "#d9b3a3", 0.8), (1, "#ffffff", 0)], 0.5, 0.5, 0.5)
    defs += blur("b", 3)
    body = f'<rect width="{W}" height="{H}" fill="url(#sky)"/>'
    body += f'<circle cx="2650" cy="1180" r="900" fill="url(#sun)" opacity="{0.6 if dark else 1}"/>'
    body += f'<circle cx="2650" cy="1180" r="120" fill="{"#f3d9c2" if dark else "#fff6ea"}" opacity="0.95"/>'
    for i, c in enumerate(layers):
        y0 = 1380 + i * 260
        ridge = wave(y0, 120 + i * 40, 0.6 + i * 1.7, 0.55 + i * 0.12, 24)
        defs += lin(f"d{i}", [(0, c, 1), (1, layers[min(i + 1, 3)], 1)])
        defs += lin(f"l{i}", [(0, "#ffffff", 0), (0.6, "#ffffff", 0.5 if not dark else 0.18), (1, "#ffffff", 0)], 0, 0, 1, 0)
        body += f'<path d="{ridge} L {W + 200} {H + 10} L -200 {H + 10} Z" fill="url(#d{i})"/>'
        body += f'<path d="{ridge}" fill="none" stroke="url(#l{i})" stroke-width="4" filter="url(#b)"/>'
    return svg(defs, body)


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "horizon"
    mode = sys.argv[2] if len(sys.argv) > 2 else "dark"
    print({"horizon": horizon, "aurora": aurora, "glass": glass, "dunes": dunes}[name](mode))
