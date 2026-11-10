#!/usr/bin/env python3
"""Memora icon theme: app and place icons on one squircle grid, written as SVG.

usage: icons.py OUTDIR   (writes OUTDIR/tile.svg and OUTDIR/Memora/{index.theme,src/apps,src/places})
Every icon shares the canvas (1024), body (824, continuous-corner squircle),
light from above, a soft drop shadow and a hairline rim.
"""
import math
import os
import sys

C = 1024
B = 824           # body size
O = (C - B) / 2   # body offset


def squircle(x=O, y=O, s=B, n=5.0, steps=240):
    pts = []
    r = s / 2
    cx, cy = x + r, y + r
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        px = cx + r * math.copysign(abs(ct) ** (2 / n), ct)
        py = cy + r * math.copysign(abs(st) ** (2 / n), st)
        pts.append(f"{px:.1f},{py:.1f}")
    return "M" + " L".join(pts) + " Z"


BODY = squircle()


def icon(name, defs, body_fill, art, rim="#ffffff", rim_op=0.35):
    """body_fill: a fill reference; art: SVG drawn clipped to the body."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
<defs>
  <clipPath id="body"><path d="{BODY}"/></clipPath>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="150%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="18"/><feOffset dy="14"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="8"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.28"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.28"/>
    <stop offset="0.45" stop-color="#fff" stop-opacity="0.04"/>
    <stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  {defs}
</defs>
<g filter="url(#drop)">
  <path d="{BODY}" fill="{body_fill}"/>
  <g clip-path="url(#body)">
    {art}
    <rect x="0" y="0" width="{C}" height="{C * 0.55}" fill="url(#gloss)"/>
  </g>
  <path d="{BODY}" fill="none" stroke="{rim}" stroke-opacity="{rim_op}" stroke-width="3"/>
</g>
</svg>
'''


def lg(id_, c1, c2, x1=0, y1=0, x2=0, y2=1):
    return f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>'


def folder_glyph(fill_back="#cfe8ff", fill_front="url(#ff)", mark=""):
    # A folder sitting in the body, front panel slightly lighter.
    return f'''
    <path d="M232 330 q0 -34 34 -34 h170 q22 0 36 18 l30 38 h256 q34 0 34 34 v330 q0 34 -34 34 h-492 q-34 0 -34 -34 Z" fill="{fill_back}"/>
    <path d="M232 418 q0 -30 30 -30 h500 q30 0 30 30 v290 q0 34 -34 34 h-492 q-34 0 -34 -34 Z" fill="{fill_front}" filter="url(#soft)"/>
    {mark}'''


ICONS = {}

# Files: a blue folder on a blue field.
ICONS["apps/org.gnome.Nautilus"] = icon(
    "files", lg("bg", "#6cc4ff", "#1468e8") + lg("ff", "#ffffff", "#dbeeff"), "url(#bg)",
    folder_glyph("#a9d6ff", "url(#ff)",
                 '<rect x="420" y="520" width="184" height="22" rx="11" fill="#5aa6f2"/>'))

ICONS["apps/memora-files"] = ICONS["apps/org.gnome.Nautilus"]

# Notes: a cream page with ruled lines and a golden header, a pencil across it.
ICONS["apps/memora-notes"] = icon(
    "notes", lg("bg", "#fffdf6", "#f1ead8") + lg("band", "#ffd25e", "#f5b72e"), "url(#bg)",
    '''<rect x="100" y="100" width="824" height="210" fill="url(#band)"/>
    <rect x="100" y="300" width="824" height="14" fill="#000" fill-opacity="0.06"/>
    <g stroke="#e3dccb" stroke-width="12" stroke-linecap="round"><path d="M250 430 h524 M250 530 h524 M250 630 h524 M250 730 h360"/></g>
    <g filter="url(#soft)" transform="rotate(-38 640 640)">
      <rect x="610" y="380" width="64" height="380" rx="10" fill="#4d8dff"/>
      <path d="M610 760 h64 l-32 70 Z" fill="#f3d3a6"/><path d="M632 808 h20 l-10 22 Z" fill="#3a3a3f"/>
      <rect x="610" y="380" width="64" height="44" rx="10" fill="#ff7a8a"/>
    </g>''', rim="#000000", rim_op=0.07)

# Calendar: a white page with a red band and two rings, the days in a grid,
# one of them circled in red.
def _days():
    out = []
    for r in range(4):
        for c in range(5):
            x, y = 262 + c * 125, 450 + r * 105
            if (r, c) == (2, 2):
                out.append(f'<circle cx="{x}" cy="{y}" r="44" fill="#ff3b30"/><circle cx="{x}" cy="{y}" r="15" fill="#ffffff"/>')
            else:
                out.append(f'<circle cx="{x}" cy="{y}" r="17" fill="#{"c9cbd2" if r < 3 or c < 3 else "e4e6eb"}"/>')
    return "".join(out)


ICONS["apps/memora-calendar"] = icon(
    "calendar", lg("bg", "#ffffff", "#eceef2") + lg("band", "#ff6259", "#e8312a"), "url(#bg)",
    f'''<rect x="100" y="100" width="824" height="230" fill="url(#band)"/>
    <rect x="100" y="320" width="824" height="12" fill="#000" fill-opacity="0.08"/>
    <g fill="#ffffff" fill-opacity="0.95"><rect x="300" y="190" width="424" height="40" rx="20"/></g>
    <g filter="url(#soft)"><rect x="318" y="70" width="44" height="150" rx="22" fill="#d9dbe1"/><rect x="662" y="70" width="44" height="150" rx="22" fill="#d9dbe1"/></g>
    {_days()}''', rim="#000000", rim_op=0.07)

# App Store: a white "A" built from three strokes, on a vivid blue.
ICONS["apps/memora-store"] = icon(
    "store", lg("bg", "#3fb8ff", "#1f5ef0"), "url(#bg)",
    '''<g filter="url(#soft)" stroke="#ffffff" stroke-width="64" stroke-linecap="round" fill="none">
      <path d="M512 250 L330 640"/><path d="M512 250 L694 640"/><path d="M300 560 L724 560"/>
    </g>''')

# Launchpad: nine coloured tiles on graphite.
tiles = ["#ff6b6b", "#ffb347", "#ffd84d", "#5fd38a", "#3fc3c9", "#4d8dff", "#8f6bff", "#e86bd8", "#b8bcc6"]
tile_svg = "".join(
    f'<rect x="{262 + (i % 3) * 180}" y="{262 + (i // 3) * 180}" width="140" height="140" rx="38" fill="{c}"/>'
    for i, c in enumerate(tiles))
ICONS["apps/memora-launchpad"] = icon("launchpad", lg("bg", "#5b5f6b", "#23252c"), "url(#bg)",
                                       f'<g filter="url(#soft)">{tile_svg}</g>')

# Browser: a white globe on deep sea blue.
ICONS["apps/chromium"] = icon(
    "browser", lg("bg", "#38d1e8", "#1652d9") + lg("gl", "#ffffff", "#e2f2ff"), "url(#bg)",
    '''<g filter="url(#soft)" fill="none" stroke="url(#gl)" stroke-width="30" stroke-linecap="round">
      <circle cx="512" cy="512" r="250"/>
      <ellipse cx="512" cy="512" rx="105" ry="250"/>
      <path d="M270 430 h484 M270 594 h484"/>
    </g>''')

# Terminal: a prompt on near-black glass.
ICONS["apps/org.gnome.Ptyxis"] = icon(
    "terminal", lg("bg", "#3a3d45", "#101114"), "url(#bg)",
    '''<rect x="120" y="120" width="784" height="70" fill="#ffffff" fill-opacity="0.06"/>
    <g filter="url(#soft)" stroke="#f2f4f7" stroke-width="44" stroke-linecap="round" stroke-linejoin="round" fill="none">
      <path d="M300 400 l120 112 l-120 112"/>
      <path d="M490 640 h230" stroke="#7ee0a3"/>
    </g>''', rim_op=0.18)
ICONS["apps/kitty"] = ICONS["apps/org.gnome.Ptyxis"]
ICONS["apps/com.mitchellh.ghostty"] = ICONS["apps/org.gnome.Ptyxis"]

# Memora AI: a white spark on a dusk gradient.
ICONS["apps/memora-ai"] = icon(
    "ai", lg("bg", "#7b5cff", "#ff7a59", 0, 0, 1, 1) + '<radialGradient id="glow" cx="0.3" cy="0.25" r="0.8"><stop offset="0" stop-color="#ffffff" stop-opacity="0.35"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>',
    "url(#bg)",
    '''<rect width="1024" height="1024" fill="url(#glow)"/>
    <path filter="url(#soft)" fill="#ffffff" d="M512 238 C532 420 604 492 786 512 C604 532 532 604 512 786 C492 604 420 532 238 512 C420 492 492 420 512 238 Z"/>
    <path fill="#ffffff" fill-opacity="0.85" d="M716 262 C722 316 742 336 796 342 C742 348 722 368 716 422 C710 368 690 348 636 342 C690 336 710 316 716 262 Z"/>''')

# Text Editor: a sheet of paper with an amber title bar.
ICONS["apps/org.gnome.TextEditor"] = icon(
    "editor", lg("bg", "#ffffff", "#e9ebef"), "url(#bg)",
    '''<rect x="100" y="100" width="824" height="170" fill="#ffbe3c"/>
    <rect x="100" y="250" width="824" height="22" fill="#e9a22b"/>
    <g stroke="#c9ccd3" stroke-width="20" stroke-linecap="round">
      <path d="M260 380 h504 M260 470 h504 M260 560 h504 M260 650 h340"/>
    </g>''', rim="#000000", rim_op=0.08)

# Calculator: keys on graphite, one amber operator.
keys = ""
for r in range(4):
    for c in range(3):
        keys += f'<circle cx="{318 + c * 130}" cy="{430 + r * 118}" r="46" fill="#6d717c"/>'
for r in range(4):
    keys += f'<circle cx="{708}" cy="{430 + r * 118}" r="46" fill="#ff9f2e"/>'
ICONS["apps/org.gnome.Calculator"] = icon(
    "calc", lg("bg", "#4a4d56", "#1d1e23"), "url(#bg)",
    f'''<rect x="250" y="220" width="524" height="120" rx="28" fill="#9fe3b6" fill-opacity="0.9"/>
    <rect x="560" y="262" width="170" height="36" rx="10" fill="#1f5135" fill-opacity="0.75"/>
    <g filter="url(#soft)">{keys}</g>''', rim_op=0.16)

# Photos: a landscape on a sky gradient.
ICONS["apps/org.gnome.Loupe"] = icon(
    "photos", lg("bg", "#8fd3ff", "#ffd1a8"), "url(#bg)",
    '''<circle cx="690" cy="330" r="86" fill="#fff6d6"/>
    <path d="M100 760 L380 450 L560 640 L670 530 L924 790 V924 H100 Z" fill="#3c9b6e"/>
    <path d="M100 820 L330 600 L520 790 L640 690 L924 900 V924 H100 Z" fill="#2c7a55"/>''')

ICONS["apps/memora-photos"] = ICONS["apps/org.gnome.Loupe"]

# Documents: a page with a red band and folded corner.
ICONS["apps/org.gnome.Papers"] = icon(
    "docs", lg("bg", "#ff6b5f", "#d62f45"), "url(#bg)",
    '''<g filter="url(#soft)">
      <path d="M300 220 h300 l124 124 v460 q0 24 -24 24 h-400 q-24 0 -24 -24 v-560 q0 -24 24 -24 Z" fill="#ffffff"/>
      <path d="M600 220 v100 q0 24 24 24 h100 Z" fill="#ffd2cc"/>
      <g stroke="#e0e2e8" stroke-width="22" stroke-linecap="round"><path d="M360 470 h300 M360 550 h300 M360 630 h220"/></g>
    </g>''')

# Player: one clean white play mark on a coral-to-magenta body. The triangle is
# equilateral with evenly rounded corners, nudged right so it looks centred.
def rounded_triangle(cx, cy, r, rad):
    import math as m
    pts = [(cx + r * m.cos(a), cy + r * m.sin(a)) for a in (0, 2 * m.pi / 3, 4 * m.pi / 3)]
    d = ""
    for k in range(3):
        p0, p1, p2 = pts[k - 1], pts[k], pts[(k + 1) % 3]
        def toward(a, b, t):
            L = m.hypot(b[0] - a[0], b[1] - a[1]); return (a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L)
        a = toward(p1, p0, rad); b = toward(p1, p2, rad)
        d += ("M" if k == 0 else "L") + f"{a[0]:.1f} {a[1]:.1f} Q{p1[0]:.1f} {p1[1]:.1f} {b[0]:.1f} {b[1]:.1f} "
    return d + "Z"


ICONS["apps/memora-player"] = icon(
    "player", lg("bg", "#ff7a5c", "#d92e7a", 0.2, 0, 0.8, 1)
    + '<radialGradient id="lift" cx="0.5" cy="0.18" r="0.75"><stop offset="0" stop-color="#fff" stop-opacity="0.22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>',
    "url(#bg)",
    f'''<rect width="1024" height="1024" fill="url(#lift)"/>
    <path filter="url(#soft)" fill="#ffffff" d="{rounded_triangle(536, 512, 228, 58)}"/>''', rim_op=0.22)
ICONS["apps/mpv"] = ICONS["apps/memora-player"]

# Settings: a machined gear on silver.
teeth = "".join(
    f'<rect x="482" y="196" width="60" height="110" rx="18" fill="url(#gear)" transform="rotate({a} 512 512)"/>'
    for a in range(0, 360, 30))
ICONS["apps/memora-settings"] = icon(
    "settings", lg("bg", "#c9ccd3", "#7f838d") + lg("gear", "#f6f7f9", "#b9bcc4"), "url(#bg)",
    f'''<g filter="url(#soft)">{teeth}
      <circle cx="512" cy="512" r="232" fill="url(#gear)"/>
      <circle cx="512" cy="512" r="150" fill="#8a8e98"/>
      <circle cx="512" cy="512" r="96" fill="url(#gear)"/></g>''', rim_op=0.4)

# System monitor: a pulse on dark.
ICONS["apps/memora-activity"] = icon(
    "monitor", lg("bg", "#30333b", "#0f1013"), "url(#bg)",
    '''<g stroke="#ffffff" stroke-opacity="0.08" stroke-width="6"><path d="M100 400 h824 M100 560 h824 M100 720 h824"/></g>
    <path filter="url(#soft)" d="M200 600 h150 l70 -200 l100 340 l90 -260 l60 120 h154" fill="none" stroke="#5fe0a0" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/>''',
    rim_op=0.16)


# ---- places: folders as on the desktop, plus Trash ---------------------------
def place(glyph_path, extra_defs=""):
    """Folder icon (no squircle): back panel, front panel and an embossed glyph."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
