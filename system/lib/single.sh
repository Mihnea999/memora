# Single-instance launching for Memora's own apps (sourced by bin/memora-*).
# memora_window CLASS — true when a window of that class is on screen.
memora_window() { hyprctl clients -j 2>/dev/null | jq -e --arg c "$1" 'any(.[]; .class == $c)' >/dev/null; }
# memora_bring CLASS — show that window: back from the Dock if minimized, then focused.
memora_bring() {
  local addr ws
  read -r addr ws < <(hyprctl clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | "\(.address) \(.workspace.name)"')
  if [[ $ws == special:minimized ]]; then
    qs -p "${MEMORA_PATH:-/usr/share/memora}/shell" ipc call shell restore "$addr" >/dev/null 2>&1 && return
  fi
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
}
# memora_single CLASS QML — if the app runs with a window, bring it and return 0;
# if it runs without one (a stale process), end it; then return 1 to start fresh.
memora_single() {
  local cls=$1 qml=$2
  pgrep -f "qs -p $qml" >/dev/null || return 1
  if memora_window "$cls"; then memora_bring "$cls"; return 0; fi
  pkill -f "qs -p $qml"; sleep 0.2; return 1
}
