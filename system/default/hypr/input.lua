-- Keyboard layout comes from the installer (~/.config/memora/keyboard.lua).
local layout = "us"
local ok, kb = pcall(dofile, os.getenv("HOME") .. "/.config/memora/keyboard.lua")
if ok and type(kb) == "table" and kb.layout then layout = kb.layout end

hl.config({
  input = {
    kb_layout = layout,
    kb_options = "compose:caps",
    repeat_rate = 40,
    repeat_delay = 250,
    follow_mouse = 1,
    sensitivity = 0,
    touchpad = { natural_scroll = true },
  },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
