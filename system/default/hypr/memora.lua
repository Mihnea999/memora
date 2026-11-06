-- Memora defaults for Hyprland. Shipped in /usr/share/memora and replaced on
-- update; put personal changes in ~/.config/hypr/user.lua instead.

local base = (os.getenv("MEMORA_PATH") or "/usr/share/memora") .. "/default/hypr/"

memora = memora or {}
memora.terminal = "ptyxis --new-window"
memora.browser = "chromium"
memora.files = "nautilus --new-window"

for _, part in ipairs({ "env", "look", "input", "rules", "binds", "autostart" }) do
  dofile(base .. part .. ".lua")
end
