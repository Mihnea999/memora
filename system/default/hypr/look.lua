-- Memora look: floating windows with deep soft shadows, hairline edges, glass surfaces.
hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    float_gaps = 0,
    border_size = 1,
    resize_on_border = true,
    layout = "dwindle",
    snap = { enabled = true, window_gap = 12, monitor_gap = 14, respect_gaps = false },
  },
  decoration = {
    rounding = 12,
    rounding_power = 3,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    shadow = { enabled = true, range = 70, render_power = 3, offset = "0 22", scale = 0.97, color = "rgba(00000059)", color_inactive = "rgba(0000002e)" },
    dim_inactive = false,
    blur = {
      enabled = true,
      size = 12,
      passes = 4,
      noise = 0.012,
      contrast = 1.05,
      brightness = 1.0,
      vibrancy = 0.25,
      vibrancy_darkness = 0.2,
      popups = true,
      popups_ignorealpha = 0.3,
      xray = false,
      new_optimizations = true,
    },
  },
  animations = { enabled = true },
  dwindle = { preserve_split = true },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
    focus_on_activate = true,
    key_press_enables_dpms = true,
    animate_mouse_windowdragging = true,
    animate_manual_resizes = true,
    -- The session sets XDG_CURRENT_DESKTOP=Hyprland:GNOME on purpose (apps then
    -- use the system keyring), so Hyprland needn't warn about it.
    disable_xdg_env_checks = true,
  },
  cursor = { hide_on_key_press = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- Glass, from System Settings > Appearance (~/.config/memora/glass.lua).
local okg, gl = pcall(dofile, os.getenv("HOME") .. "/.config/memora/glass.lua")
if not okg or type(gl) ~= "table" then gl = {} end
local gb = math.max(0, math.min(1, tonumber(gl.blur) or 0.6))
local gv = math.max(0, math.min(1, tonumber(gl.vibrancy) or 0.5))
hl.config({ decoration = { blur = {
  enabled = gl.reduce ~= true and gb > 0.02,
  size = math.floor(3 + gb * 15 + 0.5),
  passes = gb < 0.35 and 2 or (gb < 0.7 and 3 or 4),
  vibrancy = 0.05 + gv * 0.45,
  vibrancy_darkness = 0.1 + gv * 0.2,
} } })

-- Motion, from System Settings > Animations (~/.config/memora/motion.lua).
local ok, mo = pcall(dofile, os.getenv("HOME") .. "/.config/memora/motion.lua")
if not ok or type(mo) ~= "table" then mo = {} end
local on = mo.enabled ~= false
local k = math.max(0.25, tonumber(mo.speed) or 1)   -- speed multiplier
local style = mo.style or "pop"
local function sp(v) return v / k end                -- Hyprland speeds are in 100 ms units

hl.curve("smooth", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("swift", { type = "bezier", points = { { 0.32, 0.72 }, { 0, 1 } } })
hl.curve("exit", { type = "bezier", points = { { 0.4, 0 }, { 1, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("spring", { type = "spring", mass = 1, stiffness = 170, dampening = 19 })

local open_style = ({ pop = "popin 82%", slide = "slide bottom", fade = "popin 98%" })[style] or "popin 82%"
local close_style = ({ pop = "popin 86%", slide = "slide bottom", fade = "popin 98%" })[style] or "popin 86%"

hl.config({ animations = { enabled = on } })
hl.animation({ leaf = "global", enabled = on, speed = sp(4.5), bezier = "smooth" })
hl.animation({ leaf = "windowsIn", enabled = on, speed = sp(4.2), spring = "spring", style = open_style })
hl.animation({ leaf = "windowsOut", enabled = on, speed = sp(2.6), bezier = "exit", style = close_style })
hl.animation({ leaf = "windowsMove", enabled = on, speed = sp(4.4), spring = "spring" })
hl.animation({ leaf = "fadeIn", enabled = on, speed = sp(3), bezier = "smooth" })
hl.animation({ leaf = "fadeOut", enabled = on, speed = sp(2.4), bezier = "exit" })
hl.animation({ leaf = "fadeSwitch", enabled = on, speed = sp(3.5), bezier = "smooth" })
hl.animation({ leaf = "fadeShadow", enabled = on, speed = sp(3.5), bezier = "smooth" })
hl.animation({ leaf = "fadeDim", enabled = on, speed = sp(3.5), bezier = "smooth" })
hl.animation({ leaf = "border", enabled = on, speed = sp(3), bezier = "smooth" })
hl.animation({ leaf = "layersIn", enabled = on, speed = sp(3), bezier = "smooth", style = "popin 94%" })
hl.animation({ leaf = "layersOut", enabled = on, speed = sp(2.2), bezier = "exit", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = on, speed = sp(3), bezier = "smooth" })
hl.animation({ leaf = "fadeLayersOut", enabled = on, speed = sp(2.2), bezier = "exit" })
hl.animation({ leaf = "workspaces", enabled = on, speed = sp(5), spring = "spring", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = on, speed = sp(4.2), bezier = "smooth", style = "slidefadevert 20%" })
