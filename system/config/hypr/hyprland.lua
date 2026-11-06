-- Memora: Hyprland entry point.
-- Defaults live in /usr/share/memora and update with the system.
-- Put your own settings in ~/.config/hypr/user.lua; they load last and win.

local home = os.getenv("HOME")
dofile((os.getenv("MEMORA_PATH") or "/usr/share/memora") .. "/default/hypr/memora.lua")
pcall(dofile, home .. "/.config/memora/current/hyprland.lua")
pcall(dofile, home .. "/.config/hypr/monitors.lua")
pcall(dofile, home .. "/.config/hypr/user.lua")
