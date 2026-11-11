# Memora

A desktop operating system based on Arch Linux and Hyprland, with a liquid-glass look in light and dark,
its own shell and apps, and an AI assistant that can work on the computer for you.
Inter for the interface (your choice in System Settings), JetBrains Mono for code.

## Build the ISO

Requires Docker. The build runs `mkarchiso` in a privileged Arch container.

```bash
./build.sh            # → out/memora-<version>-<date>-x86_64.iso
```

Write it to a USB stick (`dd` or Ventoy) and boot it in **UEFI** mode. The graphical installer
starts on its own (`system/shell/installer.qml` in cage): keyboard and language, Wi-Fi, disk and
encryption, account, time zone (guessed from the network), appearance, developer tools, a review
page (with the drivers it will download for this computer), then progress. It works with a mouse,
the keyboard alone (Tab, Space, Return, Esc) or a finger (its own on-screen keyboard). If the screen can't show it, the text installer runs instead.

## Test in a VM

```bash
test/vm.sh install    # unattended install into test/disk.qcow2 (user memora / memora)
test/vm.sh run        # boot it in a GPU-accelerated window
test/vm.sh live       # boot the ISO in a window and use the real installer
RES=1366x768 test/vm.sh run   # another screen size (2560x1080, 1080x1920…)
VM=dev test/vm.sh install && VM=dev test/vm.sh dev   # second disk that runs system/ live from this checkout
```

## The desktop

Everything you see is the Memora shell (`system/shell`, Quickshell/QML), one design system:

