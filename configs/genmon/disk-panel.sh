#!/usr/bin/env bash
# Dependencies: bash>=3.2, coreutils, file, gawk
# Disk temperature is read from smartctl when available, else from
# /sys/class/thermal as a coarse proxy. No sudo required — this script
# must never prompt, or xfce4-panel will hang on a password dialog.

# Makes the script more portable
readonly DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional icon to display before the text
# Insert the absolute path of the icon
# Recommended size is 24x24 px
readonly ICON="${DIR}/icons/disk/folder.svg"

# Root filesystem device (/dev/sda, /dev/nvme0n1, ...) — strip any
# partition suffix so temp lookups hit the whole device. NVMe/mmcblk
# partitions end in pN, SATA in bare digits — handled on separate
# branches so nvme0n1p2 -> nvme0n1 (never nvme).
readonly ROOT_DEV="$(df / | awk '$1 ~ /^\/dev\//{print $1; exit}')"
readonly DISK_DEV="$(printf '%s' "$ROOT_DEV" | sed -E '/nvme|mmcblk/ { s/p[0-9]+$//; b }; s/[0-9]+$//')"

# Temperature: smartctl first, /sys/class/thermal fallback, else n/a.
# smartctl needs no privileges for most SATA/NVMe disks on Debian/Devuan,
# but can fail on some enclosures — degrade gracefully either way.
GET_TEMP="n/a"
if [[ -n "$DISK_DEV" ]] && command -v smartctl &> /dev/null; then
  TEMP=$(smartctl --json -A "$DISK_DEV" 2>/dev/null \
    | awk '/"temperature".*current/{gsub(/[^0-9]/, "", $2); print $2; exit}')
  [[ -n "$TEMP" ]] && GET_TEMP="$TEMP"
fi
if [[ "$GET_TEMP" == "n/a" ]]; then
  for ZONE in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r "$ZONE" ]] || continue
    TEMP=$(awk '{printf "%d", $1 / 1000}' "$ZONE")
    [[ -n "$TEMP" && "$TEMP" -gt 0 ]] && { GET_TEMP="$TEMP"; break; }
  done
fi

# To determine if colors are applied
OVERHEAT=0

# Panel
if [[ $(file -b "${ICON}") =~ PNG|SVG ]]; then
  INFO+="<img>${ICON}</img>"
  INFO+="<txt>"
else
  INFO+="<txt>"
fi

[[ "${GET_TEMP}" != "n/a" ]] && [[ "${GET_TEMP}" -gt 42 ]] && \
  OVERHEAT=1 && \
  INFO+="<span weight='Bold' fgcolor='#FF5D5D'>"

INFO+=" $(awk '{$1 = $1 / 1048576; printf "%.2f", $1}' <<< $(df / | awk '/\/dev/{print $3}'))"
INFO+=" GB"

# Close span tag if warning colors are applied
[[ "${OVERHEAT}" -eq 1 ]] && \
  INFO+="</span>"

INFO+=" </txt> "

# Tooltip
MORE_INFO="<tool>"
MORE_INFO+="┌ $(df -h / | awk '/\/dev/{print $1}' | head -n1)\n"
MORE_INFO+="├─ Device:\t\t${DISK_DEV:-unknown}\n"
if [[ "$DISK_DEV" == /dev/nvme* ]]; then
  NVME_CTRL="$(printf '%s' "${DISK_DEV##*/}" | sed -E 's/n[0-9]+(p[0-9]+)?$//')"
  MORE_INFO+="├─ Model:\t\t$(awk '{$1=$1; print}' "/sys/class/nvme/${NVME_CTRL}/model" 2>/dev/null)\n"
  MORE_INFO+="├─ Firmware:\t\t$(awk '{print $0}' "/sys/class/nvme/${NVME_CTRL}/firmware_rev" 2>/dev/null)\n"
else
  MORE_INFO+="├─ Vendor:\t\t$(awk '/[V]endor:/{print $2}' /proc/scsi/scsi 2>/dev/null)\n"
  MORE_INFO+="├─ Model:\t\t$(awk '/[Mm]odel:/{print $4, $5}' /proc/scsi/scsi 2>/dev/null)\n"
  MORE_INFO+="├─ Type:\t\t\t$(awk '/[Tt]ype:/{print $2, $3, $4}' /proc/scsi/scsi 2>/dev/null)\n"
fi

if [[ "$GET_TEMP" != "n/a" ]]; then
  MORE_INFO+="└─ Temperature:\t${GET_TEMP} ℃"
else
  MORE_INFO+="└─ Temperature:\tnot available"
fi

MORE_INFO+="</tool>"

# Panel Print
echo -e "${INFO}"

# Tooltip Print
echo -e "${MORE_INFO}"
