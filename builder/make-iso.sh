#!/usr/bin/env bash
# Runs inside the builder container (privileged). Produces out/memora-*.iso.
set -euo pipefail
src=/src
work=/build
prof="$work/profile"
rm -rf "$work"; mkdir -p "$work"

"$src/tools/gen-art.sh"

cp -r /usr/share/archiso/configs/releng "$prof"
cp "$src/iso/profiledef.sh" "$prof/profiledef.sh"
cat "$src/iso/packages.extra" >> "$prof/packages.x86_64"
cp -rT "$src/iso/airootfs" "$prof/airootfs"
mkdir -p "$prof/airootfs/opt"
cp -a "$src/system" "$prof/airootfs/opt/memora"
rm -f "$prof"/airootfs/opt/memora/branding/*.tpl
# mkarchiso resets modes; list every executable explicitly.
{
  echo 'file_permissions+=('
  (cd "$prof/airootfs" && find opt/memora -type f -perm -u+x) | sed 's|.*|  ["/&"]="0:0:755"|'
  echo ')'
} >> "$prof/profiledef.sh"

# Rename boot menu entries and shorten the timeout.
grep -rlZ 'Arch Linux install medium' "$prof"/{efiboot,syslinux,grub} | xargs -0 sed -i \
  -e 's/Arch Linux install medium/Memora installer/g' \
  -e 's/Boot the Arch Linux install medium/Boot the Memora installer/g'
sed -i 's/^timeout .*/timeout 5/' "$prof/efiboot/loader/loader.conf"
sed -i 's/^beep on//' "$prof/efiboot/loader/loader.conf"

# A quiet boot, as on a Mac or a PC: no menu (hold Space at power-on for it),
# no kernel or service text, the Memora logo while it starts (Plymouth).
quiet="quiet splash loglevel=3 rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0"
grep -rlZ '%KERNEL_PARAMS%' "$prof"/{efiboot,syslinux,grub} | xargs -0 sed -i "s/%KERNEL_PARAMS%/$quiet %KERNEL_PARAMS%/"
sed -i 's/^timeout .*/timeout 0/' "$prof/efiboot/loader/loader.conf"
sed -i 's/^TIMEOUT .*/TIMEOUT 1/' "$prof/syslinux/archiso_sys.cfg"
echo plymouth >> "$prof/packages.x86_64"
sed -i 's/ modconf kms / modconf /; s/ modconf / modconf kms plymouth /' "$prof/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
# The same splash as the installed system (system/install/chroot.sh).
pacman -Sy --noconfirm --needed plymouth >/dev/null
theme="$prof/airootfs/usr/share/plymouth/themes/memora"
mkdir -p "$theme" "$prof/airootfs/etc/plymouth"
cp /usr/share/plymouth/themes/spinner/*.png "$theme/"
cp "$src/system/plymouth/watermark.png" "$theme/watermark.png"
sed -e 's/^Name=.*/Name=Memora/' \
    -e "s|^ImageDir=.*|ImageDir=/usr/share/plymouth/themes/memora|" \
    -e 's/^WatermarkVerticalAlignment=.*/WatermarkVerticalAlignment=.45/' \
    -e 's/^BackgroundStartColor=.*/BackgroundStartColor=0x0a0a0c/' \
    -e 's/^BackgroundEndColor=.*/BackgroundEndColor=0x0a0a0c/' \
    /usr/share/plymouth/themes/spinner/spinner.plymouth > "$theme/memora.plymouth"
printf '[Daemon]\nTheme=memora\nShowDelay=0\n' > "$prof/airootfs/etc/plymouth/plymouthd.conf"
# The console logs in by itself without a word: no banner, no host name, no motd.
mkdir -p "$prof/airootfs/etc/systemd/system/getty@tty1.service.d"
cat > "$prof/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --noreset --noclear --noissue --nohostname --skip-login --autologin root - ${TERM}
UNIT
: > "$prof/airootfs/etc/issue"
: > "$prof/airootfs/etc/motd"

mkdir -p "$src/out"
mkarchiso -v -r -w "$work/work" -o "$src/out" "$prof"
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$src/out"
ls -lh "$src/out"
