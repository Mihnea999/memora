-- Keyboard and pointer. The installer writes ~/.config/memora/keyboard.lua and
-- System Settings writes ~/.config/memora/input.lua; both return a table.
local function load(name)
  local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/memora/" .. name)
  return (ok and type(t) == "table") and t or {}
end
local kb, pref = load("keyboard.lua"), load("input.lua")
local function pick(v, d) if v == nil then return d end return v end

hl.config({
  input = {
    kb_layout = pref.layout or kb.layout or "us",
    kb_options = "compose:caps",
    repeat_rate = pick(pref.repeat_rate, 40),
    repeat_delay = pick(pref.repeat_delay, 250),
    follow_mouse = 1,
    sensitivity = pick(pref.speed, 0),
    natural_scroll = pick(pref.mouse_natural, false),
    touchpad = {
      natural_scroll = pick(pref.natural_scroll, true),
      tap_to_click = pick(pref.tap_to_click, true),
      clickfinger_behavior = true,
    },
  },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
