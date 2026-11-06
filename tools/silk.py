#!/usr/bin/env python3
"""Memora wallpaper: folded silk sheets, drawn as SVG (render with rsvg-convert).

usage: silk.py light|dark > wallpaper.svg
Each sheet is the area to the right of a curve; it casts a soft shadow on the
sheet behind it and has a thin bright rim along its edge.
"""
import sys

W, H = 3840, 2400

PALETTES = {
    # background, then per sheet (edge colour, far colour)
    "light": {
        "bg": ("#d9c7ad", "#7a6450"),
        "sheets": [
            ("#f3e9da", "#8f735a"),
            ("#efe6dc", "#6f5a4c"),
            ("#e9e4e6", "#6c6577"),
            ("#e6e8ee", "#8a90a3"),
        ],
        "shadow": 0.55, "sheen": 0.55, "fold": 0.22,
        "rim": 0.95,
    },
    "dark": {
        "bg": ("#26232b", "#0b0a0e"),
        "sheets": [
            ("#5b5368", "#141218"),
            ("#4d4a5e", "#0f0e13"),
            ("#3f4a63", "#0c0d12"),
            ("#4a5468", "#101217"),
        ],
        "shadow": 0.75, "sheen": 0.22, "fold": 0.35,
        "rim": 0.55,
    },
}

# Edge curves, bottom to top. Each sheet covers the area right of its curve.
CURVES = [
    "M -300 2400 C 300 1700, 900 1500, 1250 1050 S 1650 250, 1150 -100",
    "M 300 2400 C 900 1800, 1700 1450, 2250 1050 S 2700 300, 2350 -100",
    "M 1300 2400 C 1500 1900, 2300 1450, 3000 1050 S 3900 200, 4100 -100",
    "M 2400 2400 C 2600 1900, 3200 1500, 3600 1100 S 4100 500, 4200 300",
]


def sheet_path(curve):
    return f"{curve} L {W + 400} -100 L {W + 400} {H + 100} Z"


def main():
    p = PALETTES[sys.argv[1] if len(sys.argv) > 1 else "light"]
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', "<defs>"]
    out.append(f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
               f'<stop offset="0" stop-color="{p["bg"][0]}"/><stop offset="1" stop-color="{p["bg"][1]}"/></linearGradient>')
    for i, (edge, far) in enumerate(p["sheets"]):
        # Light at the rim, falling into shade away from it (towards lower right).
        out.append(f'<linearGradient id="s{i}" x1="0.05" y1="0.1" x2="0.55" y2="0.75">'
                   f'<stop offset="0" stop-color="{edge}"/><stop offset="0.45" stop-color="{far}"/>'
                   f'<stop offset="1" stop-color="{edge}" stop-opacity="0.9"/></linearGradient>')
    out.append('<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="70"/></filter>')
    out.append('<filter id="glow" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="14"/></filter>')
    out.append('<filter id="soft" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="2.2"/></filter>')
    out.append('<filter id="silk" x="0" y="0" width="100%" height="100%"><feGaussianBlur stdDeviation="28"/></filter>')
    out.append('<filter id="sheen" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="90"/></filter>')
    for i, curve in enumerate(CURVES):
        out.append(f'<clipPath id="c{i}"><path d="{sheet_path(curve)}"/></clipPath>')
    out.append("</defs>")
    out.append(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>')
    for i, curve in enumerate(CURVES):
        d = sheet_path(curve)
        out.append(f'<path d="{d}" fill="#000" opacity="{p["shadow"]}" filter="url(#shadow)" transform="translate(-40 30)"/>')
        out.append(f'<path d="{d}" fill="url(#s{i})" filter="url(#silk)"/>')
        out.append(f'<path d="{d}" fill="url(#s{i})" opacity="0.85"/>')
        # Sheen just inside the rim, and the fold's shade further in.
        out.append(f'<g clip-path="url(#c{i})">'
                   f'<path d="{curve}" fill="none" stroke="#fff" stroke-width="260" opacity="{p["sheen"]}" filter="url(#sheen)"/>'
                   f'<path d="{curve}" fill="none" stroke="#000" stroke-width="500" opacity="{p["fold"]}" filter="url(#sheen)" transform="translate(520 120)"/>'
                   '</g>')
        out.append(f'<path d="{curve}" fill="none" stroke="#fff" stroke-width="40" opacity="{p["rim"] * 0.35}" filter="url(#glow)"/>')
        out.append(f'<path d="{curve}" fill="none" stroke="#fff" stroke-width="7" opacity="{p["rim"]}" filter="url(#soft)"/>')
    out.append("</svg>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
