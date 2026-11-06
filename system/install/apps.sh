#!/usr/bin/env bash
# Tidy the app launcher: hide helper entries, give a few apps plain names.
# Overrides live in /usr/local/share/applications, which wins over /usr/share.
set -euo pipefail
src=/usr/share/applications
dst=/usr/local/share/applications
mkdir -p "$dst"

hide=(qv4l2 qvidcap uuctl avahi-discover bssh bvnc lstopo nvim xgps xgpsspeed cmake-gui
      jshell-java17-openjdk jconsole-java17-openjdk java-java17-openjdk electron
      org.freedesktop.IBus.Setup kitty-open)
for id in "${hide[@]}"; do
  [[ -f $src/$id.desktop ]] || continue
  sed '/^\[Desktop Entry\]/a NoDisplay=true' "$src/$id.desktop" > "$dst/$id.desktop"
done

rename() { # id "New name"
  [[ -f $src/$1.desktop ]] || return 0
  sed -e "0,/^Name=.*/s//Name=$2/" -e '/^Name\[/d' "$src/$1.desktop" > "$dst/$1.desktop"
}
rename kitty "Terminal"
rename btop "System Monitor"
rename nm-connection-editor "Network Settings"
rename org.pulseaudio.pavucontrol "Sound Settings"
update-desktop-database -q "$dst" 2>/dev/null || true
