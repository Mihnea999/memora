-- Memora look: floating windows with deep soft shadows, hairline edges, glass surfaces.
hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    float_gaps = 0,
    border_size = 1,
    resize_on_border = true,
    layout = "dwindle",
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
      size = 9,
      passes = 3,
      noise = 0.012,
      contrast = 1.05,
      brightness = 1.0,
      vibrancy = 0.25,
      vibrancy_darkness = 0.2,
      popups = true,
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
  },
  cursor = { hide_on_key_press = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- Springy, quick motion.
hl.curve("glass", { type = "spring", mass = 1, stiffness = 260, dampening = 26 })
hl.curve("out", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.animation({ leaf = "global", enabled = true, speed = 6, bezier = "out" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, spring = "glass", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, spring = "glass" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.2, bezier = "out", style = "popin 94%" })
hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "out" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "out" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "out", style = "popin 96%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.6, bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, spring = "glass", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, spring = "glass", style = "slidevert" })
