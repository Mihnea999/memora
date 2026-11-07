hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("QS_ICON_THEME", "Memora")
-- Apps from the App Store (Flatpak) appear in Launchpad, Spotlight and the Dock.
local home = os.getenv("HOME") or ""
local data = os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
if not data:find("flatpak/exports", 1, true) then
  data = home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:" .. data
end
hl.env("XDG_DATA_DIRS", data)
-- Memora commands, including ones added by an update.
-- And tools installed for you (Claude Code, npm/uv/mise tools from the App Store).
hl.env("PATH", (os.getenv("MEMORA_PATH") or "/usr/share/memora") .. "/bin:" .. home .. "/.local/bin:" .. home .. "/.local/share/mise/shims:" .. (os.getenv("PATH") or "/usr/bin"))
hl.env("MEMORA_PATH", os.getenv("MEMORA_PATH") or "/usr/share/memora")

-- NVIDIA. On a desktop with only an NVIDIA card everything uses it. On a
-- laptop with a built-in chip too (/etc/memora/hybrid) the desktop stays on the
-- built-in chip, which saves battery, and games go to NVIDIA (see memora-gpu).
local function exists(p) local h = io.open(p, "r"); if h then h:close(); return true end return false end
if exists("/etc/memora/nvidia") and not exists("/etc/memora/hybrid") then
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  hl.env("NVD_BACKEND", "direct")
  hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
end
