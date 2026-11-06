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
for f in $MEMORA_PATH/bin/*; do ln -sf "$f" "/usr/local/bin/$(basename "$f")"; done
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
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
mkdir -p /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi-backend.conf
printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf
sed -i 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/' /etc/default/ufw 2>/dev/null || true

step "Login"
mkdir -p /etc/greetd
if [[ $MEMORA_ENCRYPT == 1 ]]; then
  # The disk passphrase already authenticates the user: log straight in.
  cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[initial_session]
command = "uwsm start -- hyprland.desktop"
user = "$MEMORA_USER"

[default_session]
command = "tuigreet --time --remember --asterisks --cmd 'uwsm start -- hyprland.desktop'"
user = "greeter"
EOF
else
  cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --greeting 'Memora' --cmd 'uwsm start -- hyprland.desktop'"
user = "greeter"
EOF
fi
systemctl enable greetd.service

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
mount -a
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
  MEMORA_USER_TOOLKITS="$user_kits" MEMORA_SKIP_PKGS=1 bash $MEMORA_PATH/install/user.sh

rm -f /root/memora.env
step "Done"
