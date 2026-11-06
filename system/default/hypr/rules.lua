hl.window_rule({ name = "memora-suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

hl.window_rule({
  name = "memora-xwayland-drag",
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- Floating utility windows launched by Memora tools.
for _, class in ipairs({ "memora-float", "memora-ai", "memora-welcome", "org.pulseaudio.pavucontrol", "nm-connection-editor", "satty" }) do
  hl.window_rule({ name = "memora-float-" .. class, match = { class = "^(" .. class .. ")$" }, float = true, center = true })
end
hl.window_rule({ name = "memora-ai-size", match = { class = "^(memora-ai)$" }, size = "1000 680" })
hl.window_rule({ name = "memora-welcome-size", match = { class = "^(memora-welcome)$" }, size = "640 470" })
hl.window_rule({ name = "memora-float-size", match = { class = "^(memora-float)$" }, size = "900 600" })

-- Glass surfaces: blur everything behind bar, dock, launcher, notifications and lock.
for _, ns in ipairs({ "waybar", "launcher", "notifications", "nwg-dock", "hyprlock" }) do
  hl.layer_rule({ name = "memora-glass-" .. ns, match = { namespace = "^(" .. ns .. ")$" }, blur = true, ignore_alpha = 0.1 })
end
