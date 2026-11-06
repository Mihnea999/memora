# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# Start the Memora installer once, on the first console.
if [[ $(tty) == /dev/tty1 && ! -e /tmp/.memora-started ]] && ! grep -qw memora.auto /proc/cmdline; then
  touch /tmp/.memora-started
  memora-install
  echo
  echo "Installer closed. Run 'memora-install' to start it again."
fi
