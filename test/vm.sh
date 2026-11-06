#!/usr/bin/env bash
# QEMU test harness for Memora.
#   test/vm.sh install   unattended install of out/*.iso onto test/disk.qcow2
#   test/vm.sh boot      boot the installed disk (headless, VNC :5 / screenshots)
#   test/vm.sh shot FILE take a screenshot of the running VM
#   test/vm.sh live      boot the ISO interactively in a window
set -euo pipefail
cd "$(dirname "$0")"
iso="$(ls -t ../out/memora-*.iso 2>/dev/null | head -1)"
disk=disk.qcow2
ovmf_code=/usr/share/edk2/x64/OVMF_CODE.4m.fd
ovmf_vars=/usr/share/edk2/x64/OVMF_VARS.4m.fd
mon=monitor.sock

common=(-machine q35,accel=kvm -cpu host -smp 4 -m 6G
  -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
  -drive "if=pflash,format=raw,file=vars.fd"
  -nic user,model=virtio-net-pci
  -monitor "unix:$mon,server,nowait")

case "${1:-}" in
  install)
    [[ -n $iso ]] || { echo "No ISO in out/. Run ./build.sh"; exit 1; }
    rm -f "$disk" vars.fd; qemu-img create -q -f qcow2 "$disk" 40G; cp "$ovmf_vars" vars.fd
    label="$(isoinfo -d -i "$iso" 2>/dev/null | awk -F': ' '/Volume id/ {print $2}' || true)"
    [[ -n $label ]] || label="$(blkid -s LABEL -o value "$iso")"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    bsdtar -xf "$iso" -C "$tmp" memora/boot/x86_64/vmlinuz-linux memora/boot/x86_64/initramfs-linux.img
    qemu-system-x86_64 "${common[@]}" \
      -drive "file=$disk,if=virtio,format=qcow2" -cdrom "$iso" \
      -kernel "$tmp/memora/boot/x86_64/vmlinuz-linux" -initrd "$tmp/memora/boot/x86_64/initramfs-linux.img" \
      -append "archisobasedir=memora archisolabel=$label console=ttyS0,115200 memora.auto ${EXTRA:-}" \
      -display none -serial "file:install.log" -no-reboot
    grep -q MEMORA_INSTALL_OK install.log && echo "INSTALL OK" || { echo "INSTALL FAILED, see test/install.log"; exit 1; }
    ;;
  boot)
    qemu-system-x86_64 "${common[@]}" -drive "file=$disk,if=virtio,format=qcow2" \
      ${GPU:--device virtio-vga-gl,xres=1920,yres=1080 -display egl-headless,rendernode=/dev/dri/renderD128} \
      -vnc :5 -serial "file:boot.log" &
    echo "VM started (VNC localhost:5905). Screenshot: test/vm.sh shot out.png"
    ;;
  shot)
    out="${2:-shot.png}"
    (echo "screendump $PWD/shot.ppm"; sleep 1) | socat - "UNIX-CONNECT:$mon" >/dev/null
    magick shot.ppm "$out" && rm -f shot.ppm && echo "$out"
    ;;
  key)  # test/vm.sh key "ret"  — send keys through the monitor
    shift; for k in "$@"; do (echo "sendkey $k"; sleep 0.15) | socat - "UNIX-CONNECT:$mon" >/dev/null; done ;;
  type) # test/vm.sh type "text"
    shift; s="$*"
    for ((i = 0; i < ${#s}; i++)); do
      c="${s:i:1}"
      case "$c" in
        " ") k=spc ;; "-") k=minus ;; ".") k=dot ;; "/") k=slash ;; ":") k=shift-semicolon ;;
        ";") k=semicolon ;; "|") k=shift-backslash ;; "~") k=shift-grave_accent ;; "'") k=apostrophe ;;
        '"') k=shift-apostrophe ;; ">") k=shift-dot ;; "<") k=shift-comma ;; "&") k=shift-7 ;; '$') k=shift-4 ;;
        "_") k=shift-minus ;; "=") k=equal ;; ",") k=comma ;; "*") k=shift-8 ;; "(") k=shift-9 ;; ")") k=shift-0 ;;
        "?") k=shift-slash ;; "#") k=shift-3 ;; "+") k=shift-equal ;; "!") k=shift-1 ;; "\\") k=backslash ;; "[") k=bracket_left ;; "]") k=bracket_right ;;
        [A-Z]) k="shift-${c,,}" ;; *) k="$c" ;;
      esac
      (echo "sendkey $k"; sleep 0.08) | socat - "UNIX-CONNECT:$mon" >/dev/null
    done ;;
  stop) (echo quit; sleep 0.5) | socat - "UNIX-CONNECT:$mon" >/dev/null || true ;;
  live)
    cp -n "$ovmf_vars" vars.fd 2>/dev/null || true
    qemu-system-x86_64 "${common[@]}" -cdrom "$iso" -drive "file=$disk,if=virtio,format=qcow2" \
      -device virtio-vga-gl -display gtk,gl=on ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
