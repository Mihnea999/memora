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


def icon(name, defs, body_fill, art, light=False, lift=0.22):
    """One app icon: a squircle body (body_fill), a soft light from above, a glass
    rim (bright at the top, fading down) and the art drawn clipped to the body.
    Art uses url(#ink) (white glyph, a touch cooler at the bottom) and
    filter="url(#lift)" (the glyph floats a little above the body).
    light: a white body (paper apps), which gets a faint dark edge instead."""
    rim = ('<path d="{b}" fill="none" stroke="#000" stroke-opacity="0.10" stroke-width="2.5"/>'
           '<path d="{b}" fill="none" stroke="url(#rim)" stroke-width="5"/>') if light else \
          '<path d="{b}" fill="none" stroke="url(#rim)" stroke-width="5"/>'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
<defs>
  <clipPath id="body"><path d="{BODY}"/></clipPath>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="150%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="16"/><feOffset dy="12"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.24"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="lift" x="-30%" y="-30%" width="160%" height="170%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="10"/>
    <feComponentTransfer><feFuncA type="linear" slope="{0.12 if light else 0.20}"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <radialGradient id="sky" cx="0.5" cy="0" r="0.9">
    <stop offset="0" stop-color="#fff" stop-opacity="{lift}"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="{0.9 if light else 0.55}"/>
    <stop offset="0.35" stop-color="#fff" stop-opacity="0.08"/>
    <stop offset="1" stop-color="#fff" stop-opacity="{0.0 if light else 0.18}"/>
  </linearGradient>
  <linearGradient id="ink" gradientUnits="userSpaceOnUse" x1="0" y1="260" x2="0" y2="760"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e9edf5"/></linearGradient>
  {defs}
</defs>
<g filter="url(#drop)">
  <path d="{BODY}" fill="{body_fill}"/>
  <g clip-path="url(#body)">
    <rect width="{C}" height="{C}" fill="url(#sky)"/>
    {art}
  </g>
  {rim.format(b=BODY)}