<defs>
  {lg("back", "#64b2f5", "#3d8fe6")}{lg("front", "#9fd3ff", "#6db8fb")}
  <filter id="drop" x="-20%" y="-20%" width="140%" height="150%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="10"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.25"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>{extra_defs}
</defs>
<g filter="url(#drop)">
  <path d="M110 250 q0 -46 46 -46 h232 q30 0 50 24 l42 50 h388 q46 0 46 46 v460 q0 46 -46 46 h-712 q-46 0 -46 -46 Z" fill="url(#back)"/>
  <path d="M110 370 q0 -40 40 -40 h724 q40 0 40 40 v420 q0 46 -46 46 h-712 q-46 0 -46 -46 Z" fill="url(#front)"/>
  <path d="M150 336 h724" stroke="#ffffff" stroke-opacity="0.55" stroke-width="6"/>
  <g fill="#3d8fe6" fill-opacity="0.75" stroke="#3d8fe6" stroke-opacity="0.75">{glyph_path}</g>
</g>
</svg>
'''


PLACES = {
    "folder": "",
    "folder-download": '<path d="M512 450 v190 M430 560 l82 82 l82 -82" fill="none" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/>',
    "folder-documents": '<path d="M440 470 h110 l50 50 v140 h-160 Z" stroke-width="0"/>',
    "folder-pictures": '<path d="M410 660 l80 -100 l60 70 l40 -40 l60 70 Z" stroke-width="0"/><circle cx="600" cy="500" r="30" stroke-width="0"/>',
    "folder-music": '<path d="M480 640 a40 34 0 1 1 0 -2 v-170 l120 -26 v150 a40 34 0 1 1 0 -2 v-110 l-120 26" stroke-width="0"/>',
    "folder-videos": '<rect x="420" y="500" width="140" height="120" rx="20" stroke-width="0"/><path d="M572 540 l60 -36 v112 l-60 -36 Z" stroke-width="0"/>',
    "folder-desktop": '<rect x="420" y="480" width="184" height="126" rx="16" fill="none" stroke-width="28"/><path d="M470 652 h84" stroke-width="28" stroke-linecap="round"/>',
    "folder-publicshare": '<circle cx="470" cy="560" r="34" stroke-width="0"/><circle cx="590" cy="500" r="34" stroke-width="0"/><circle cx="590" cy="620" r="34" stroke-width="0"/><path d="M470 560 L590 500 M470 560 L590 620" stroke-width="20"/>',
    "folder-templates": '<path d="M440 470 h144 v190 h-144 Z" fill="none" stroke-width="26" stroke-dasharray="30 18"/>',
    "user-desktop": '<rect x="420" y="480" width="184" height="126" rx="16" fill="none" stroke-width="28"/><path d="M470 652 h84" stroke-width="28" stroke-linecap="round"/>',
    "user-home": '<path d="M512 456 l120 100 v110 h-80 v-70 h-80 v70 h-80 v-110 Z" stroke-width="0"/>',
    "folder-projects": '<path d="M450 520 l-50 50 l50 50 M574 520 l50 50 l-50 50" fill="none" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>',
}


def trash(full):
    paper = '''<path d="M360 300 q40 -90 150 -60 q100 -60 150 40 q30 40 0 60 h-300 q-30 -10 0 -40 Z" fill="#ffffff"/>
    <path d="M420 280 l60 -40 M560 250 l40 50" stroke="#c9ccd3" stroke-width="10"/>''' if full else ""
    ribs = "".join(f'<path d="M{410 + i * 68} 380 L{420 + i * 62} 820" stroke="#ffffff" stroke-opacity="0.5" stroke-width="14" stroke-linecap="round"/>' for i in range(4))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
<defs>
  {lg("can", "#eef0f4", "#b9bdc6")}
  <filter id="drop" x="-20%" y="-20%" width="140%" height="150%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="10"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.25"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
</defs>
<g filter="url(#drop)">
  {paper}
  <path d="M300 340 h424 l-40 500 q-4 40 -44 40 h-256 q-40 0 -44 -40 Z" fill="url(#can)" fill-opacity="0.92"/>
  {ribs}
  <rect x="270" y="300" width="484" height="64" rx="28" fill="#dfe2e8"/>
  <rect x="270" y="300" width="484" height="22" rx="11" fill="#ffffff" fill-opacity="0.7"/>
</g>
</svg>
'''


