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

# App Store source (Flathub), installed per user so apps need no password.
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
mkdir -p "$HOME/.local/share/flatpak/exports/share/applications"

# Default apps for common kinds of files.
xdg-mime default memora-files.desktop inode/directory
for t in image/png image/jpeg image/webp image/gif image/bmp image/svg+xml image/heic image/tiff image/avif image/jxl; do xdg-mime default memora-photos.desktop "$t"; done
for t in video/mp4 video/x-matroska video/webm video/quicktime audio/mpeg audio/flac audio/ogg audio/x-wav audio/mp4; do xdg-mime default memora-player.desktop "$t"; done
xdg-mime default org.gnome.Papers.desktop application/pdf
for t in text/plain text/markdown text/x-log application/json text/x-python text/x-shellscript; do xdg-mime default org.gnome.TextEditor.desktop "$t"; done
for t in x-scheme-handler/http x-scheme-handler/https text/html; do xdg-mime default chromium.desktop "$t"; done

# Browser profile: draw its window with the system (GTK) theme, so it gets
# Memora's round window buttons, and skip the welcome page.
mkdir -p "$cfg/chromium/Default"
[[ -f $cfg/chromium/Default/Preferences ]] || printf '%s\n' \
  '{"extensions":{"theme":{"system_theme":1}},"browser":{"custom_chrome_frame":true,"has_seen_welcome_page":true}}' \
  > "$cfg/chromium/Default/Preferences"
touch "$cfg/chromium/First Run"

printf '%s\n' --no-first-run --no-default-browser-check --password-store=gnome-libsecret --ozone-platform-hint=auto \
  > "$cfg/chromium-flags.conf"

# With disk encryption the session starts without a password, so there is none
# to unlock a keyring with: give it an open one (the disk itself is encrypted).
if [[ ${MEMORA_ENCRYPT:-0} == 1 ]]; then
  mkdir -p "$HOME/.local/share/keyrings"
  printf '[keyring]\ndisplay-name=Login\nctime=0\nmtime=0\nlock-on-idle=false\nlock-after=false\n' > "$HOME/.local/share/keyrings/login.keyring"
  printf 'login\n' > "$HOME/.local/share/keyrings/default"
  chmod 700 "$HOME/.local/share/keyrings"; chmod 600 "$HOME/.local/share/keyrings/"*
fi

# Optional toolkits picked in the installer that live in $HOME.
# Gaming: ProtonPlus (newer Proton and Wine builds for Steam), and on laptops
# with two graphics chips, Steam and every game it starts on the fast one.
if [[ " ${MEMORA_USER_TOOLKITS:-} " == *" gaming "* ]]; then
  flatpak install --user -y --noninteractive flathub com.vysp3r.ProtonPlus >/dev/null 2>&1 || echo "ProtonPlus can be installed later from the App Store."
  [[ -f /etc/memora/hybrid ]] && "$MEMORA_PATH/bin/memora-gpu" games on || true
  MEMORA_USER_TOOLKITS="${MEMORA_USER_TOOLKITS// gaming/}"
fi
for t in ${MEMORA_USER_TOOLKITS:-}; do
  echo "Installing toolkit: $t"
  PATH="$HOME/.local/bin:$PATH" "$MEMORA_PATH/bin/memora-dev" install "$t" || echo "Toolkit $t failed; run 'memora dev install $t' later."
done
