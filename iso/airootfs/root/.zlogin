# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# Start the Memora installer once, on the first console.
if [[ $(tty) == /dev/tty1 && ! -e /tmp/.memora-started ]] && ! grep -qw memora.auto /proc/cmdline; then
  touch /tmp/.memora-started
  # Nothing of the console shows: a black screen until the installer is up.
  setterm --cursor off --blank 0 2>/dev/null; clear
  # The graphical installer; the text one if the screen can't show it.
  ln -sfn /opt/memora/icons/Memora /usr/share/icons/Memora 2>/dev/null
  if ! env WLR_NO_HARDWARE_CURSORS=1 MEMORA_PATH=/opt/memora MEMORA_MODE=dark QS_ICON_THEME=Memora QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
      cage -s -- qs -p /opt/memora/shell/installer.qml 2>/tmp/installer-gui.log; then
    memora-install
  fi
  setterm --cursor on 2>/dev/null
  cat /etc/memora-help 2>/dev/null
fi
