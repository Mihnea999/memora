#!/usr/bin/env bash
# Runs inside arch-chroot on the target. Settings come from /root/memora.env,
# written by memora-install.
set -euo pipefail
# shellcheck disable=SC1091
source /root/memora.env
MEMORA_PATH=/usr/share/memora

step() { printf '\n\e[38;5;179m==>\e[0m %s\n' "$*"; }
# pacman, again after a pause if the network drops for a moment (Wi-Fi
# re-authenticating, a mirror timing out).
pac() {
  local i
  for i in 1 2 3; do
    pacman "$@" && return 0
    [[ $i == 3 ]] || { echo "pacman: network trouble, trying again in 15 s"; sleep 15; }
  done
  return 1
}

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
# Not in "input": that group can read every key typed, in any app.
groupadd -f -r memora-input
useradd -m -G wheel,video,audio,memora-input -s /bin/bash -c "$MEMORA_FULLNAME" "$MEMORA_USER"
printf '%s:%s\n' "$MEMORA_USER" "$MEMORA_PASSWORD" | chpasswd
printf 'root:%s\n' "$MEMORA_PASSWORD" | chpasswd
passwd -l root >/dev/null
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
echo 'Defaults passwd_timeout=0, timestamp_type=global, lecture=never' > /etc/sudoers.d/20-memora
chmod 440 /etc/sudoers.d/*

step "Graphics"
# 32-bit libraries (multilib) are needed by Steam and by games' graphics drivers.
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
fi
pac -Sy --noconfirm >/dev/null
gpu="$(lspci -nn | grep -iE 'vga|3d|display' || true)"
# steam-devices: permissions for game controllers (Steam from the App Store asks for it).
gfx=(mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader vulkan-mesa-layers steam-devices)
igpu=0
grep -qE 'AMD|ATI|Radeon' <<<"$gpu" && { gfx+=(vulkan-radeon lib32-vulkan-radeon libva-mesa-driver); igpu=1; }
grep -qi intel <<<"$gpu" && { gfx+=(vulkan-intel lib32-vulkan-intel intel-media-driver); igpu=1; }
grep -qi 'virtio\|qxl\|vmware\|bochs' <<<"$gpu" && gfx+=(vulkan-swrast)
if grep -qi nvidia <<<"$gpu"; then
  # Turing (GTX 16 / RTX 20) and newer: NVIDIA's open kernel modules, built for
  # every kernel by DKMS, so the newest driver follows each system update.
  # Older cards: the open-source driver (the current NVIDIA driver no longer
  # supports them).
  if grep -qE '\b(TU|GA|GH|AD|GB)[0-9]{3}|RTX|GTX 16[0-9]{2}|\[10de:(1e|1f|2[0-9a-f])' <<<"$gpu"; then
    gfx+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland libva-nvidia-driver opencl-nvidia)
    touch /etc/memora/nvidia
    printf 'options nvidia_drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp\n' > /etc/modprobe.d/nvidia.conf
    # Laptops with a second, built-in graphics chip: the desktop runs on that,
    # games are sent to the NVIDIA card (prime-run).
    if [[ $igpu == 1 ]]; then gfx+=(nvidia-prime); touch /etc/memora/hybrid; fi
  else
    gfx+=(vulkan-nouveau lib32-vulkan-nouveau)
    touch /etc/memora/nvidia-legacy
  fi
fi
pac -S --needed --noconfirm "${gfx[@]}"
if [[ -f /etc/memora/nvidia ]]; then
  systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true
fi

step "Optional toolkits"
user_kits=""
for t in $MEMORA_TOOLKITS; do
  case "$t" in
    docker)
      pac -S --needed --noconfirm docker docker-compose docker-buildx
      systemctl enable docker.service
      usermod -aG docker "$MEMORA_USER" ;;
    ollama)
      if grep -qi nvidia <<<"$gpu"; then o=ollama-cuda
      elif grep -qE 'AMD|ATI|Radeon' <<<"$gpu"; then o=ollama-rocm
      else o=ollama; fi
      pac -S --needed --noconfirm "$o"
      systemctl enable ollama.service ;;
    android) pac -S --needed --noconfirm android-tools jdk17-openjdk ;;
    flutter) pac -S --needed --noconfirm jdk17-openjdk clang cmake ninja pkgconf gtk3; user_kits+=" flutter" ;;
    rust) pac -S --needed --noconfirm rustup; user_kits+=" rust" ;;
    gaming)
      # Steam (with Proton for Windows games), GameMode and the MangoHud overlay;
      # ProtonPlus (newer Proton builds) comes from the App Store in user.sh.
      pac -S --needed --noconfirm steam gamemode lib32-gamemode mangohud lib32-mangohud
      usermod -aG gamemode "$MEMORA_USER" 2>/dev/null || true
      user_kits+=" gaming" ;;
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
# Firewall on from the first boot: nothing may connect in, everything may go out.
sed -i 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/' /etc/default/ufw 2>/dev/null || true
sed -i 's/^DEFAULT_OUTPUT_POLICY=.*/DEFAULT_OUTPUT_POLICY="ACCEPT"/' /etc/default/ufw 2>/dev/null || true
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf 2>/dev/null || true
# Nearby Share (LocalSend, port 53317) gets through from the local network
# only; a unit adds the rules at boot (ufw can't change rules inside the chroot).
install -Dm644 -t /usr/lib/systemd/system $MEMORA_PATH/units/memora-nearby-firewall.service $MEMORA_PATH/units/memora-charge-limit.service
systemctl enable memora-nearby-firewall.service memora-charge-limit.service

