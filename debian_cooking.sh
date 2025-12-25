#!/usr/bin/env bash
set -euo pipefail

DEBUG="${DEBUG:-0}"
log() { echo "[debian_cooking] $*" >&2; }
dbg() { [[ "$DEBUG" == "1" ]] && echo "[DEBUG] $*" >&2 || true; }
run() { dbg "+ $*"; "$@"; }

CMD="${1:-}"
IMG="${2:-}"

MNT="/mnt/rootfs"
STATE_DIR="/tmp/debian_cooking"
mkdir -p "$STATE_DIR"

die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo $0 ..."; }
need_file() { [[ -f "$IMG" ]] || die "Image not found: $IMG"; }

hash_img() { echo -n "$IMG" | sha256sum | awk '{print $1}'; }
state_file() { echo "$STATE_DIR/$(hash_img).state"; }

get_loop_for_img() {
  losetup -j "$IMG" | head -n1 | cut -d: -f1 || true
}

set_state_loop() {
  local loop="$1"
  printf '%s\n' "$loop" > "$(state_file)"
}

get_state_loop() {
  local f
  f="$(state_file)"
  [[ -f "$f" ]] || return 1
  cat "$f"
}

clear_state() {
  rm -f "$(state_file)" || true
}

ensure_loop() {
  local loop
  loop="$(get_loop_for_img)"
  if [[ -n "$loop" ]]; then
    echo "$loop"
    return 0
  fi
  loop="$(losetup --show -Pf "$IMG")"
  partprobe "$loop" || true
  udevadm settle || true
  set_state_loop "$loop"
  echo "$loop"
}

detach_loop() {
  local loop="$1"
  if [[ -n "$loop" ]]; then
    losetup -d "$loop" || true
  fi
}

is_mounted() {
  mountpoint -q "$1"
}

umount_if_mounted() {
  local p="$1"
  if is_mounted "$p"; then
    umount "$p"
  fi
}

get_sector_size() {
  local loop="$1"
  blockdev --getss "$loop"
}

get_part2_start_sector() {
  local loop="$1"
  parted -ms "$loop" unit s print | awk -F: '$1=="2"{gsub(/s/,"",$2); print $2}'
}

get_part2_end_sector() {
  local loop="$1"
  parted -ms "$loop" unit s print | awk -F: '$1=="2"{gsub(/s/,"",$3); print $3}'
}

bytes_to_sectors_ceil() {
  local bytes="$1" ss="$2"
  echo $(( (bytes + ss - 1) / ss ))
}

extend_cmd() {
  need_root
  need_file

  local default="150M"
  read -r -p "Extend rootfs (partition 2) by how much? [${default}]: " inc
  inc="${inc:-$default}"

  local loop p2 old_size new_size
  loop="$(ensure_loop)"
  p2="${loop}p2"

  [[ -b "$p2" ]] || die "Missing partition node: $p2"

  old_size="$(stat -c%s "$IMG")"
  truncate -s +"$inc" "$IMG"
  sudo losetup -c "$loop"
  sudo partprobe "$loop" || true
  sudo udevadm settle || true
  new_size="$(stat -c%s "$IMG")"

  partprobe "$loop" || true
  udevadm settle || true

  parted -s "$loop" unit s resizepart 2 100% >/dev/null
  partprobe "$loop" || true
  udevadm settle || true

  e2fsck -f -y "$p2" >/dev/null
  resize2fs "$p2" >/dev/null

  detach_loop "$loop"
  clear_state

  echo "Extended: $IMG"
  echo "Size: $old_size -> $new_size bytes"
}

mount_cmd() {
  need_root
  need_file

  local loop p2
  loop="$(ensure_loop)"
  p2="${loop}p2"

  [[ -b "$p2" ]] || die "Missing partition node: $p2"

  mkdir -p "$MNT"
  mount "$p2" "$MNT"

  mkdir -p "$MNT/usr/bin"
  if [[ -x /usr/bin/qemu-arm-static ]]; then
    cp -f /usr/bin/qemu-arm-static "$MNT/usr/bin/" || true
  fi

  mkdir -p "$MNT/dev" "$MNT/sys" "$MNT/proc"
  mount -o bind /dev "$MNT/dev"
  mount -o bind /sys "$MNT/sys"
  mount -t proc proc "$MNT/proc"

  echo 'Use chroot /mnt/rootfs /bin/bash to edit the rootfs'
}

