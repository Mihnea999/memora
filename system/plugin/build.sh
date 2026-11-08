#!/usr/bin/env bash
# Build the Memora Hyprland plugin against the installed Hyprland.
# Run again after Hyprland updates (a pacman hook does it).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
out="${1:-/usr/lib/memora/memora-minimize.so}"
mkdir -p "$(dirname "$out")"
g++ -shared -fPIC -std=c++26 -O2 $(pkg-config --cflags hyprland pixman-1 libdrm) \
  "$src/minimize.cpp" "$src/titlebar.cpp" -o "$out.new"
mv "$out.new" "$out"
echo "built $out for Hyprland $(Hyprland --version 2>/dev/null | head -1 | awk '{print $2}')"
