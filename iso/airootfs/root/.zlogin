# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# Start the Memora installer once, on the first console.
if [[ $(tty) == /dev/tty1 && ! -e /tmp/.memora-started ]] && ! grep -qw memora.auto /proc/cmdline; then
  touch /tmp/.memora-started
  # The graphical installer; the text one if the screen can't show it.
  ln -sfn /opt/memora/icons/Memora /usr/share/icons/Memora 2>/dev/null
  if ! env MEMORA_PATH=/opt/memora MEMORA_MODE=dark QS_ICON_THEME=Memora QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
      cage -s -- qs -p /opt/memora/shell/installer.qml 2>/tmp/installer-gui.log; then
    memora-install
  fi
  echo
  echo "Installer closed. Run 'memora-install' to start it again."
fi
