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

-- Super works like the Command key on a Mac.

-- Finding and opening things
b(S .. " + SUPER_L", shell("super-up"), "Apps (tap Super)", { release = true })
b(S .. " + SPACE", shell("toggle spotlight"), "Spotlight search")
b("CTRL + ALT + T", app(memora.terminal), "Terminal")
b(S .. " + RETURN", app(memora.terminal), "Terminal")
b(S .. " + E", app(memora.files), "Files")
b(S .. " + B", app(memora.browser), "Browser")
b(S .. " + A", run("memora-ai window"), "Memora AI")
b(S .. " + SHIFT + A", run("memora-ai explain-clipboard"), "AI: explain clipboard")
b(S .. " + COMMA", run("memora-settings"), "System Settings")
b(S .. " + I", run("memora-settings"), "System Settings")
b(S .. " + V", run("memora-clipboard"), "Clipboard history")
b(S .. " + N", shell("toggle control"), "Control Center")
b(S .. " + P", run("memora-shell project"), "Screens: extend, mirror, one only")
b(S .. " + ALT + ESCAPE", run("memora-app activity"), "Force Quit (Activity Monitor)")

-- Switching
b(S .. " + TAB", shell("switch next"), "Switch apps (hold Super)")
b(S .. " + SHIFT + TAB", shell("switch prev"), "Switch apps backwards")
b("ALT + TAB", shell("switch next"), "Switch windows")
b("ALT + SHIFT + TAB", shell("switch prev"), "Switch windows backwards")
b("ALT + ALT_L", shell("switch commit"), "Finish switching", { release = true })

-- Windows
b(S .. " + W", hl.dsp.window.close(), "Close window")
b(S .. " + Q", shell("quit-app"), "Quit the app (all its windows)")
b("ALT + F4", hl.dsp.window.close(), "Close window")
b(S .. " + M", run("memora-shell minimize"), "Minimize window")
b(S .. " + H", shell("hide-app"), "Hide the app")
b(S .. " + D", run("memora-shell show-desktop"), "Show desktop")
b(S .. " + F3", run("memora-shell show-desktop"), "Show desktop")
b("CTRL + " .. S .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Full screen")
b("F11", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Full screen", { non_consuming = true })
-- Docking from the keyboard: halves, then two-thirds and thirds on repeat;
-- combine for quarters (left, then up = top-left); down goes back.
b(S .. " + UP", run("memora-window key up"), "Fill the screen, or the top quarter")
b(S .. " + LEFT", run("memora-window key left"), "Left half, then two-thirds, then a third")
b(S .. " + RIGHT", run("memora-window key right"), "Right half, then two-thirds, then a third")
b(S .. " + DOWN", run("memora-window key down"), "Bottom quarter, or back to its own size")
b(S .. " + C", run("memora-window center"), "Center window")
b(S .. " + T", hl.dsp.window.float({ action = "toggle" }), "Tile or float window")
b(S .. " + mouse:272", hl.dsp.window.drag(), "Move window", { mouse = true })
b(S .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

-- Desktops
b("CTRL + " .. S .. " + UP", shell("toggle overview"), "Desktops and windows (Mission Control)")
b("F3", shell("toggle overview"), "Desktops and windows (Mission Control)", { non_consuming = true })
b(S .. " + S", shell("toggle overview"), "Desktops and windows (Mission Control)")
b("CTRL + " .. S .. " + RIGHT", shell("desktop next"), "Next desktop")
b("CTRL + " .. S .. " + LEFT", shell("desktop prev"), "Previous desktop")
b("CTRL + " .. S .. " + SHIFT + RIGHT", shell("desktop carryNext"), "Take the window to the next desktop")
b("CTRL + " .. S .. " + SHIFT + LEFT", shell("desktop carryPrev"), "Take the window to the previous desktop")
for i = 1, 9 do
  b("CTRL + " .. S .. " + " .. i, shell("desktop go " .. i), "Desktop " .. i)
  b("CTRL + " .. S .. " + SHIFT + " .. i, shell("desktop carry " .. i), "Take the window to desktop " .. i)
end

-- Capture, as on a Mac
b(S .. " + SHIFT + 3", run("memora-screenshot screen"), "Screenshot of the screen")
b(S .. " + SHIFT + 4", run("memora-screenshot region"), "Screenshot of an area")
b(S .. " + SHIFT + 5", run("memora-screenshot edit"), "Screenshot and annotate")
b(S .. " + SHIFT + S", run("memora-screenshot region"), "Screenshot of an area")
b("PRINT", run("memora-screenshot region"), "Screenshot of an area")
b("SHIFT + PRINT", run("memora-screenshot screen"), "Screenshot of the screen")

-- Session
b("CTRL + " .. S .. " + Q", run("memora-lock"), "Lock screen")
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
