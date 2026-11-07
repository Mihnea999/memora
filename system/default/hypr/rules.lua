
hl.window_rule({
  name = "memora-xwayland-drag",
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- Windows float like on a desktop and open centred at their own size.
-- Super+V puts one into the tiled layout; Super+Shift+F maximizes.
hl.window_rule({ name = "memora-float-all", match = { class = ".*" }, float = true })

-- The free part of a monitor: below the menu bar, above the Dock (logical pixels).
memora.work_area = function(m)
  local r = m.reserved or {}
  local l = r.left or r[1] or 0
  local t = r.top or r[2] or 0
  local rt = r.right or r[3] or 0
  local b = r.bottom or r[4] or 0
  local s = m.scale or 1
  return m.x + l, m.y + t, m.width / s - l - rt, m.height / s - t - b
end

-- A new floating window fits inside the free area and opens in its middle, so
-- nothing hides under the menu bar or the Dock, however big the app asks to be.
hl.on("window.open", function(w)
  if not w or not w.floating or (w.fullscreen or 0) ~= 0 or not w.monitor then return end
  local x, y, aw, ah = memora.work_area(w.monitor)
  local gap = 18
  aw, ah = aw - 2 * gap, ah - 2 * gap
  local sz = w.size or {}
  local ww, wh = sz.x or sz[1] or aw, sz.y or sz[2] or ah
  local nw, nh = math.min(ww, aw), math.min(wh, ah)
  local sel = "address:" .. w.address
  if nw < ww or nh < wh then hl.dispatch(hl.dsp.window.resize({ x = math.floor(nw), y = math.floor(nh), window = sel })) end
  hl.dispatch(hl.dsp.window.move({ x = math.floor(x + gap + (aw - nw) / 2), y = math.floor(y + gap + (ah - nh) / 2), window = sel }))
end)

-- Floating utility windows launched by Memora tools.
for _, class in ipairs({ "memora-float", "memora-ai", "memora-welcome", "org.pulseaudio.pavucontrol", "nm-connection-editor", "satty" }) do
  hl.window_rule({ name = "memora-float-" .. class, match = { class = "^(" .. class .. ")$" }, float = true, center = true })
end
hl.window_rule({ name = "memora-ai-size", match = { class = "^(memora-ai)$" }, size = "760 720" })
hl.window_rule({ name = "memora-welcome-size", match = { class = "^(memora-welcome)$" }, size = "680 500" })
hl.window_rule({ name = "memora-float-tool-size", match = { class = "^(memora-float)$" }, size = "900 600" })

-- Glass surfaces: blur what is behind the shell's translucent layers.
for _, ns in ipairs({ "memora-bar", "memora-dock", "memora-panel", "memora-launchpad", "memora-spotlight", "memora-overview",
  "memora-notifications", "memora-osd", "memora-dialog", "memora-switcher" }) do
  hl.layer_rule({ name = "memora-glass-" .. ns, match = { namespace = "^(" .. ns .. ")$" }, blur = true, ignore_alpha = 0.3 })
end
hl.layer_rule({ name = "memora-no-anim-wallpaper", match = { namespace = "^(memora-wallpaper|memora-genie|memora-snap)$" }, no_anim = true })
