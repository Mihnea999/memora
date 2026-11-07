-- Minimize buttons in apps (see system/plugin).
local f = io.open("/usr/lib/memora/memora-minimize.so", "r")
if f then f:close(); pcall(hl.plugin.load, "/usr/lib/memora/memora-minimize.so") end

hl.on("hyprland.start", function()
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")
  hl.exec_cmd("memora-theme desktop-settings")
  -- One process draws the desktop: picture, menu bar, Dock, panels, notifications.
  hl.exec_cmd("uwsm app -- memora-shell")
  hl.exec_cmd("uwsm app -- hypridle")
  hl.exec_cmd("uwsm app -- wl-paste --watch cliphist store")
  hl.exec_cmd("sleep 1.5 && memora-welcome --first-run")
end)
