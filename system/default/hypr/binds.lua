-- Keybindings. Every bind has a description, which memora-keys shows.
local S = "SUPER"
local function b(keys, dsp, desc, opts)
  opts = opts or {}
  opts.description = desc
  hl.bind(keys, dsp, opts)
end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end
local function app(cmd) return hl.dsp.exec_cmd("uwsm app -- " .. cmd) end

-- Apps
b(S .. " + RETURN", app(memora.terminal), "Terminal")
b(S .. " + SPACE", run("memora-launch"), "App launcher")
b(S .. " + B", app(memora.browser), "Browser")
b(S .. " + E", app(memora.files), "Files")
b(S .. " + A", run("memora-ai window"), "Memora AI")
b(S .. " + SHIFT + A", run("memora-ai explain-clipboard"), "AI: explain clipboard")
b(S .. " + M", run("memora-menu"), "Memora menu")
b(S .. " + K", run("memora-keys"), "Show keybindings")
b(S .. " + T", run("memora-theme next"), "Next theme")
b(S .. " + C", run("memora-clipboard"), "Clipboard history")

-- Windows
b(S .. " + Q", hl.dsp.window.close(), "Close window")
b(S .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Fullscreen")
b(S .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), "Maximize")
b(S .. " + V", hl.dsp.window.float({ action = "toggle" }), "Toggle floating")
b(S .. " + P", hl.dsp.window.pseudo(), "Pseudo-tile")
b(S .. " + J", hl.dsp.layout("togglesplit"), "Toggle split")

for key, dir in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
  b(S .. " + " .. key, hl.dsp.focus({ direction = dir }), "Focus " .. key)
  b(S .. " + SHIFT + " .. key, hl.dsp.window.swap({ direction = dir }), "Swap " .. key)
end
b(S .. " + ALT + left", hl.dsp.window.resize({ x = -60, y = 0, relative = true }), "Shrink width", { repeating = true })
b(S .. " + ALT + right", hl.dsp.window.resize({ x = 60, y = 0, relative = true }), "Grow width", { repeating = true })
b(S .. " + ALT + up", hl.dsp.window.resize({ x = 0, y = -60, relative = true }), "Shrink height", { repeating = true })
b(S .. " + ALT + down", hl.dsp.window.resize({ x = 0, y = 60, relative = true }), "Grow height", { repeating = true })
b(S .. " + mouse:272", hl.dsp.window.drag(), "Move window", { mouse = true })
b(S .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

-- Workspaces
for i = 1, 10 do
  local key = i % 10
  b(S .. " + " .. key, hl.dsp.focus({ workspace = tostring(i) }), "Workspace " .. i)
  b(S .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(i) }), "Move to workspace " .. i)
end
b(S .. " + TAB", hl.dsp.focus({ workspace = "previous" }), "Previous workspace")
b(S .. " + S", hl.dsp.workspace.toggle_special("scratch"), "Scratchpad")
b(S .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }), "Move to scratchpad")
b(S .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Next workspace")
b(S .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Previous workspace")

-- Capture
b("PRINT", run("memora-screenshot region"), "Screenshot region")
b("SHIFT + PRINT", run("memora-screenshot screen"), "Screenshot screen")
b(S .. " + PRINT", run("memora-screenshot edit"), "Screenshot and annotate")
b(S .. " + SHIFT + C", run("hyprpicker -a"), "Color picker")

-- Session
b(S .. " + L", run("loginctl lock-session"), "Lock")
b(S .. " + ESCAPE", run("memora-menu power"), "Power menu")
b(S .. " + SHIFT + R", run("hyprctl reload"), "Reload Hyprland")

-- Hardware keys
local lr = { locked = true, repeating = true }
b("XF86AudioRaiseVolume", run("memora-osd volume up"), "Volume up", lr)
b("XF86AudioLowerVolume", run("memora-osd volume down"), "Volume down", lr)
b("XF86AudioMute", run("memora-osd volume mute"), "Mute", { locked = true })
b("XF86AudioMicMute", run("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Mute microphone", { locked = true })
b("XF86MonBrightnessUp", run("memora-osd brightness up"), "Brightness up", lr)
b("XF86MonBrightnessDown", run("memora-osd brightness down"), "Brightness down", lr)
b("XF86AudioPlay", run("playerctl play-pause"), "Play/pause", { locked = true })
b("XF86AudioPause", run("playerctl play-pause"), "Play/pause", { locked = true })
b("XF86AudioNext", run("playerctl next"), "Next track", { locked = true })
b("XF86AudioPrev", run("playerctl previous"), "Previous track", { locked = true })