step "Security"
# Kernel: hide kernel pointers and logs from programs, ignore spoofed and
# redirected packets, protect links in shared folders.
cat > /etc/sysctl.d/90-memora.conf <<'SYSCTL'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
SYSCTL
# Remote login stays off; if someone turns it on, never as root and only with keys.
mkdir -p /etc/ssh/sshd_config.d
printf 'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/10-memora.conf
# Wrong passwords: a short pause after 5 tries, so guessing is slow but you are never locked out for long.
sed -i -e 's/^#\? *deny *=.*/deny = 5/' -e 's/^#\? *unlock_time *=.*/unlock_time = 120/' /etc/security/faillock.conf 2>/dev/null || true
# Private home folders.
sed -i 's/^#\?HOME_MODE.*/HOME_MODE 0700/' /etc/login.defs
# Firmware updates for laptops and peripherals (System Settings > Software Update).
systemctl enable fwupd-refresh.timer 2>/dev/null || true
# Virtual pointer and keyboard for Memora AI's screen tools; only its socket is
# shared (group memora-input), not the keyboards themselves.
cat > /etc/systemd/system/memora-ydotoold.service <<UNIT
[Unit]
Description=Virtual input for Memora AI

[Service]
ExecStart=/usr/bin/ydotoold --socket-path=/run/memora-ydotool.sock --socket-own=0:$(getent group memora-input | cut -d: -f3) --socket-perm=0660
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable memora-ydotoold.service
# Keeps Windows and other systems in the startup menu.
cat > /etc/systemd/system/memora-bootsync.service <<'UNIT'
[Unit]
Description=Keep other systems in the startup menu
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/memora-bootsync

[Install]
WantedBy=multi-user.target
UNIT
# Plain-words password prompts for the changes System Settings makes.
install -Dm644 $MEMORA_PATH/polkit/org.memora.admin.policy /usr/share/polkit-1/actions/org.memora.admin.policy
# Drives open from Files without a password prompt each time (memora-drives).
install -Dm644 $MEMORA_PATH/polkit/50-memora-drives.rules /etc/polkit-1/rules.d/50-memora-drives.rules
# Look for updates in the background and say when there are some.
install -Dm644 -t /usr/lib/systemd/user $MEMORA_PATH/units/memora-update-check.service $MEMORA_PATH/units/memora-update-check.timer
systemctl --global enable memora-update-check.timer