TILE = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
<defs>{lg("t", "#ffffff", "#e4e6eb")}
<filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="18"/><feOffset dy="14"/><feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
<g filter="url(#drop)"><path d="{BODY}" fill="url(#t)"/><path d="{BODY}" fill="none" stroke="#000" stroke-opacity="0.08" stroke-width="3"/></g></svg>
'''


def main():
    os.makedirs(sys.argv[1], exist_ok=True)
    # The plate the shell puts under apps that have no Memora icon.
    with open(os.path.join(sys.argv[1], "tile.svg"), "w") as f:
        f.write(TILE)
    out = os.path.join(sys.argv[1], "Memora")
    for sub in ("src/apps", "src/places"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    for name, svg in ICONS.items():
        with open(os.path.join(out, "src", name + ".svg"), "w") as f:
            f.write(svg)
    for name, glyph in PLACES.items():
        with open(os.path.join(out, "src/places", name + ".svg"), "w") as f:
            f.write(place(glyph))
    for name, full in (("user-trash", False), ("user-trash-full", True)):
        with open(os.path.join(out, "src/places", name + ".svg"), "w") as f:
            f.write(trash(full))
    # SVG sources live in src/; gen-art.sh renders them to PNG sizes with librsvg,
    # since Qt's SVG renderer skips the shadow filters.
    sizes = [32, 48, 64, 128, 256, 512]
    dirs = [f"{n}x{n}/{ctx}" for n in sizes for ctx in ("apps", "places")]
    with open(os.path.join(out, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=Memora\nComment=Memora app and place icons\n"
                "Inherits=Papirus-Dark,Adwaita,hicolor\nDirectories=" + ",".join(dirs) + "\n")
        for d in dirs:
            n = d.split("x")[0]
            ctx = "Applications" if d.endswith("apps") else "Places"
            f.write(f"\n[{d}]\nSize={n}\nType=Fixed\nContext={ctx}\n")


if __name__ == "__main__":
    main()
