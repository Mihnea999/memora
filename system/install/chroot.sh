#!/usr/bin/env bash
# Runs inside arch-chroot on the target. Settings come from /root/memora.env,
# written by memora-install.
set -euo pipefail
# shellcheck disable=SC1091
source /root/memora.env
MEMORA_PATH=/usr/share/memora

step() { printf '\n\e[38;5;179m==>\e[0m %s\n' "$*"; }

step "Time, locale, hostname"
ln -sf "/usr/share/zoneinfo/$MEMORA_TIMEZONE" /etc/localtime
hwclock --systohc || true
sed -i "s/^#\(en_US.UTF-8 UTF-8\)/\1/" /etc/locale.gen
[[ $MEMORA_LOCALE != en_US.UTF-8 ]] && sed -i "s/^#\(${MEMORA_LOCALE} \)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$MEMORA_LOCALE" > /etc/locale.conf
echo "KEYMAP=$MEMORA_KEYMAP" > /etc/vconsole.conf
echo "$MEMORA_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $MEMORA_HOSTNAME.localdomain $MEMORA_HOSTNAME
EOF
systemctl enable systemd-timesyncd.service

step "Branding"
install -Dm755 $MEMORA_PATH/install/os-release.sh /usr/local/sbin/memora-os-release
/usr/local/sbin/memora-os-release
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/90-memora-os-release.hook <<'EOF'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = filesystem

