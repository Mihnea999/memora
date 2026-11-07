#!/usr/bin/env bash
# Build a signed Memora update: out/release/memora-VERSION.tar.zst(.sig) and
# out/release/latest. Upload the folder to the address in /etc/memora/update.conf
# (URL=https://…) on installed systems. Signed with your GPG key; put the public
# key in system/keys/release.asc before building the ISO, so installs trust it.
#   tools/release.sh [GPG-KEY-ID]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ver="$(cat "$root/system/version")"
out="$root/out/release"; mkdir -p "$out"
tar --zstd -cf "$out/memora-$ver.tar.zst" -C "$root/system" --exclude='./plugin/*.so' .
gpg --batch --yes ${1:+--local-user "$1"} --detach-sign -o "$out/memora-$ver.tar.zst.sig" "$out/memora-$ver.tar.zst"
echo "$ver" > "$out/latest"
echo "Release $ver in $out"
