#!/usr/bin/env bash
# Dependencies: bash>=3.2, coreutils, file, gawk, iproute2

readonly DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Icon path
readonly ICON="${DIR}/icons/network/globe.svg"

# Default routing interface (auto-detected — no hardcoded wlp3s0)
readonly INTERFACE="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"

# Offline — show a muted state and bail out cleanly
if [[ -z "$INTERFACE" ]] || [[ ! -d "/sys/class/net/${INTERFACE}" ]]; then
  echo -ne "<txt> Offline</txt><tool>No default route — offline</tool>"
  exit 0
fi

# Local IPv4 addresses for the tooltip
readonly TOOLTIP="$(ip -4 addr show dev "$INTERFACE" 2>/dev/null | awk '/inet /{print $2}' | paste -sd ' ')"

INTF_DIR="/sys/class/net/${INTERFACE}"

PTX=$(awk '{print $1}' "${INTF_DIR}/statistics/tx_bytes")
PRX=$(awk '{print $1}' "${INTF_DIR}/statistics/rx_bytes")
sleep 1
CTX=$(awk '{print $1}' "${INTF_DIR}/statistics/tx_bytes")
CRX=$(awk '{print $1}' "${INTF_DIR}/statistics/rx_bytes")

BTX=$(( CTX - PTX ))
BRX=$(( CRX - PRX ))

fmt_rate() {
  awk -v b="$1" 'BEGIN {
    n = b; p = 0;
    while (n > 1024) { n = n / 1024; p++ }
    u = (p==0) ? "B/s" : ((p==1) ? "KB/s" : ((p==2) ? "MB/s" : "GB/s"));
    printf "%.2f %s", n, u
  }'
}

RX=$(fmt_rate "${BRX}")
TX=$(fmt_rate "${BTX}")

# Panel
if [[ $(file -b "${ICON}") =~ PNG|SVG ]]; then
  INFO="<img>${ICON}</img>"
  if command -v xfce4-taskmanager &> /dev/null; then
    INFO+="<click>xfce4-taskmanager</click>"
  fi
  INFO+="<txt>"
else
  INFO="<txt>"
fi
INFO+=" ▼${RX} ▲${TX}"
INFO+="</txt>"

# Tooltip
MORE_INFO="<tool>"
MORE_INFO+="Interface: ${INTERFACE}\n"
MORE_INFO+="IPv4: ${TOOLTIP:-none}\n"
MORE_INFO+="Download: ${RX}\n"
MORE_INFO+="Upload: ${TX}"
MORE_INFO+="</tool>"

# Panel Print
echo -e "${INFO}"

# Tooltip Print
echo -e "${MORE_INFO}"