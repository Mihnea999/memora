# Restart Memora's shell with its output appended to logs/shell.log.
L=/mnt/share/logs; mkdir -p "$L"
pkill -f "qs -p /usr/share/memora/shell\$"; sleep 0.5
echo "===== $(date +%T.%3N) shell start =====" >> "$L/shell.log"
setsid -f memora-shell >> "$L/shell.log" 2>&1
