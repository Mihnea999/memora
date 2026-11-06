#!/usr/bin/env bash
# Build the Memora ISO in a privileged Arch container. Output: out/*.iso
set -euo pipefail
cd "$(dirname "$0")"
docker build -q -t memora-builder builder/ >/dev/null
docker run --rm --privileged \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$PWD:/src" \
  -v memora-pacman-cache:/var/cache/pacman/pkg \
  memora-builder /src/builder/make-iso.sh
