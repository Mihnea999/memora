# Memora

A desktop operating system based on Arch Linux and Hyprland, with a liquid-glass look in light and dark,
its own shell and apps, and an AI assistant that can work on the computer for you.
JetBrains Mono everywhere.

## Build the ISO

Requires Docker. The build runs `mkarchiso` in a privileged Arch container.

```bash
./build.sh            # → out/memora-<version>-<date>-x86_64.iso
```

Write it to a USB stick (`dd` or Ventoy) and boot it in **UEFI** mode. The graphical installer
starts on its own (`system/shell/installer.qml` in cage): keyboard and language, Wi-Fi, disk and
encryption, account, time zone (guessed from the network), appearance, developer tools, a review
page, then progress. If the screen can't show it, the text installer runs instead.

## Test in a VM

```bash
test/vm.sh install    # unattended install into test/disk.qcow2 (user memora / memora)
test/vm.sh run        # boot it in a GPU-accelerated window
test/vm.sh live       # boot the ISO in a window and use the real installer
VM=dev test/vm.sh install && VM=dev test/vm.sh dev   # second disk that runs system/ live from this checkout
```

## The desktop

Everything you see is the Memora shell (`system/shell`, Quickshell/QML), one design system:

| Part | What it does |
|---|---|
| Menu bar | System menu, the focused app's name, File / Edit / View / Go / Window / Help (they send the standard shortcuts, so they work in any app), status icons, clock |
| Dock | Pinned and running apps with magnification, running dots, bounce on launch, minimized windows, Downloads, Trash, right-click menus |
| Launchpad | All apps in pages, with search (tap Super, or the grid in the Dock) |
| Spotlight | Apps, files, settings, maths, ask the AI (Super+Space); also clipboard history and keyboard shortcuts |
| Control Center | Wi-Fi, Bluetooth, Focus, appearance, display, sound, media, power |
| Notifications | Banners, and Notification Center with a calendar (click the clock) |
| Lock and login | Same face: time, person, password field; login runs in greetd + cage |
| Dialogs | Administrator password (polkit), volume and brightness |
| Alt+Tab | Window switcher |

Apps: **System Settings** (`memora-settings [pane]`), **Files**, **Notes**, **App Store** (curated Flathub
apps, per user), **Activity Monitor**, **Memora AI**, **Welcome**, all in the same style. Anything that
can't be undone (shut down, restart, log out, emptying the Trash, deleting forever) asks first.

Liquid glass is configurable in System Settings > Appearance: Clear or Tinted, transparency, frost
(Hyprland blur), colour through glass, edge light, Reduce Transparency, and the accent colour.
Wallpapers: **Ember** (default, warm) and **Tide** are lit per pixel by `tools/flow.py`; Horizon,
Dunes and Silk are drawn as SVG. All are 8K, in light and dark.
GTK apps get round window buttons, and windows float with deep shadows; Super+T tiles one.
Icons are Memora's own (`tools/icons.py`); apps without one are placed on the same squircle tile.

## Memora AI

`memora-ai` (Super+A, the sparkle in the menu bar, or `?? question` in the terminal).
Set it up in System Settings > Memora AI:

- **Claude** through the Anthropic API (default `claude-opus-5-5`): uses tools — runs commands, reads and
  writes files, opens apps, changes settings, manages windows, looks at the screen and clicks or types,
  searches and reads the web, remembers things you tell it
- **Claude Code** with your Claude account (its own tools)
- **Ollama** or any **OpenAI-compatible** server (chat only)

Risky actions (administrator commands, deleting or replacing files, installing software, stopping
services) wait for **Allow**. The gravest (erasing disks, deleting the system or your home folder,
removing core packages) show a red warning first. Administrator commands go through Memora's password dialog.

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
- Administrator actions from Settings go through `memora-admin` with their own polkit actions, so the
  password dialog says in plain words what will happen.

## What gets installed

| Part | Choice |
|---|---|
| Disk | GPT, 2 GiB EFI, btrfs (`@`, `@home`, `@log`, `@pkg`, `@snapshots`), optional LUKS2 |
| Boot | systemd-boot, Plymouth splash, zram swap |
| Snapshots | snapper + snap-pac (one before every pacman transaction) |
| Login | greetd with the Memora login screen; straight to the desktop after the disk password when encrypted |
| Session | Hyprland (Lua config) via uwsm, Memora shell |
| Drivers | Picked from `lspci`: NVIDIA (open), AMD, Intel, VM |

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
tools/               gen-art.sh (logos, wallpapers, icons), silk.py, icons.py
```

Personal Hyprland changes go in `~/.config/hypr/user.lua`; it loads last.

## License

MIT
