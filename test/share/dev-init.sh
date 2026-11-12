# Dev VM helper, started at login by ~/.local/bin/memora-dev-boot (dev disk only).
# - logs/: everything the system and the session print, readable from the host
#   in test/share/logs/ (the previous boot's go to logs/prev/)
# - /mnt/share/cmd: a command file run in the session, output in cmd.out
# - ydotool socket /tmp/.ydotool_socket for pointer tests
pw() { echo memora | sudo -S "$@"; }
L=/mnt/share/logs
mkdir -p "$L"; rm -rf "$L/prev"; mkdir -p "$L/prev"; mv "$L"/*.log "$L/prev/" 2>/dev/null

# Everything in the journal (system + session, incl. the shell and apps started
# with uwsm app), with milliseconds.
(pw journalctl -b -n all -f -o short-precise --no-pager > "$L/journal.log" 2>&1 &)
# The shell's own output (QML errors, console.log): restarted with it going to
# logs/shell.log. To restart it later and keep logging: bash /mnt/share/shell-restart.sh
bash /mnt/share/shell-restart.sh
# Hyprland's own log.
(tail -n +1 -F "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log > "$L/hyprland.log" 2>&1 &)
# Windows opening/closing, focus, workspaces (Hyprland events).
(socat -u "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" - 2>/dev/null \
  | while IFS= read -r l; do printf '%s %s\n' "$(date +%T.%3N)" "$l"; done > "$L/events.log" &)

hyprctl eval 'hl.config({input={accel_profile="flat", sensitivity=0}})' >/dev/null
[ -S /tmp/.ydotool_socket ] || pw systemd-run --unit=ydotoold-dev-$RANDOM ydotoold --socket-path=/tmp/.ydotool_socket --socket-own=1000:1000 >/dev/null 2>&1

echo "$(date +%T) dev-init ready" > "$L/dev.log"
rm -f /mnt/share/cmd
while true; do if [ -f /mnt/share/cmd ]; then bash /mnt/share/cmd > /mnt/share/cmd.out 2>&1; rm -f /mnt/share/cmd; fi; sleep 0.1; done
