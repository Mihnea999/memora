-- Keybindings. Everything also works with the mouse (menu bar, Dock, window
-- buttons); these are the familiar PC shortcuts on top. Every bind has a
-- description, which memora-keys and Help > Keyboard Shortcuts show.
local S = "SUPER"
local function b(keys, dsp, desc, opts)
  opts = opts or {}
  opts.description = desc
  hl.bind(keys, dsp, opts)
end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end
local function app(cmd) return hl.dsp.exec_cmd("uwsm app -- " .. cmd) end
local function shell(cmd) return hl.dsp.exec_cmd("memora-shell " .. cmd) end

-- Finding and opening things
b(S .. " + SUPER_L", shell("toggle launchpad"), "Launchpad (tap Super)", { release = true })
b(S .. " + SPACE", shell("toggle spotlight"), "Spotlight search")
b("CTRL + ALT + T", app(memora.terminal), "Terminal")
b(S .. " + RETURN", app(memora.terminal), "Terminal")
b(S .. " + E", app(memora.files), "Files")
b(S .. " + B", app(memora.browser), "Browser")
b(S .. " + A", run("memora-ai window"), "Memora AI")
b(S .. " + P", run("memora-shell project"), "Screens: extend, mirror, one only")
b(S .. " + SHIFT + A", run("memora-ai explain-clipboard"), "AI: explain clipboard")
b(S .. " + I", run("memora-settings"), "System Settings")
b(S .. " + V", run("memora-clipboard"), "Clipboard history")
b(S .. " + N", shell("toggle control"), "Control Center")

-- Windows, the classic way
b("ALT + TAB", shell("switch next"), "Switch windows")
b("ALT + SHIFT + TAB", shell("switch prev"), "Switch windows backwards")
b("ALT + ALT_L", shell("switch commit"), "Finish switching", { release = true })
b("ALT + F4", hl.dsp.window.close(), "Close window")
b(S .. " + Q", hl.dsp.window.close(), "Close window")
b(S .. " + M", run("memora-shell minimize"), "Minimize window")
b(S .. " + D", run("memora-shell show-desktop"), "Show desktop")
b(S .. " + UP", run("memora-window fill"), "Fill the screen")
b(S .. " + LEFT", run("memora-window left"), "Move to left half")
b(S .. " + RIGHT", run("memora-window right"), "Move to right half")
b(S .. " + DOWN", run("memora-window center"), "Center window")
b("F11", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Full screen", { non_consuming = true })
b(S .. " + T", hl.dsp.window.float({ action = "toggle" }), "Tile or float window")
b(S .. " + C", run("memora-window center"), "Center window")
b(S .. " + mouse:272", hl.dsp.window.drag(), "Move window", { mouse = true })
b(S .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

-- Desktops (workspaces)
for i = 1, 9 do
  b("CTRL + " .. S .. " + " .. i, hl.dsp.focus({ workspace = tostring(i) }), "Desktop " .. i)
  b("CTRL + " .. S .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = tostring(i) }), "Move window to desktop " .. i)
end
b("CTRL + " .. S .. " + right", hl.dsp.focus({ workspace = "e+1" }), "Next desktop")
b("CTRL + " .. S .. " + left", hl.dsp.focus({ workspace = "e-1" }), "Previous desktop")

-- Capture
b("PRINT", run("memora-screenshot region"), "Screenshot of an area")
b("SHIFT + PRINT", run("memora-screenshot screen"), "Screenshot of the screen")
b(S .. " + SHIFT + S", run("memora-screenshot region"), "Screenshot of an area")
b(S .. " + PRINT", run("memora-screenshot edit"), "Screenshot and annotate")

-- Session
b(S .. " + L", run("memora-lock"), "Lock screen")
b("CTRL + ALT + DELETE", run("memora-power"), "Power options")
b(S .. " + SHIFT + R", run("hyprctl reload"), "Reload desktop settings")

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

-- Window docking: the shell follows a window being dragged between these two.
hl.bind("mouse:272", run("memora-shell snap begin"), { non_consuming = true, description = "Window docking (drag to an edge)" })
hl.bind("mouse:272", run("memora-shell snap end"), { non_consuming = true, release = true })
