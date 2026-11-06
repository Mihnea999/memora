#!/usr/bin/env bash
# Runs as the new user (inside the chroot) to set up the home directory.
set -euo pipefail
MEMORA_PATH=/usr/share/memora

cfg="$HOME/.config"
mkdir -p "$cfg" "$HOME/.local/bin" "$HOME/.local/state/memora"
for d in "$MEMORA_PATH"/config/*/; do
  name="$(basename "$d")"
  [[ $name == bash ]] && continue
  mkdir -p "$cfg/$name"
  cp -r --update=none "$d". "$cfg/$name/"
done
cp --update=none "$MEMORA_PATH/config/starship.toml" "$cfg/starship.toml"
cp "$MEMORA_PATH/config/bash/bashrc" "$HOME/.bashrc"
printf '[[ -f ~/.bashrc ]] && . ~/.bashrc\n' > "$HOME/.bash_profile"

mkdir -p "$cfg/memora"
printf 'return { layout = "%s" }\n' "${MEMORA_XKB:-us}" > "$cfg/memora/keyboard.lua"

MEMORA_PATH="$MEMORA_PATH" "$MEMORA_PATH/bin/memora-theme" set "${MEMORA_THEME:-dark}"

xdg-user-dirs-update || true

# Optional toolkits picked in the installer that live in $HOME.
for t in ${MEMORA_USER_TOOLKITS:-}; do
  echo "Installing toolkit: $t"
  PATH="$HOME/.local/bin:$PATH" "$MEMORA_PATH/bin/memora-dev" install "$t" || echo "Toolkit $t failed; run 'memora dev install $t' later."
done