| Part | What it does |
|---|---|
| Menu bar | System menu, the focused app's name, File / Edit / View / Go / Window / Help (they send the standard shortcuts, so they work in any app), status icons, clock |
| Dock | Pinned and running apps with magnification, running dots, bounce on launch, minimized windows, Downloads, Trash, right-click menus; bottom, left or right; always fits the screen; hides when a window needs the room (automatic on small screens) |
| Apps | A glass library rising from the Dock: search, most used, apps grouped by kind (tap Super, or the grid in the Dock) |
| Memora AI | A notch in the middle of the menu bar that unfolds into a conversation (Super+A); drag files onto it to convert them (pictures, videos, sound, PDF), compress, resize, combine into a PDF, copy the text in them, zip, extract or share, then drag the result out |
| Widgets | Clock, World Clock, Weather, Calendar, Up Next, Reminders, Batteries, Photos, Stocks, Now Playing, Notes and System on the desktop, small, medium or large; right-click the desktop > Edit Widgets |
| Screens | Extend, mirror, one screen only (Super+P, or by itself when a screen is plugged in); each screen starts at its own scale (from pixel density), Text size from Larger Text to More Space; windows go back to a screen plugged in again |
| Windows | Docking by dragging (edges, corners, a layouts bar shaped for the screen: small, wide, ultrawide, portrait), Snap Assist, a shared line to resize docked windows, Arrange All (Super+Alt+A), Keep on Top, move to another screen (Super+Shift+arrows), the window menu (right-click a title bar, Alt+Space); apps reopen where you left them, new windows cascade, dialogs open over their window, Picture in Picture sits in a corner |
| Mission Control | Every desktop and its windows (Super+S, F3, three fingers up): type to find a window, × to close, drop on + for a new desktop, name desktops; App Exposé for one app (Ctrl+Super+↓); Show Desktop slides windows aside (Super+D); Hot Corners |
| Touch | Edge swipes and three/four-finger gestures, bigger targets under a finger, dragging windows by their title bars, an on-screen keyboard for tapped text fields, rotation on 2-in-1s |
| Spotlight | Apps, files, settings, maths, ask the AI (Super+Space); also clipboard history and keyboard shortcuts |
| Control Center | Wi-Fi, Bluetooth, Focus, appearance, display, sound, media, power |
| Notifications | Banners, and Notification Center with a calendar (click the clock) |
| Lock and login | Same face: time, person, password field; login runs in greetd + cage |
| Dialogs | Administrator password (polkit), volume and brightness |
| Switching | Super+Tab: apps (Q quits, H hides, ` shows its windows); Alt+Tab: windows with live pictures; Super+`: the app's windows; hold Super to see the shortcuts |

Apps: **System Settings** (`memora-settings [pane]`), **Files**, **Notes**, **Calendar** (day, week, month and year,
calendars in their own colours, your country's public holidays, events typed the way you'd say them,
dragged to another day or time, search, reminders from the desktop), **Photos**, **Player** (films and music), **App Store** (curated Flathub apps plus AI coding agents and developer toolchains, per user),
**Archives** (`memora-archive`: opens zip, rar/rar5, 7z, tar.gz/xz/zst/bz2, iso, dmg, cab, msi, deb, rpm, wim and more, multi-part ones too; browse, search, open or drag out single files, extract all or some, check for damage; makes zip, 7z, RAR (with RARLAB's rar, fetched in one click) and tar.* with a password, hidden names and parts; adds to and deletes from zip, 7z, tar and RAR; built on 7-Zip, unrar and bsdtar), **Activity Monitor**, **Welcome**, all in the same style. Terminal is Ghostty with Memora's light and dark themes. Anything that
can't be undone (shut down, restart, log out, emptying the Trash, deleting forever) asks first.

Liquid glass is configurable in System Settings > Appearance: Clear or Tinted, transparency, frost
(Hyprland blur), colour through glass, edge light, Reduce Transparency, and the accent colour.
System Settings > Reset puts the settings back to how they came, or erases the computer (home folder,
added apps, saved networks) and restarts into a new home; the account stays.
Wallpapers: **Ember** (default, warm) and **Tide** are lit per pixel by `tools/flow.py`; Horizon,
Dunes and Silk are drawn as SVG. The playful sets, **Sorbet** (warm), **Lagoon** (cool), **Petal**
and **Bubbles**, are soft 3D shapes lit per pixel by `tools/play.py`. All are 8K, in light and dark.
GTK apps get round window buttons, and windows float with deep shadows; Super+T tiles one.
Icons are Memora's own (`tools/icons.py`); apps without one are placed on the same squircle tile.

## Memora AI

`memora-ai` (Super+A, the sparkle in the menu bar, or `?? question` in the terminal).
Set it up in System Settings > Memora AI:

- **DeepSeek** (its Anthropic-compatible API, default `deepseek-chat`): the same tools, without web search
- **Claude** through the Anthropic API (default `claude-opus-5-5`): uses tools — runs commands, reads and
  writes files, opens apps, changes settings, manages windows, looks at the screen and clicks or types,
  searches and reads the web, remembers things you tell it
- **Claude Code** with your Claude account (its own tools)
- **Ollama** or any **OpenAI-compatible** server (chat only)

Risky actions (administrator commands, deleting or replacing files, installing software, stopping
services, reading passwords and keys, changing what runs at login, sending data to another computer,
a desktop widget that runs commands) wait for **Allow**. The gravest (erasing disks, deleting the
system or your home folder, removing core packages) show a red warning first. An administrator
command goes through Memora's password dialog, and only that command runs as administrator
(`ai/shims/sudo`), not the rest of the line.

## Updates and security

- **Software Update** (System Settings, or the Memora menu) lists what's new and installs it with one
  password prompt: system packages (pacman), App Store apps (Flathub) and, when an update address is
  configured, Memora itself. A snapshot is taken before every system update.
- A background check (`memora-update-check.timer`, user) posts a notification when updates are waiting.
- Memora's own updates come from `URL=` in `/etc/memora/update.conf` and are installed only when signed
  by a key in `system/keys/*.asc` (build one with `tools/release.sh`). Without both, it is off.
- Firewall (ufw) on from the first boot: nothing may connect in. Kernel and network hardening
  (`/etc/sysctl.d/90-memora.conf`), remote login off (and keys-only if turned on), private home folders,
  a short lock-out after 5 wrong passwords.
- System Settings > Privacy & Security: firewall, disk encryption status, lock and sleep timing,
  whether Memora AI may see and use the screen, clearing clipboard history.
- Administrator actions from Settings and the App Store go through `memora-admin` with their own polkit
  actions, so the password dialog says in plain words what will happen. It takes words from a fixed
  list only (`firewall on`, `software install docker`), never a command or an address.
- The installer writes only the hash of your password to the new disk.
- Nearby Share takes exactly the files you accepted (name and size), one question at a time; a
  LocalSend device you trusted is checked against its certificate before it may send without asking.

## What gets installed

| Part | Choice |
|---|---|
| Disk | GPT, 2 GiB EFI, btrfs (`@`, `@home`, `@log`, `@pkg`, `@snapshots`), optional LUKS2 |
| Boot | systemd-boot, Plymouth splash, zram swap |
| Snapshots | snapper + snap-pac (one before every pacman transaction) |
| Login | greetd with the Memora login screen; straight to the desktop after the disk password when encrypted |
| Session | Hyprland (Lua config) via uwsm, Memora shell |
| Drivers | Picked from `lspci`: NVIDIA open driver (DKMS) for Turing and later, open-source driver for older NVIDIA cards; AMD, Intel, VM; 32-bit drivers for games. Laptops with two chips keep the desktop on the built-in one and run games on NVIDIA (`memora-gpu`) |
| Gaming (optional) | Steam with Proton, GameMode, MangoHud, ProtonPlus |

## Layout

```
build.sh, builder/   ISO build (Docker + archiso releng overlay)
iso/                 live ISO overlay: installer, boot, motd
system/              installed to /usr/share/memora
  shell/             the shell, login, Settings, AI and Welcome windows (QML)
  ai/agent.py        Memora AI agent (Anthropic SDK)
  bin/               memora, memora-shell, memora-ai, memora-settings, memora-theme, ...
  default/hypr/      Hyprland defaults (Lua), updated with the system
  icons/             Memora icon theme (generated)
  themes/            light, dark (colours, wallpaper, logo)
  install/           chroot and user setup run by the installer
test/vm.sh           QEMU harness
tools/               gen-art.sh (logos, wallpapers, icons), silk.py, play.py, icons.py
```

Personal Hyprland changes go in `~/.config/hypr/user.lua`; it loads last.

## License

MIT