umount_cmd() {
  need_root
  need_file

  local loop
  loop="$(get_loop_for_img)"
  if [[ -z "$loop" ]]; then
    loop="$(get_state_loop 2>/dev/null || true)"
  fi

  umount_if_mounted "$MNT/dev"
  umount_if_mounted "$MNT/sys"
  umount_if_mounted "$MNT/proc"
  umount_if_mounted "$MNT"

  if [[ -n "$loop" ]]; then
    detach_loop "$loop"
  fi
  clear_state
}

parted_yes() { parted -s ---pretend-input-tty "$@" <<< $'Yes\n'; }


shrink_cmd() {
  need_root
  need_file

  local padding_mb=30
  local padding_bytes=$((padding_mb * 1024 * 1024))

  if is_mounted "$MNT" || is_mounted "$MNT/dev" || is_mounted "$MNT/sys" || is_mounted "$MNT/proc"; then
    die "Rootfs is mounted at $MNT. Run: sudo $0 umount $IMG"
  fi

  local existing
  existing="$(get_loop_for_img)"
  if [[ -n "$existing" ]]; then
    die "Image already attached to $existing. Run: sudo $0 umount $IMG"
  fi

  log "IMG      = $IMG"
  log "IMG size = $(stat -c%s "$IMG") bytes"

  local loop p2 ss start end fs_block_size fs_blocks fs_bytes target_part_bytes target_sectors target_end new_img_bytes
  loop="$(ensure_loop)"
  p2="${loop}p2"

  log "LOOP     = $loop"
  run losetup -l | grep -F "$loop" || true
  run parted -ms "$loop" unit s print

  ss="$(get_sector_size "$loop")"
  log "SECTORSZ = $ss bytes"

  [[ -b "$p2" ]] || die "Missing partition node: $p2"

  run e2fsck -f -y "$p2" >/dev/null
  run resize2fs -M "$p2" >/dev/null

  fs_block_size="$(dumpe2fs -h "$p2" 2>/dev/null | awk -F: '/Block size/{gsub(/ /,"",$2); print $2}')"
  fs_blocks="$(dumpe2fs -h "$p2" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')"
  [[ -n "$fs_block_size" && -n "$fs_blocks" ]] || die "Failed to read filesystem size from dumpe2fs"

  fs_bytes=$((fs_block_size * fs_blocks))
  target_part_bytes=$((fs_bytes + padding_bytes))
  target_sectors="$(bytes_to_sectors_ceil "$target_part_bytes" "$ss")"

  start="$(get_part2_start_sector "$loop")"
  [[ -n "$start" ]] || die "Failed to read partition 2 start sector"

  target_end=$((start + target_sectors - 1))

  log "p2 start sector = $start"
  log "target sectors  = $target_sectors"
  log "target end sect = $target_end"
  log "fs bytes(min)   = $fs_bytes"
  log "pad bytes       = $padding_bytes"
  log "part bytes tgt  = $target_part_bytes"

  # Force non-interactive confirmation for shrink warning
  echo Yes | parted ---pretend-input-tty "$loop" unit s resizepart 2 "${target_end}s"

  run partprobe "$loop" || true
  run udevadm settle || true

  run parted -ms "$loop" unit s print

  end="$(get_part2_end_sector "$loop")"
  [[ -n "$end" ]] || die "Failed to read partition 2 end sector after resize"
  new_img_bytes=$(((end + 1) * ss))

  log "p2 end sector   = $end"
  log "new img bytes   = $new_img_bytes"

  run losetup -d "$loop"
  clear_state

  local before after
  before="$(stat -c%s "$IMG")"
  run truncate -s "$new_img_bytes" "$IMG"
  after="$(stat -c%s "$IMG")"

  log "truncate: $before -> $after bytes"

  if [[ "$after" -ge "$before" ]]; then
    log "NOTE: image size didn't decrease. That means partition 2 still ends near EOF (end sector calculation ~= old)."
    log "Dumping partition table from image file for inspection:"
    run parted -ms "$IMG" unit s print || true
  fi
}
case "$CMD" in
  extend) extend_cmd ;;
  mount)  mount_cmd ;;
  umount) umount_cmd ;;
  shrink) shrink_cmd ;;
  *) die "Usage: sudo $0 {extend|mount|umount|shrink} /path/to/armbian.img" ;;
esac