[Action]
Description = Keeping Memora os-release
When = PostTransaction
Exec = /usr/local/sbin/memora-os-release
EOF
install -Dm644 $MEMORA_PATH/branding/logo.svg /usr/share/pixmaps/memora.svg
install -Dm644 $MEMORA_PATH/branding/logo.png /usr/share/pixmaps/memora.png
install -Dm644 -t /usr/share/applications $MEMORA_PATH/applications/*.desktop
install -Dm644 $MEMORA_PATH/branding/app-icon.svg /usr/share/icons/hicolor/scalable/apps/memora-ai.svg
install -Dm644 $MEMORA_PATH/branding/app-icon.png /usr/share/icons/hicolor/256x256/apps/memora-ai.png
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
# Memora icon theme: a link, so system updates bring new icons with them.
ln -sfn $MEMORA_PATH/icons/Memora /usr/share/icons/Memora
bash $MEMORA_PATH/install/apps.sh
for f in $MEMORA_PATH/bin/*; do ln -sf "$f" "/usr/local/bin/$(basename "$f")"; done
echo 'case ":$PATH:" in *":/usr/share/memora/bin:"*) ;; *) PATH="/usr/share/memora/bin:$PATH" ;; esac' > /etc/profile.d/memora.sh
mkdir -p /etc/memora
mkdir -p /etc/environment.d
echo 'MEMORA_PATH=/usr/share/memora' > /etc/environment.d/memora.conf
cat > /etc/issue <<'EOF'
Memora \r (\l)

EOF

step "User $MEMORA_USER"
useradd -m -G wheel,video,input,audio -s /bin/bash -c "$MEMORA_FULLNAME" "$MEMORA_USER"
printf '%s:%s\n' "$MEMORA_USER" "$MEMORA_PASSWORD" | chpasswd
printf 'root:%s\n' "$MEMORA_PASSWORD" | chpasswd
passwd -l root >/dev/null
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
echo 'Defaults passwd_timeout=0, timestamp_type=global' > /etc/sudoers.d/20-memora
chmod 440 /etc/sudoers.d/*

step "Graphics"
gpu="$(lspci -nn | grep -iE 'vga|3d|display' || true)"
gfx=(mesa vulkan-icd-loader)
if grep -qi nvidia <<<"$gpu"; then
  gfx+=(nvidia-open nvidia-utils egl-wayland libva-nvidia-driver)
  touch /etc/memora/nvidia
  echo 'options nvidia_drm modeset=1 fbdev=1' > /etc/modprobe.d/nvidia.conf
fi
grep -qE 'AMD|ATI|Radeon' <<<"$gpu" && gfx+=(vulkan-radeon libva-mesa-driver)
grep -qi intel <<<"$gpu" && gfx+=(vulkan-intel intel-media-driver)
grep -qi 'virtio\|qxl\|vmware\|bochs' <<<"$gpu" && gfx+=(vulkan-swrast)
pacman -S --needed --noconfirm "${gfx[@]}"

step "Optional toolkits"
user_kits=""
for t in $MEMORA_TOOLKITS; do
  case "$t" in
    docker)
      pacman -S --needed --noconfirm docker docker-compose docker-buildx
      systemctl enable docker.service
      usermod -aG docker "$MEMORA_USER" ;;
    ollama)
      if grep -qi nvidia <<<"$gpu"; then o=ollama-cuda
      elif grep -qE 'AMD|ATI|Radeon' <<<"$gpu"; then o=ollama-rocm
      else o=ollama; fi
      pacman -S --needed --noconfirm "$o"
      systemctl enable ollama.service ;;
    android) pacman -S --needed --noconfirm android-tools jdk17-openjdk ;;
    flutter) pacman -S --needed --noconfirm jdk17-openjdk clang cmake ninja pkgconf gtk3; user_kits+=" flutter" ;;
    rust) pacman -S --needed --noconfirm rustup; user_kits+=" rust" ;;
    *) user_kits+=" $t" ;;
  esac
done

step "Services"
systemctl enable NetworkManager.service bluetooth.service power-profiles-daemon.service \
  fstrim.timer systemd-resolved.service ufw.service
# /etc/resolv.conf is bind-mounted by arch-chroot; memora-install links it afterwards.
mkdir -p /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi-backend.conf
printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf
sed -i 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/' /etc/default/ufw 2>/dev/null || true
# Virtual pointer and keyboard for Memora AI's screen tools; usable by the input group.
cat > /etc/systemd/system/memora-ydotoold.service <<UNIT
[Unit]
Description=Virtual input for Memora AI

[Service]
ExecStart=/usr/bin/ydotoold --socket-path=/run/memora-ydotool.sock --socket-own=0:$(getent group input | cut -d: -f3) --socket-perm=0660
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable memora-ydotoold.service

step "Login"
# One session only, named Memora (the stock Hyprland entries stay out of the list).
rm -f /usr/share/wayland-sessions/hyprland.desktop /usr/share/wayland-sessions/hyprland-uwsm.desktop
sed -i 's|^#NoExtract.*|NoExtract   = usr/share/wayland-sessions/hyprland.desktop usr/share/wayland-sessions/hyprland-uwsm.desktop|' /etc/pacman.conf
cat > /usr/share/wayland-sessions/memora.desktop <<'DESKTOP'
[Desktop Entry]
Name=Memora
Comment=Memora desktop
Exec=uwsm start -e -D Hyprland -N Memora -- start-hyprland
Type=Application
DesktopNames=Hyprland
DESKTOP
session_cmd="uwsm start -e -D Hyprland -N Memora -- start-hyprland"

# The login screen is part of the Memora shell (shell/greeter.qml), shown by greetd in cage.
mkdir -p /etc/greetd /var/lib/memora
printf %s "$MEMORA_USER" > /var/lib/memora/last-user
chown -R greeter:greeter /var/lib/memora
greeter_cmd="cage -s -mlast -- env MEMORA_MODE=$MEMORA_THEME QS_ICON_THEME=Memora QT_WAYLAND_DISABLE_WINDOWDECORATION=1 qs -p $MEMORA_PATH/shell/greeter.qml"

{
  printf '[terminal]\nvt = 1\n\n'
  if [[ $MEMORA_ENCRYPT == 1 ]]; then
    # The disk passphrase already proves who you are: go straight to the desktop.
    printf '[initial_session]\ncommand = "%s"\nuser = "%s"\n\n' "$session_cmd" "$MEMORA_USER"
  fi
  printf '[default_session]\ncommand = "%s"\nuser = "greeter"\n' "$greeter_cmd"
} > /etc/greetd/config.toml
systemctl enable greetd.service
# The login password also unlocks the keyring, so the browser and other apps never ask for one.
grep -q pam_gnome_keyring /etc/pam.d/greetd || {
  sed -i '/^auth.*system-local-login/a auth       optional     pam_gnome_keyring.so' /etc/pam.d/greetd
  sed -i '/^session.*system-local-login/a session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/greetd
}
grep -q pam_gnome_keyring /etc/pam.d/passwd || echo 'password   optional     pam_gnome_keyring.so' >> /etc/pam.d/passwd

# Plugin that lets app minimize buttons send windows to the Dock. It is built
# against the installed Hyprland, and again after every Hyprland update.
bash $MEMORA_PATH/plugin/build.sh || echo "memora-minimize plugin failed to build (minimize buttons will do nothing)"
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/memora-plugin.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = hyprland

[Action]
Description = Rebuilding the Memora Hyprland plugin...
When = PostTransaction
Exec = /usr/bin/bash /usr/share/memora/plugin/build.sh
HOOK

# fastfetch shows Memora, not the Arch logo.
install -Dm644 $MEMORA_PATH/fastfetch/config.jsonc /etc/xdg/fastfetch/config.jsonc

# Browser: no first-run screens, passwords in the keyring, native Wayland.
mkdir -p /etc/chromium/policies/managed
cat > /etc/chromium/policies/managed/memora.json <<'JSON'
{
  "PromotionalTabsEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "PrivacySandboxPromptEnabled": false,
  "BrowserSignin": 1,
  "MetricsReportingEnabled": false,
  "ShowFullUrlsInAddressBar": false
}
JSON

step "Boot splash"
theme=/usr/share/plymouth/themes/memora
mkdir -p "$theme"
cp /usr/share/plymouth/themes/spinner/*.png "$theme/"
cp $MEMORA_PATH/plymouth/watermark.png "$theme/watermark.png"
sed -e 's/^Name=.*/Name=Memora/' \
    -e "s|^ImageDir=.*|ImageDir=$theme|" \
    -e 's/^WatermarkVerticalAlignment=.*/WatermarkVerticalAlignment=.45/' \
    -e 's/^BackgroundStartColor=.*/BackgroundStartColor=0x0a0a0c/' \
    -e 's/^BackgroundEndColor=.*/BackgroundEndColor=0x0a0a0c/' \
    /usr/share/plymouth/themes/spinner/spinner.plymouth > "$theme/memora.plymouth"