step "Login"
# One session only, named Memora (the stock Hyprland entries stay out of the list).
rm -f /usr/share/wayland-sessions/hyprland.desktop /usr/share/wayland-sessions/hyprland-uwsm.desktop
sed -i 's|^#NoExtract.*|NoExtract   = usr/share/wayland-sessions/hyprland.desktop usr/share/wayland-sessions/hyprland-uwsm.desktop|' /etc/pacman.conf
cat > /usr/share/wayland-sessions/memora.desktop <<'DESKTOP'
[Desktop Entry]
Name=Memora
Comment=Memora desktop
Exec=uwsm start -e -D Hyprland:GNOME -N Memora -- start-hyprland
Type=Application
DesktopNames=Hyprland
DESKTOP
session_cmd="memora-session"

# The login screen is part of the Memora shell (shell/greeter.qml), shown by greetd in cage.
mkdir -p /etc/greetd /var/lib/memora
printf %s "$MEMORA_USER" > /var/lib/memora/last-user
chown -R greeter:greeter /var/lib/memora
greeter_cmd="memora-greeter $MEMORA_THEME"

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
# The disk password field sits below the logo, not on top of it.
sed -i '/^DialogVerticalAlignment=/d' "$theme/memora.plymouth"
sed -i '0,/^\[two-step\]/s//[two-step]\nDialogVerticalAlignment=.72/' "$theme/memora.plymouth"
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
# Next to another system the menu lives on its EFI partition (/efi) and the
# kernels on Memora's own boot partition (/boot); otherwise both are /boot.
bootctl install
loader=/boot/loader
mountpoint -q /efi && loader=/efi/loader
mkdir -p "$loader" /boot/loader/entries /etc/memora
cmdline="rw rootflags=subvol=@ quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
if [[ $MEMORA_ENCRYPT == 1 ]]; then
  cmdline="rd.luks.name=$MEMORA_LUKS_UUID=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot $cmdline"
else
  cmdline="root=UUID=$MEMORA_ROOT_UUID $cmdline"
fi
ucode=""
[[ -f /boot/intel-ucode.img ]] && ucode+="initrd  /intel-ucode.img"$'\n'
[[ -f /boot/amd-ucode.img ]] && ucode+="initrd  /amd-ucode.img"$'\n'
cat > /boot/loader/entries/memora.conf <<EOF
title   Memora
sort-key 00-memora
linux   /vmlinuz-linux
${ucode}initrd  /initramfs-linux.img
options $cmdline
EOF
# Arch no longer builds a fallback image by default; offer it only when there is one.
[[ -f /boot/initramfs-linux-fallback.img ]] && cat > /boot/loader/entries/memora-fallback.conf <<EOF
title   Memora (fallback initramfs)
sort-key 99-memora
linux   /vmlinuz-linux
${ucode}initrd  /initramfs-linux-fallback.img
options ${cmdline/ quiet splash/}
EOF
# Other systems on this computer (Windows, other Linux) join the menu, which
# then stays up for a few seconds so there's time to pick one.
# (Checked again at every start, so a system installed later shows up too.)
others="$(memora-bootsync || true)"
systemctl enable memora-bootsync.service
timeout=2
if [[ -n $others ]]; then
  timeout=5
  # Windows keeps the hardware clock in local time; agree with it, or the
  # clock is off by hours after switching.
  if grep -q '^Windows|' /etc/memora/other-systems; then printf '0.0 0 0.0\n0\nLOCAL\n' > /etc/adjtime; fi
fi
cat > "$loader/loader.conf" <<EOF
default memora.conf
timeout $timeout
console-mode max
editor no
auto-entries no
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