</g>
</svg>
'''


def lg(id_, c1, c2, x1=0, y1=0, x2=0, y2=1):
    return f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>'


def rounded_poly(pts, rad):
    """A closed path through pts with every corner rounded by rad."""
    d = ""
    n = len(pts)
    for k in range(n):
        p0, p1, p2 = pts[k - 1], pts[k], pts[(k + 1) % n]

        def toward(a, b, t):
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            return (a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L)
        a = toward(p1, p0, rad)
        b = toward(p1, p2, rad)
        d += ("M" if k == 0 else "L") + f"{a[0]:.1f} {a[1]:.1f} Q{p1[0]:.1f} {p1[1]:.1f} {b[0]:.1f} {b[1]:.1f} "
    return d + "Z"


def rounded_triangle(cx, cy, r, rad):
    return rounded_poly([(cx + r * math.cos(a), cy + r * math.sin(a)) for a in (0, 2 * math.pi / 3, 4 * math.pi / 3)], rad)


def sparkle(cx, cy, r, k=0.18):
    """A four-pointed star with curved sides."""
    i = r * k
    return (f"M{cx} {cy - r} C{cx + i} {cy - i} {cx + i} {cy - i} {cx + r} {cy} "
            f"C{cx + i} {cy + i} {cx + i} {cy + i} {cx} {cy + r} "
            f"C{cx - i} {cy + i} {cx - i} {cy + i} {cx - r} {cy} "
            f"C{cx - i} {cy - i} {cx - i} {cy - i} {cx} {cy - r} Z")


# Every glyph sits in the middle half of the body (about 300..724), one idea per
# icon, white on colour; the paper apps (Notes, Calendar, Text Editor) are white
# with a coloured glyph.
ICONS = {}

# Files: a white folder on blue.
ICONS["apps/org.gnome.Nautilus"] = icon(
    "files", lg("bg", "#5fc6ff", "#0a62f0"), "url(#bg)",
    '''<g filter="url(#lift)">
      <path d="M290 372 q0 -40 40 -40 h118 q22 0 36 17 l26 31 h194 q40 0 40 40 v40 H290 Z" fill="#ffffff" fill-opacity="0.62"/>
      <rect x="290" y="420" width="444" height="292" rx="40" fill="url(#ink)"/>
    </g>''')
ICONS["apps/memora-files"] = ICONS["apps/org.gnome.Nautilus"]

# Notes: a yellow note on white, three lines on it.
ICONS["apps/memora-notes"] = icon(
    "notes", lg("bg", "#ffffff", "#eeeef1") + lg("note", "#ffd95a", "#ffb81c"), "url(#bg)",
    '''<g filter="url(#lift)">
      <rect x="300" y="276" width="424" height="472" rx="52" fill="url(#note)"/>
      <g stroke="#ffffff" stroke-opacity="0.92" stroke-width="28" stroke-linecap="round">
        <path d="M376 420 h272 M376 512 h272 M376 604 h168"/>
      </g>
    </g>''', light=True)

# Calendar: the day of the month under a red weekday, on white.
ICONS["apps/memora-calendar"] = icon(
    "calendar", lg("bg", "#ffffff", "#eeeef1"), "url(#bg)",
    '''<text x="512" y="330" text-anchor="middle" font-family="Inter, Adwaita Sans, sans-serif" font-weight="600"
            font-size="96" letter-spacing="4" fill="#ff3b30">MON</text>
    <text x="512" y="700" text-anchor="middle" font-family="Inter, Adwaita Sans, sans-serif" font-weight="300"
            font-size="380" letter-spacing="-4" fill="#1d1d1f">17</text>''', light=True)

# App Store: an "A" of three rounded strokes on blue.
ICONS["apps/memora-store"] = icon(
    "store", lg("bg", "#45bfff", "#1660f2"), "url(#bg)",
    '''<g filter="url(#lift)" stroke="url(#ink)" stroke-width="54" stroke-linecap="round" fill="none">
      <path d="M512 286 L360 630"/><path d="M512 286 L664 630"/><path d="M338 560 H686"/>
    </g>''')

# Launchpad: nine soft tiles, a colour each, on graphite.
_tiles = ["#ff6b6b", "#ffa94d", "#ffd43b", "#51cf66", "#22c3c9", "#4dabf7", "#845ef7", "#e64980", "#adb5bd"]
ICONS["apps/memora-launchpad"] = icon(
    "launchpad", lg("bg", "#4a4c55", "#1b1c20"), "url(#bg)",
    '<g filter="url(#lift)">' + "".join(
        f'<rect x="{302 + (i % 3) * 152}" y="{302 + (i // 3) * 152}" width="116" height="116" rx="34" fill="{c}"/>'
        for i, c in enumerate(_tiles)) + '</g>', lift=0.16)

# Browser: a white globe on sea blue.
ICONS["apps/chromium"] = icon(
    "browser", lg("bg", "#3fd4ec", "#1258e0"), "url(#bg)",
    '''<g filter="url(#lift)" fill="none" stroke="url(#ink)" stroke-width="26" stroke-linecap="round">
      <circle cx="512" cy="512" r="222"/>
      <ellipse cx="512" cy="512" rx="96" ry="222"/>
      <path d="M296 512 h432 M326 404 h372 M326 620 h372"/>
    </g>''')

# Terminal: a prompt on near-black.
ICONS["apps/org.gnome.Ptyxis"] = icon(
    "terminal", lg("bg", "#3b3d45", "#121316"), "url(#bg)",
    '''<g filter="url(#lift)" stroke-width="40" stroke-linecap="round" stroke-linejoin="round" fill="none">
      <path d="M330 404 l108 108 l-108 108" stroke="url(#ink)"/>
      <path d="M494 626 h200" stroke="#6ee7a1"/>
    </g>''', lift=0.14)
ICONS["apps/kitty"] = ICONS["apps/org.gnome.Ptyxis"]
ICONS["apps/com.mitchellh.ghostty"] = ICONS["apps/org.gnome.Ptyxis"]

# Memora AI: a white spark on a dusk gradient.
ICONS["apps/memora-ai"] = icon(
    "ai", lg("bg", "#8a6bff", "#ff7d5c", 0, 0, 1, 1), "url(#bg)",
    f'''<g filter="url(#lift)">
      <path fill="url(#ink)" d="{sparkle(490, 534, 230)}"/>
      <path fill="#ffffff" fill-opacity="0.85" d="{sparkle(696, 318, 74)}"/>
    </g>''', lift=0.26)

# Welcome: Memora's mark on midnight blue.
ICONS["apps/memora-welcome"] = icon(
    "welcome", lg("bg", "#3d4f80", "#121a30"), "url(#bg)",
    '''<g filter="url(#lift)" transform="translate(272 270) scale(3.75)">
      <path d="M26 100 V38 L64 78 L102 38 V100" fill="none" stroke="url(#ink)" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
      <circle cx="64" cy="22" r="9" fill="#8fb4ff"/>
    </g>''')

# Text Editor: lines of text and a blue caret, on white.
ICONS["apps/org.gnome.TextEditor"] = icon(
    "editor", lg("bg", "#ffffff", "#eeeef1"), "url(#bg)",
    '''<g stroke-linecap="round">
      <path d="M318 368 h388 M318 456 h388 M318 544 h300 M318 632 h196" stroke="#b9bcc6" stroke-width="30"/>
      <rect x="550" y="588" width="22" height="90" rx="11" fill="#0a84ff" filter="url(#lift)"/>
    </g>''', light=True)

# Calculator: plus, minus, times and equals, white on orange.
ICONS["apps/org.gnome.Calculator"] = icon(
    "calc", lg("bg", "#ffb340", "#ff6a00"), "url(#bg)",
    '''<g filter="url(#lift)" stroke="url(#ink)" stroke-width="40" stroke-linecap="round" fill="none">
      <path d="M352 400 h112 M408 344 v112"/>
      <path d="M560 400 h112"/>
      <path d="M368 584 l80 80 M448 584 l-80 80"/>
      <path d="M560 600 h112 M560 652 h112"/>
    </g>''')

# Photos: a white sun over white hills, on a sunset.
ICONS["apps/org.gnome.Loupe"] = icon(
    "photos", lg("bg", "#ffb15c", "#ff4f7b"), "url(#bg)",
    f'''<g filter="url(#lift)">
      <circle cx="610" cy="390" r="64" fill="url(#ink)"/>
      <path d="{rounded_poly([(292, 700), (446, 470), (560, 620), (624, 540), (732, 700)], 22)}" fill="url(#ink)"/>
    </g>''', lift=0.26)
ICONS["apps/memora-photos"] = ICONS["apps/org.gnome.Loupe"]

# Documents: a white page with a folded corner on red.
ICONS["apps/org.gnome.Papers"] = icon(
    "docs", lg("bg", "#ff6b5f", "#d92b47"), "url(#bg)",
    '''<g filter="url(#lift)">
      <path d="M362 262 h214 l122 122 v338 q0 40 -40 40 h-296 q-40 0 -40 -40 v-420 q0 -40 40 -40 Z" fill="url(#ink)"/>
      <path d="M576 262 v84 q0 38 38 38 h84 Z" fill="#ffc9c3"/>
      <g stroke="#f0c4c4" stroke-width="22" stroke-linecap="round"><path d="M392 500 h240 M392 572 h240 M392 644 h150"/></g>
    </g>''')

# Player: a white play mark on coral to magenta. Its box is centred, nudged 8px
# right (the point makes a truly centred triangle look left-heavy).
ICONS["apps/memora-player"] = icon(
    "player", lg("bg", "#ff7f5c", "#d42c7c", 0.2, 0, 0.8, 1), "url(#bg)",
    f'<path filter="url(#lift)" fill="url(#ink)" d="{rounded_triangle(470, 512, 200, 52)}"/>', lift=0.24)
ICONS["apps/mpv"] = ICONS["apps/memora-player"]


# Settings: a graphite gear on silver, its hole showing the body.
def _gear(cx=512, cy=512, ro=228, ri=178, hole=84, n=10):
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        w = math.pi / n
        for t, r in ((-0.55, ri), (-0.32, ro), (0.32, ro), (0.55, ri)):
            pts.append((cx + r * math.cos(a + t * w), cy + r * math.sin(a + t * w)))
    outer = rounded_poly(pts, 12)
    return outer + f" M{cx + hole} {cy} A{hole} {hole} 0 1 0 {cx - hole} {cy} A{hole} {hole} 0 1 0 {cx + hole} {cy} Z"


ICONS["apps/memora-settings"] = icon(
    "settings", lg("bg", "#e4e6ea", "#a4a8b1") + lg("gear", "#6b6f78", "#3d4047"), "url(#bg)",
    f'<path filter="url(#lift)" fill="url(#gear)" fill-rule="evenodd" d="{_gear()}"/>', light=True, lift=0.3)

# System monitor: a green pulse on black.
ICONS["apps/memora-activity"] = icon(
    "monitor", lg("bg", "#33363e", "#0f1013"), "url(#bg)",
    '''<path filter="url(#lift)" d="M290 540 h96 l60 -160 l92 290 l78 -210 l46 80 h72" fill="none"
            stroke="#5fe3a1" stroke-width="38" stroke-linecap="round" stroke-linejoin="round"/>''', lift=0.14)

# Archives: a white storage box, its lid and handle slot, on indigo.
ICONS["apps/memora-archive"] = icon(
    "archive", lg("bg", "#8f7dff", "#4732d6"), "url(#bg)",
    '''<g filter="url(#lift)">
      <rect x="290" y="304" width="444" height="104" rx="30" fill="url(#ink)"/>
      <rect x="318" y="430" width="388" height="290" rx="36" fill="url(#ink)" fill-opacity="0.9"/>
      <rect x="448" y="500" width="128" height="34" rx="17" fill="#5a47e0" fill-opacity="0.55"/>
    </g>''')


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