plymouth-set-default-theme memora

step "Initramfs"
hooks="base systemd autodetect microcode modconf kms keyboard sd-vconsole block"
[[ $MEMORA_ENCRYPT == 1 ]] && hooks+=" plymouth sd-encrypt" || hooks+=" plymouth"
hooks+=" filesystems fsck"
cat > /etc/mkinitcpio.conf.d/memora.conf <<EOF
HOOKS=($hooks)
EOF
[[ -f /etc/memora/nvidia ]] && echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' >> /etc/mkinitcpio.conf.d/memora.conf
mkinitcpio -P

step "Bootloader"
bootctl install
cmdline="rw rootflags=subvol=@ quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
if [[ $MEMORA_ENCRYPT == 1 ]]; then
  cmdline="rd.luks.name=$MEMORA_LUKS_UUID=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot $cmdline"
else
  cmdline="root=UUID=$MEMORA_ROOT_UUID $cmdline"
fi
ucode=""
[[ -f /boot/intel-ucode.img ]] && ucode+="initrd  /intel-ucode.img"$'\n'
[[ -f /boot/amd-ucode.img ]] && ucode+="initrd  /amd-ucode.img"$'\n'
cat > /boot/loader/loader.conf <<'EOF'
default memora.conf
timeout 2
console-mode max
editor no
EOF
cat > /boot/loader/entries/memora.conf <<EOF
title   Memora
linux   /vmlinuz-linux
${ucode}initrd  /initramfs-linux.img
options $cmdline
EOF
cat > /boot/loader/entries/memora-fallback.conf <<EOF
title   Memora (fallback initramfs)
linux   /vmlinuz-linux
${ucode}initrd  /initramfs-linux-fallback.img
options ${cmdline/ quiet splash/}
EOF
systemctl enable systemd-boot-update.service

step "Snapshots"
umount /.snapshots 2>/dev/null || true
rm -rf /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount /.snapshots
chmod 750 /.snapshots
sed -i -e 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' \
       -e 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' \
       -e 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/root
systemctl enable snapper-cleanup.timer

step "Pacman"
sed -i -e 's/^#Color/Color/' -e 's/^#ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
grep -q ILoveCandy /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf

step "Home directory"
sudo -u "$MEMORA_USER" -H env MEMORA_XKB="$MEMORA_XKB" MEMORA_THEME="$MEMORA_THEME" \
  MEMORA_ENCRYPT="$MEMORA_ENCRYPT" MEMORA_USER_TOOLKITS="$user_kits" MEMORA_SKIP_PKGS=1 bash $MEMORA_PATH/install/user.sh

rm -f /root/memora.env
step "Done"
