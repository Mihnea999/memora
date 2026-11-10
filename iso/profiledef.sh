#!/usr/bin/env bash
# shellcheck disable=SC2034
# Memora live/installer ISO — overlays the archiso "releng" profile.

iso_name="memora"
iso_label="MEMORA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Memora <https://github.com/Mihnea999/memora>"
iso_application="Memora installer"
iso_version="$(cat "$(dirname "${BASH_SOURCE[0]}")/airootfs/opt/memora/version")-$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="memora"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/memora-install"]="0:0:755"
  ["/usr/local/bin/memora-disks"]="0:0:755"
  ["/usr/local/bin/memora-drivers"]="0:0:755"
)
