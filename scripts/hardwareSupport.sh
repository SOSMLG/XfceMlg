#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  hardwareSupport.sh — firmware, microcode, firmware updates
#  Covers "why doesn't my WiFi/Bluetooth work" — almost always a
#  missing non-free firmware blob, not a driver bug. Inert on
#  hardware it doesn't match, so it doesn't conflict with
#  staying minimal.
#  Privilege: sudo
# ══════════════════════════════════════════════════════════════
set -euo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && err "Run this script as your normal user, not root."

command -v sudo &>/dev/null || err "sudo not found — this script needs it to install packages."

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        ok "$label already installed."
        return 0
    fi
    info "$label: installing ${to_install[*]}"
    sudo apt-get install -y "${to_install[@]}" || warn "$label: some packages failed to install (continuing)."
}

echo -e "\n${B}${W}══════ Hardware Support ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

step "1/3  WiFi/Bluetooth firmware"
if ask "Install common WiFi/Bluetooth firmware (Intel/Realtek/Atheros/Broadcom)?"; then
    install_pkgs "WiFi/Bluetooth firmware" \
        firmware-iwlwifi firmware-realtek firmware-atheros \
        firmware-brcm80211 firmware-misc-nonfree firmware-linux
fi

step "2/3  CPU microcode (auto-detected)"
if ask "Install CPU microcode updates?"; then
    VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
    case "$VENDOR" in
        GenuineIntel) info "Detected Intel CPU."; install_pkgs "Intel microcode" intel-microcode ;;
        AuthenticAMD) info "Detected AMD CPU.";   install_pkgs "AMD microcode" amd64-microcode ;;
        *) warn "Could not detect CPU vendor, skipping microcode." ;;
    esac
fi

step "3/3  fwupd (BIOS/UEFI + peripheral firmware updates)"
if ask "Install fwupd?"; then
    install_pkgs "fwupd" fwupd

    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now fwupd &>/dev/null || true
    else
        sudo service fwupd start &>/dev/null || true
    fi
    ok "fwupd installed. Check for updates with: fwupdmgr get-updates"
fi

ok "Hardware support step complete."
warn "A reboot is recommended so newly installed firmware/microcode is loaded."
