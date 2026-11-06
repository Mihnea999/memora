#!/usr/bin/env python3
"""Memora wallpapers, drawn as SVG (render with rsvg-convert at 8K).

usage: walls.py NAME MODE > out.svg      NAME: ribbon | dune | prism   MODE: light | dark
Crisp shapes: every edge is sharp, depth comes from gradients and thin light
lines, not from blur, so the pictures stay clear at any resolution.
"""
import math
import random
import sys

W, H = 3840, 2400


def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<defs>{defs}</defs>{body}</svg>')


def lin(id_, stops, x1=0, y1=0, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def rad(id_, stops, cx=0.5, cy=0.5, r=0.7):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{id_}" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


# ------------------------------------------------------------------ ribbon --
# Wide glass ribbons sweeping across the screen, each lit along its top edge.
def ribbon(mode):
    dark = mode == "dark"
    bg = [(0, "#070912", 1), (1, "#141026", 1)] if dark else [(0, "#f3f5fb", 1), (1, "#dfe3f2", 1)]
    defs = lin("bg", bg, 0, 0, 1, 1)
    defs += '<filter id="sh" x="-10%" y="-10%" width="120%" height="130%"><feGaussianBlur stdDeviation="26"/></filter>'
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>'
    defs += rad("glow", [(0, "#8fa8ff" if dark else "#ffffff", 0.22 if dark else 0.7), (1, "#ffffff", 0)], 0.62, 0.28, 0.55)
    body += f'<rect width="{W}" height="{H}" fill="url(#glow)"/>'
    # Each ribbon: its top edge as two cubic curves (7 points), a thickness, colours along it.
    ribbons = [
        ([(-400, 1900), (700, 1500), (1100, 300), (2100, 420), (3100, 540), (3500, 1400), (4300, 600)], 520,
         ["#2b4bd6", "#6b8cff", "#a8bcff"] if not dark else ["#13206e", "#2f4fd6", "#6f8dff"]),
        ([(-400, 2350), (900, 2100), (1500, 1000), (2500, 1150), (3500, 1300), (3600, 1900), (4300, 1300)], 460,
         ["#7a4fe0", "#b08cff", "#e0d0ff"] if not dark else ["#2a1566", "#6a3fd6", "#a98cff"]),
        ([(-400, 1250), (500, 1150), (1300, 1700), (2200, 1800), (3100, 1900), (3500, 1500), (4300, 2300)], 300,
         ["#25a8c8", "#7fd6ea", "#d4f4fb"] if not dark else ["#0d3a52", "#1f86a8", "#68cde6"]),
    ]
    def curve(p, start=True):
        head = f"M {p[0][0]} {p[0][1]} " if start else f"L {p[0][0]} {p[0][1]} "
        return head + f"C {p[1][0]} {p[1][1]}, {p[2][0]} {p[2][1]}, {p[3][0]} {p[3][1]} C {p[4][0]} {p[4][1]}, {p[5][0]} {p[5][1]}, {p[6][0]} {p[6][1]}"
    for i, (pts, t, cols) in enumerate(ribbons):
        top = curve(pts)
        low = [(x, y + t) for x, y in pts][::-1]
        d = top + " " + curve(low, start=False) + " Z"
        defs += lin(f"r{i}", [(0, cols[0], 0.96), (0.5, cols[1], 0.94), (1, cols[2], 0.96)], 0, 1, 1, 0)
        defs += lin(f"h{i}", [(0, "#ffffff", 0), (0.5, "#ffffff", 0.85 if not dark else 0.55), (1, "#ffffff", 0.1)], 0, 0, 1, 0)
        defs += lin(f"in{i}", [(0, "#ffffff", 0.28 if not dark else 0.12), (0.35, "#ffffff", 0), (1, "#000000", 0.18 if not dark else 0.35)], 0, 0, 0, 1)
        body += f'<path d="{d}" fill="#000" opacity="{0.22 if not dark else 0.55}" filter="url(#sh)" transform="translate(0 40)"/>'
        body += f'<path d="{d}" fill="url(#r{i})"/>'
        body += f'<path d="{d}" fill="url(#in{i})"/>'
        body += f'<path d="{top}" fill="none" stroke="url(#h{i})" stroke-width="6"/>'
    return svg(defs, body)


# -------------------------------------------------------------------- dune --
# Layered hills of fine sand at dusk (dark) or morning (light).
def dune(mode):
    dark = mode == "dark"
    sky = [(0, "#0b0e1c", 1), (0.6, "#2a2240", 1), (1, "#5a3a4a", 1)] if dark else [(0, "#f6efe6", 1), (0.6, "#f0dcc8", 1), (1, "#e9c4a6", 1)]
    layers = (["#3b2a3c", "#2c2033", "#1f1829", "#151120", "#0c0a14"] if dark else
              ["#e6b993", "#d9a27c", "#c98a68", "#b37458", "#99604a"])
    defs = lin("sky", sky)
    body = f'<rect width="{W}" height="{H}" fill="url(#sky)"/>'
    sun = (2700, 760, 300)
    defs += rad("sun", [(0, "#ffe9c7" if not dark else "#f3c9a8", 1), (0.6, "#ffd7a8" if not dark else "#c98a8a", 0.5), (1, "#ffffff", 0)], 0.5, 0.5, 0.5)
    body += f'<circle cx="{sun[0]}" cy="{sun[1]}" r="{sun[2] * 2.2}" fill="url(#sun)" opacity="{0.55 if dark else 0.9}"/>'
    body += f'<circle cx="{sun[0]}" cy="{sun[1]}" r="{sun[2] * 0.55}" fill="{"#f6d2b4" if dark else "#fff3e2"}" opacity="0.95"/>'
    rnd = random.Random(7)
    for i, c in enumerate(layers):
        base = 1150 + i * 260
        pts = []
        for k in range(9):
            x = -300 + k * (W + 600) / 8
            pts.append((x, base + rnd.uniform(-170, 170) - (i == 0) * 120))
        d = f"M {pts[0][0]:.0f} {pts[0][1]:.0f}"
        for a, b in zip(pts, pts[1:]):
            mx = (a[0] + b[0]) / 2
            d += f" C {mx:.0f} {a[1]:.0f}, {mx:.0f} {b[1]:.0f}, {b[0]:.0f} {b[1]:.0f}"
        d += f" L {W + 300} {H + 50} L -300 {H + 50} Z"
        defs += lin(f"d{i}", [(0, c, 1), (1, layers[min(i + 1, len(layers) - 1)], 1)])
        body += f'<path d="{d}" fill="url(#d{i})"/>'
        ridge = d.split(" L ")[0]
        body += f'<path d="{ridge}" fill="none" stroke="#ffffff" stroke-opacity="{0.10 if dark else 0.32}" stroke-width="4"/>'
    return svg(defs, body)


# ------------------------------------------------------------------- prism --
# Rounded panes of coloured glass, overlapping; their edges catch the light.
def prism(mode):
    dark = mode == "dark"
    bg = [(0, "#0a0b10", 1), (1, "#16141f", 1)] if dark else [(0, "#f7f7fa", 1), (1, "#e7e8f0", 1)]
    defs = lin("bg", bg, 0, 0, 1, 1)
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>'
    panes = [
        (420, 380, 1500, 1500, -14, "#ff7a6b", "#ffb36b"),
        (1350, 650, 1600, 1350, 9, "#6b8cff", "#a56bff"),
        (2350, 260, 1350, 1250, -6, "#3fd1c2", "#4f9dff"),
        (900, 1350, 1250, 1000, 18, "#ffd36b", "#ff7ab8"),
        (2500, 1350, 1250, 950, -20, "#8f6bff", "#ff6bd6"),
    ]
    for i, (x, y, w, h, rot, c1, c2) in enumerate(panes):
        a = 0.55 if dark else 0.62
        defs += lin(f"p{i}", [(0, c1, a), (1, c2, a * 0.9)], 0, 0, 1, 1)
        defs += lin(f"e{i}", [(0, "#ffffff", 0.75 if dark else 0.9), (0.5, "#ffffff", 0.1), (1, "#ffffff", 0.45)], 0, 0, 1, 1)
        cx, cy = x + w / 2, y + h / 2
        body += (f'<g transform="rotate({rot} {cx} {cy})">'
                 f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="160" fill="url(#p{i})"/>'
                 f'<rect x="{x + 3}" y="{y + 3}" width="{w - 6}" height="{h - 6}" rx="157" fill="none" stroke="url(#e{i})" stroke-width="6"/>'
                 f'</g>')
    defs += rad("v", [(0, "#000000", 0), (1, "#000000", 0.35 if dark else 0.06)], 0.5, 0.5, 0.75)
    body += f'<rect width="{W}" height="{H}" fill="url(#v)"/>'
    return svg(defs, body)


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "ribbon"
    mode = sys.argv[2] if len(sys.argv) > 2 else "light"
    print({"ribbon": ribbon, "dune": dune, "prism": prism}[name](mode))
