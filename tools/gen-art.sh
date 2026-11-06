#!/usr/bin/env bash
# Renders logos and wallpapers for every theme. Needs rsvg-convert and ImageMagick.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/system/lib/render.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

wallpaper() { # theme-dir name
  local dir=$1 t=$2 base="" args=() pos size col
  while IFS='=' read -r k v; do
    case $k in
      base) base=$v ;;
      blob) read -r pos size col <<<"$v"; args+=(-fill "$col" -draw "ellipse ${pos} ${size} 0,360") ;;
    esac
  done < "$dir/wallpaper.spec"
  rsvg-convert -w 3840 -h 2160 "$root/system/branding/wallpaper-$t-lines.svg" -o "$tmp/lines.png"
  # Blobs are blurred at low resolution in 16-bit, then upscaled and dithered: no banding.
  magick -size 960x540 -depth 16 "xc:$base" "${args[@]}" -blur 0x95 \
    -filter Gaussian -resize 3840x2160! \
    "$tmp/lines.png" -composite \
    -attenuate 0.35 +noise Gaussian \
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
