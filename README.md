# Memora

An Arch Linux based desktop with a glass look, a dock, and an AI assistant built in.
Hyprland (Lua config), waybar, nwg-dock, fuzzel, mako, kitty, JetBrains Mono everywhere.

## Build the ISO

Requires Docker. The build runs `mkarchiso` in a privileged Arch container.

```bash
./build.sh            # → out/memora-<version>-<date>-x86_64.iso
```

Write it to a USB stick (`dd` or Ventoy) and boot it in **UEFI** mode. The installer starts
on its own: keyboard, user, time zone, disk, encryption, appearance, developer tools.

## Test in a VM

```bash
test/vm.sh install    # unattended install into test/disk.qcow2 (user memora / memora)
test/vm.sh boot       # boot it headless; VNC on localhost:5905
test/vm.sh shot a.png # screenshot of the running VM
test/vm.sh live       # boot the ISO in a window and use the real installer
```

## What gets installed

| Part | Choice |
|---|---|
| Disk | GPT, 2 GiB EFI, btrfs (`@`, `@home`, `@log`, `@pkg`, `@snapshots`), optional LUKS2 |
| Boot | systemd-boot, Plymouth splash, zram swap |
| Snapshots | snapper + snap-pac (one before every pacman transaction) |
| Login | greetd; straight into the desktop after the disk password when encrypted |
| Desktop | Hyprland via uwsm, waybar top bar, nwg-dock-hyprland dock, fuzzel launcher |
| Drivers | Picked from `lspci`: NVIDIA (open), AMD, Intel, VM |

## Keys

| Keys | Action |
|---|---|
| Super+Space | Launcher |
| Super+Return | Terminal |
| Super+A | Memora AI |
| Super+M | Memora menu |
| Super+K | All keybindings |
| Super+T | Switch light / dark |
| Super+Q | Close window |
| Super+1…0 | Workspaces |
| Print | Screenshot region |

## Memora AI

`memora-ai setup` picks where it runs:

- **Claude** through the Anthropic API (default model `claude-opus-5-5`)
- **Claude Code** with your Claude account
- **Ollama** locally, private and offline (model sized to RAM)
- any **OpenAI-compatible** endpoint (LM Studio, OpenRouter)

It knows the system it runs on, keeps a memory file you control
(`memora-ai remember …`, `memora-ai memory`), and can run the command block from its last
answer after you confirm (`/run`). In the shell: `?? question`, `cmd 2>&1 | ?? explain`, `wtf`.

## Layout

```
build.sh, builder/   ISO build (Docker + archiso releng overlay)
iso/                 live ISO overlay: installer, boot, motd
system/              installed to /usr/share/memora
  bin/               memora, memora-ai, memora-theme, memora-menu, ...
  default/hypr/      Hyprland defaults (Lua), updated with the system
  config/            files copied once into ~/.config
  templates/         theme templates rendered by memora-theme
  themes/            light, dark (colors, wallpaper, logo)
  install/           chroot and user setup run by the installer
test/vm.sh           QEMU harness
tools/gen-art.sh     renders logos and wallpapers
```

Personal changes go in `~/.config/hypr/user.lua`; it loads last.

## License

MIT
