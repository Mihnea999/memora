#!/usr/bin/env bash
# Renders logos and wallpapers for every theme. Needs rsvg-convert and ImageMagick.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/system/lib/render.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

wallpaper() { # theme-dir name — folded silk sheets (tools/silk.py), dithered against banding
  local dir=$1 t=$2
  python3 "$root/tools/silk.py" "$t" > "$tmp/silk.svg"
  rsvg-convert -w 3840 -h 2400 "$tmp/silk.svg" -o "$tmp/silk.png"
  magick "$tmp/silk.png" -depth 16 -attenuate 0.3 +noise Gaussian \
    -dither FloydSteinberg -depth 8 "$dir/wallpaper.png"
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
    rsvg-convert -w $n -h $n "$svg" -o "$root/system/icons/Memora/${n}x${n}/$ctx/$name.png"
  done
done
rsvg-convert -w 512 -h 512 "$root/system/icons/tile.svg" -o "$root/system/icons/tile.png"
echo "art: icons"
