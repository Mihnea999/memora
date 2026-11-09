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
    -- Click to focus, as on a Mac: the window under the pointer still scrolls,
    -- but the keyboard goes where you click. Settings > Mouse can make focus
    -- follow the pointer instead.
    follow_mouse = pref.focus_follows and 1 or 2,
    float_switch_override_focus = pref.focus_follows and 1 or 0,
    sensitivity = pick(pref.speed, 0),
    natural_scroll = pick(pref.mouse_natural, false),
    touchpad = {
      natural_scroll = pick(pref.natural_scroll, true),
      tap_to_click = pick(pref.tap_to_click, true),
      clickfinger_behavior = true,
    },
  },
})

-- Three fingers: sideways between desktops, up for Mission Control, down for the
-- app's windows (App Exposé) or to leave what is open.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd("memora-shell show overview") end })
hl.gesture({ fingers = 3, direction = "down", action = function() hl.exec_cmd("memora-shell swipeDown") end })
-- Four fingers, as on a Mac: pinch for Apps, spread for the desktop.
hl.gesture({ fingers = 4, direction = "pinchin", action = function() hl.exec_cmd("memora-shell toggle launchpad") end })
hl.gesture({ fingers = 4, direction = "pinchout", action = function() hl.exec_cmd("memora-shell show-desktop") end })
