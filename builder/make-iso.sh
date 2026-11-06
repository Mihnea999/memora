#!/usr/bin/env bash
# Runs inside the builder container (privileged). Produces out/memora-*.iso.
set -euo pipefail
src=/src
work=/build
prof="$work/profile"
rm -rf "$work"; mkdir -p "$work"

"$src/tools/gen-art.sh"

cp -r /usr/share/archiso/configs/releng "$prof"
cp "$src/iso/profiledef.sh" "$prof/profiledef.sh"
cat "$src/iso/packages.extra" >> "$prof/packages.x86_64"
cp -rT "$src/iso/airootfs" "$prof/airootfs"
mkdir -p "$prof/airootfs/opt"
cp -a "$src/system" "$prof/airootfs/opt/memora"
rm -f "$prof"/airootfs/opt/memora/branding/*.tpl

# Rename boot menu entries and shorten the timeout.
grep -rlZ 'Arch Linux install medium' "$prof"/{efiboot,syslinux,grub} | xargs -0 sed -i \
  -e 's/Arch Linux install medium/Memora installer/g' \
  -e 's/Boot the Arch Linux install medium/Boot the Memora installer/g'
sed -i 's/^timeout .*/timeout 5/' "$prof/efiboot/loader/loader.conf"
sed -i 's/^beep on//' "$prof/efiboot/loader/loader.conf"

mkdir -p "$src/out"
mkarchiso -v -r -w "$work/work" -o "$src/out" "$prof"
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$src/out"
ls -lh "$src/out"
