hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("QS_ICON_THEME", "Memora")
-- Memora commands, including ones added by an update.
hl.env("PATH", (os.getenv("MEMORA_PATH") or "/usr/share/memora") .. "/bin:" .. (os.getenv("PATH") or "/usr/bin"))
hl.env("MEMORA_PATH", os.getenv("MEMORA_PATH") or "/usr/share/memora")

-- NVIDIA tweaks, written by the installer only on NVIDIA machines.
local f = io.open("/etc/memora/nvidia", "r")
if f then
  f:close()
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  hl.env("NVD_BACKEND", "direct")
end
