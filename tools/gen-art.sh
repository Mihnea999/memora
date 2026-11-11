#!/usr/bin/env bash
# Renders logos and wallpapers for every theme. Needs rsvg-convert and ImageMagick.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/system/lib/render.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# 8K wallpapers: silk (tools/silk.py) and the crisp sets (tools/walls.py), each in
# light and dark. Rendering takes a while, so each is only redone when its drawing changes.
render_wall() { # name mode script...
  local name=$1 mode=$2 out="$root/system/wallpapers/$1-$2.jpg"; shift 2
  [[ -f $out && $out -nt $1 ]] && return 0
  mkdir -p "$root/system/wallpapers"
  python3 "$@" > "$tmp/w.svg"
  rsvg-convert -w 7680 -h 4800 "$tmp/w.svg" -o "$tmp/w.png"
  magick "$tmp/w.png" -depth 16 -attenuate 0.10 +noise Gaussian -depth 8 -sampling-factor 4:4:4 -quality 94 "$out"
}
# Prism, Ember and Tide are lit per pixel (tools/prism.py and tools/flow.py need numpy
# and pillow; set PYTHON to an interpreter that has them).
render_flow() { # name mode
  local name=$1 mode=$2 out="$root/system/wallpapers/$1-$2.jpg"
  [[ -f $out && $out -nt $root/tools/flow.py ]] && return 0
  "${PYTHON:-python3}" "$root/tools/flow.py" "$name" "$mode" 7680 4800 "$tmp/f.png"
  magick "$tmp/f.png" -sampling-factor 4:4:4 -quality 94 "$out"
}
render_prism() { # mode
  local out="$root/system/wallpapers/prism-$1.jpg"
  [[ -f $out && $out -nt $root/tools/prism.py ]] && return 0
  "${PYTHON:-python3}" "$root/tools/prism.py" "$1" 7680 4800 "$tmp/b.png"
  magick "$tmp/b.png" -sampling-factor 4:4:4 -quality 94 "$out"
  magick "$out" -resize 540x338 -quality 88 "$root/system/wallpapers/thumbs/prism-$1.jpg"
}
wallpaper() { # theme-dir mode
  local m=$2
  render_prism "$m"; render_flow ember "$m"; render_flow tide "$m"
  render_wall silk "$m" "$root/tools/silk.py" "$m"
  for n in horizon dunes; do render_wall "$n" "$m" "$root/tools/walls.py" "$n" "$m"; done
  ln -sf "../../wallpapers/prism-$m.jpg" "$1/wallpaper.jpg"
}

for theme in "$root"/system/themes/*/; do
  t="$(basename "$theme")"
  memora_render "$theme/colors" "$root/system/branding/logo.svg.tpl" "$theme/logo.svg"
  rsvg-convert -w 256 -h 256 "$theme/logo.svg" -o "$theme/logo.png"
  wallpaper "$theme" "$t"
  echo "art: $t"
done

cp "$root/system/themes/light/logo.svg" "$root/system/branding/logo.svg"
rsvg-convert -w 512 -h 512 "$root/system/branding/logo.svg" -o "$root/system/branding/logo.png"
rsvg-convert -w 160 -h 160 "$root/system/themes/dark/logo.svg" -o "$root/system/plymouth/watermark.png"
rsvg-convert -w 256 -h 256 "$root/system/branding/app-icon.svg" -o "$root/system/branding/app-icon.png"

# Icon theme: SVG sources to PNG sizes.
python3 "$root/tools/icons.py" "$root/system/icons"
for svg in "$root"/system/icons/Memora/src/*/*.svg; do
  ctx="$(basename "$(dirname "$svg")")"; name="$(basename "$svg" .svg)"
  for n in 32 48 64 128 256 512; do
    mkdir -p "$root/system/icons/Memora/${n}x${n}/$ctx"
    png="$root/system/icons/Memora/${n}x${n}/$ctx/$name.png"
    [[ -f $png && $png -nt $root/tools/icons.py ]] && continue
    rsvg-convert -w $n -h $n "$svg" -o "$root/system/icons/Memora/${n}x${n}/$ctx/$name.png"
  done
done
rsvg-convert -w 512 -h 512 "$root/system/icons/tile.svg" -o "$root/system/icons/tile.png"
echo "art: icons"
