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
  },
  cursor = { hide_on_key_press = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- Motion: calm ease-outs, the way a desktop should feel. Speeds are in 100 ms.
hl.curve("smooth", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("swift", { type = "bezier", points = { { 0.32, 0.72 }, { 0, 1 } } })
hl.curve("exit", { type = "bezier", points = { { 0.4, 0 }, { 1, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.animation({ leaf = "global", enabled = true, speed = 4, bezier = "smooth" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.2, bezier = "smooth", style = "popin 88%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.8, bezier = "exit", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.4, bezier = "smooth" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.4, bezier = "smooth" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.6, bezier = "exit" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 3, bezier = "smooth" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 3, bezier = "smooth" })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "smooth" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.2, bezier = "smooth", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.6, bezier = "exit", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2.2, bezier = "smooth" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.6, bezier = "exit" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.5, bezier = "swift", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.5, bezier = "smooth", style = "slidefadevert 20%" })
