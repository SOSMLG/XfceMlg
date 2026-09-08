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
    if sudo apt-get install -y "${to_install[@]}"; then
        return 0
    else
        warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

echo -e "\n${B}${W}══════ Hardware Support ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

step "1/4  WiFi/Bluetooth firmware"
if ask "Install common WiFi/Bluetooth firmware (Intel/Realtek/Atheros/Broadcom)?"; then
    install_pkgs "WiFi/Bluetooth firmware" \
        firmware-iwlwifi firmware-realtek firmware-atheros \
        firmware-brcm80211 firmware-misc-nonfree firmware-linux
fi

step "2/4  CPU microcode (auto-detected)"
if ask "Install CPU microcode updates?"; then
    VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
    case "$VENDOR" in
        GenuineIntel) info "Detected Intel CPU."; install_pkgs "Intel microcode" intel-microcode ;;
        AuthenticAMD) info "Detected AMD CPU.";   install_pkgs "AMD microcode" amd64-microcode ;;
        *) warn "Could not detect CPU vendor, skipping microcode." ;;
    esac
fi

step "3/4  fwupd (BIOS/UEFI + peripheral firmware updates)"
if ask "Install fwupd?"; then
    install_pkgs "fwupd" fwupd

    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now fwupd &>/dev/null || true
    else
        sudo service fwupd start &>/dev/null || true
    fi
    ok "fwupd installed. Check for updates with: fwupdmgr get-updates"
fi

step "4/4  TLP (laptop power management, ThinkPad battery thresholds)"
if ask "Install TLP for battery/power tuning?"; then
    # power-profiles-daemon and TLP both try to manage the same knobs
    # (CPU governor, PCIe ASPM, etc.) — running both fights itself and
    # is a well-known source of "my settings keep reverting" reports.
    if is_installed power-profiles-daemon; then
        info "power-profiles-daemon conflicts with TLP — removing it first."
        sudo systemctl disable --now power-profiles-daemon &>/dev/null || true
        sudo apt-get purge -y power-profiles-daemon &>/dev/null || warn "Couldn't remove power-profiles-daemon — TLP may fight it for control."
    fi

    install_pkgs "TLP" tlp tlp-rdw

    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now tlp &>/dev/null || true
    else
        sudo service tlp start &>/dev/null || true
    fi

    if is_installed tlp; then
        ok "TLP installed and running. Check status any time with: sudo tlp-stat -s"

        # Charge thresholds only exist on hardware that exposes them
        # (ThinkPads via the in-kernel thinkpad_acpi driver, and some
        # others) — check rather than assume, and don't silently pick
        # a number for someone's battery.
        BAT_PATH=$(find /sys/class/power_supply -maxdepth 1 -iname 'BAT*' -print -quit 2>/dev/null)
        if [[ -n "$BAT_PATH" && -f "${BAT_PATH}/charge_control_end_threshold" ]]; then
            BAT_NAME=$(basename "$BAT_PATH")
            info "Charge-threshold support detected on ${BAT_NAME} (common on ThinkPads)."
            if ask "Cap charging at 80% to slow long-term battery wear (common ThinkPad recommendation)?" "N"; then
                sudo mkdir -p /etc/tlp.d
                cat | sudo tee /etc/tlp.d/60-battery-threshold.conf > /dev/null << EOF
# Written by hardwareSupport.sh — charge threshold for ${BAT_NAME}.
# Full-charge fans of 100% can delete this file and run: sudo tlp start
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
EOF
                sudo tlp start &>/dev/null || true
                ok "Charge capped at 80% (starts topping up again below 75%). Edit /etc/tlp.d/60-battery-threshold.conf to change it."
            fi
        else
            info "No charge-threshold sysfs entry found on this machine — skipping (nothing to configure, not an error)."
        fi
    fi
fi

ok "Hardware support step complete."
warn "A reboot is recommended so newly installed firmware/microcode is loaded."
