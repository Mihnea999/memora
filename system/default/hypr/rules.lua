
hl.window_rule({
  name = "memora-xwayland-drag",
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- Windows float like on a desktop and open centred at their own size.
-- Super+V puts one into the tiled layout; Super+Shift+F maximizes.
hl.window_rule({ name = "memora-float-all", match = { class = ".*" }, float = true, center = true })

-- Floating utility windows launched by Memora tools.
for _, class in ipairs({ "memora-float", "memora-ai", "memora-welcome", "org.pulseaudio.pavucontrol", "nm-connection-editor", "satty" }) do
  hl.window_rule({ name = "memora-float-" .. class, match = { class = "^(" .. class .. ")$" }, float = true, center = true })
end
hl.window_rule({ name = "memora-ai-size", match = { class = "^(memora-ai)$" }, size = "1000 680" })
hl.window_rule({ name = "memora-welcome-size", match = { class = "^(memora-welcome)$" }, size = "640 470" })
hl.window_rule({ name = "memora-float-tool-size", match = { class = "^(memora-float)$" }, size = "900 600" })

-- Glass surfaces: blur what is behind the shell's translucent layers.
for _, ns in ipairs({ "memora-bar", "memora-dock", "memora-panel", "memora-launchpad", "memora-spotlight",
  "memora-notifications", "memora-osd", "memora-dialog", "memora-switcher" }) do
  hl.layer_rule({ name = "memora-glass-" .. ns, match = { namespace = "^(" .. ns .. ")$" }, blur = true, ignore_alpha = 0.18 })
end
hl.layer_rule({ name = "memora-no-anim-wallpaper", match = { namespace = "^(memora-wallpaper)$" }, no_anim = true })
