
hl.window_rule({
  name = "memora-xwayland-drag",
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- Windows float like on a desktop and open centred at their own size.
-- Super+T puts one into the tiled layout; Super+Up fills the screen.
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

-- A new floating window fits inside the free area, so nothing hides under the
-- menu bar or the Dock, however big the app asks to be. An app's first window
-- opens where it was last; more windows cascade; dialogs open over their window;
-- Picture in Picture goes to a corner, on every desktop.
hl.on("window.open", function(w)
  if not w or not w.floating or (w.fullscreen or 0) ~= 0 or not w.monitor then return end
  local x, y, aw, ah = memora.work_area(w.monitor)
  local gap = 18
  aw, ah = aw - 2 * gap, ah - 2 * gap
  local sz = w.size or {}
  local ww, wh = sz.x or sz[1] or aw, sz.y or sz[2] or ah
  local nw, nh = math.min(ww, aw), math.min(wh, ah)
  local sel = "address:" .. w.address
  local px, py = x + gap + (aw - nw) / 2, y + gap + (ah - nh) / 2

  -- Where the shell remembers things (core/Frames.qml): each app's last frame,
  -- and the windows open now, by app.
  local cls = w.class or w.initial_class or w.initialClass or ""
  local title = w.title or ""
  local function state(path)
    local ok, t = pcall(dofile, path)
    return (ok and type(t) == "table") and t or {}
  end
  local home = os.getenv("HOME") or ""
  local open = state((os.getenv("XDG_CACHE_HOME") or (home .. "/.cache")) .. "/memora/open.lua")[cls] or {}
  local frames = state((os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/memora/frames.lua")
  local function fits(fx, fy, fw, fh)
    return fx >= x and fy >= y and fx + fw <= x + aw + 2 * gap and fy + fh <= y + ah + 2 * gap
  end

  if title:match("^Picture[%- ]in[%- ][Pp]icture") then
    -- Picture in Picture: small, in the bottom-right corner, on every desktop.
    local pw = math.max(320, math.floor((aw + 2 * gap) * 0.28))
    local ph = math.floor(pw * (wh / math.max(1, ww)))
    nw, nh = pw, ph
    px, py = x + aw + gap - pw, y + ah + gap - ph
    ww, wh = nw, nh   -- sized here
    hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh, window = sel }))
    if hl.dsp.window.pin then pcall(function() hl.dispatch(hl.dsp.window.pin({ action = "enable", window = sel })) end) end
  elseif #open == 0 then
    -- The app's first window: where it was last, if that is on this screen.
    local f = frames[cls]
    if f and f.w and f.h and fits(f.x, f.y, f.w, f.h) then
      nw, nh, px, py = f.w, f.h, f.x, f.y
      ww, wh = nw, nh   -- sized here
      hl.dispatch(hl.dsp.window.resize({ x = math.floor(nw), y = math.floor(nh), window = sel }))
    end
  else
    -- Another window of an open app: a dialog (much smaller) opens over the
    -- window in front, near its top; a new window cascades from it.
    local front = open[1]
    for _, o in ipairs(open) do if (o.focus or 99) < (front.focus or 99) then front = o end end
    if nw < front.w * 0.7 and nh < front.h * 0.7 then
      px, py = front.x + (front.w - nw) / 2, front.y + math.min(60, (front.h - nh) / 2)
    else
      px, py = front.x + 28, front.y + 28
      if not fits(px, py, nw, nh) then px, py = x + gap, y + gap end
    end
  end
  -- Never outside the free area.
  px = math.max(x + gap, math.min(px, x + gap + aw - nw))
  py = math.max(y + gap, math.min(py, y + gap + ah - nh))
  if nw < ww or nh < wh then hl.dispatch(hl.dsp.window.resize({ x = math.floor(nw), y = math.floor(nh), window = sel })) end
  hl.dispatch(hl.dsp.window.move({ x = math.floor(px), y = math.floor(py), window = sel }))
end)

-- Floating utility windows launched by Memora tools.
for _, class in ipairs({ "memora-float", "memora-ai", "memora-welcome", "org.pulseaudio.pavucontrol", "nm-connection-editor", "satty" }) do
  hl.window_rule({ name = "memora-float-" .. class, match = { class = "^(" .. class .. ")$" }, float = true, center = true })
end
hl.window_rule({ name = "memora-ai-size", match = { class = "^(memora-ai)$" }, size = "760 720" })
hl.window_rule({ name = "memora-welcome-size", match = { class = "^(memora-welcome)$" }, size = "720 520" })
hl.window_rule({ name = "memora-float-tool-size", match = { class = "^(memora-float)$" }, size = "900 600" })

-- Glass surfaces: blur what is behind the shell's translucent layers.
-- ignore_alpha: where a layer is fainter than this (its anti-aliased edge) nothing is
-- blurred. It sits just under the thinnest glass fill (core/Theme.qml).
local tf = io.open(os.getenv("HOME") .. "/.config/memora/theme")
local glass_floor = (tf and (tf:read("*l") or ""):match("light")) and 0.13 or 0.16
if tf then tf:close() end
for _, ns in ipairs({ "memora-bar", "memora-dock", "memora-panel", "memora-launchpad", "memora-spotlight", "memora-overview",
  "memora-notifications", "memora-osd", "memora-dialog", "memora-switcher" }) do
  -- blur_popups: the menus that hang from the bar and the Dock are glass too
  -- (without it they are see-through and what is behind shows sharp through the text).
  hl.layer_rule({ name = "memora-glass-" .. ns, match = { namespace = "^(" .. ns .. ")$" }, blur = true, blur_popups = true, ignore_alpha = glass_floor })
end
hl.layer_rule({ name = "memora-no-anim-wallpaper", match = { namespace = "^(memora-wallpaper|memora-genie|memora-snap)$" }, no_anim = true })
