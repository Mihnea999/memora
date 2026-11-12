# Once per dev disk (after `VM=dev test/vm.sh install`), in the VM's terminal:
#   echo memora | sudo -S mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/share; bash /mnt/share/dev-setup.sh
# From then on every login mounts test/share and starts dev-init.sh (logs, command loop).
mkdir -p ~/.local/bin
cat > ~/.local/bin/memora-dev-boot <<'X'
#!/bin/bash
# Dev disk only: mount the host's test/share and start dev-init (logs, command loop).
pgrep -f "bash /mnt/share/dev-init.sh" >/dev/null && exit 0
mountpoint -q /mnt/share || echo memora | sudo -S sh -c 'mkdir -p /mnt/share; mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/share'
mountpoint -q /mnt/share && exec bash /mnt/share/dev-init.sh
X
chmod +x ~/.local/bin/memora-dev-boot
grep -q memora-dev-boot ~/.config/hypr/user.lua 2>/dev/null || cat >> ~/.config/hypr/user.lua <<'X'

-- Dev VM: logs and the command loop in the host's test/share (see test/share/dev-init.sh).
hl.on("hyprland.start", function() hl.exec_cmd("sleep 3 && ~/.local/bin/memora-dev-boot") end)
X
setsid -f ~/.local/bin/memora-dev-boot >/dev/null 2>&1
