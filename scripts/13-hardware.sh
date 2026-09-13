#!/usr/bin/env bash
# DEBSWAY_DESC: WiFi/BT firmware, CPU microcode, fwupd, TLP + battery cap
# DEBSWAY_DEFAULT: Y
#  13-hardware.sh — firmware, microcode, firmware updates
#  Covers "why doesn't my WiFi/Bluetooth work" — almost always a
#  missing non-free firmware blob, not a driver bug. Inert on
#  hardware it doesn't match, so it doesn't conflict with
#  staying minimal.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root







apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/4  WiFi/Bluetooth firmware"
if ask "Install common WiFi/Bluetooth firmware (Intel/Realtek/Atheros/Broadcom)?"; then
    install_pkgs "WiFi/Bluetooth firmware" \
        firmware-iwlwifi firmware-realtek firmware-atheros \
        firmware-brcm80211 firmware-misc-nonfree firmware-linux
fi

log_head "2/4  CPU microcode (auto-detected)"
if ask "Install CPU microcode updates?"; then
    VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
    case "$VENDOR" in
        GenuineIntel) log_info "Detected Intel CPU."; install_pkgs "Intel microcode" intel-microcode ;;
        AuthenticAMD) log_info "Detected AMD CPU.";   install_pkgs "AMD microcode" amd64-microcode ;;
        *) log_warn "Could not detect CPU vendor, skipping microcode." ;;
    esac
fi

log_head "3/4  fwupd (BIOS/UEFI + peripheral firmware updates)"
if ask "Install fwupd?"; then
    install_pkgs "fwupd" fwupd

    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        priv systemctl enable --now fwupd &>/dev/null || true
    else
        priv service fwupd start &>/dev/null || true
    fi
    log_ok "fwupd installed. Check for updates with: fwupdmgr get-updates"
fi

log_head "4/4  TLP (laptop power management, ThinkPad battery thresholds)"
if ask "Install TLP for battery/power tuning?"; then
    # power-profiles-daemon and TLP both try to manage the same knobs
    # (CPU governor, PCIe ASPM, etc.) — running both fights itself and
    # is a well-known source of "my settings keep reverting" reports.
    if is_installed power-profiles-daemon; then
        log_info "power-profiles-daemon conflicts with TLP — removing it first."
        priv systemctl disable --now power-profiles-daemon &>/dev/null || true
        priv apt-get purge -y power-profiles-daemon &>/dev/null || log_warn "Couldn't remove power-profiles-daemon — TLP may fight it for control."
    fi

    install_pkgs "TLP" tlp tlp-rdw

    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        priv systemctl enable --now tlp &>/dev/null || true
    else
        priv service tlp start &>/dev/null || true
    fi

    if is_installed tlp; then
        log_ok "TLP installed and running. Check status any time with: doas tlp-stat -s"

        # Charge thresholds only exist on hardware that exposes them
        # (ThinkPads via the in-kernel thinkpad_acpi driver, and some
        # others) — check rather than assume, and don't silently pick
        # a number for someone's battery.
        BAT_PATH=$(find /sys/class/power_supply -maxdepth 1 -iname 'BAT*' -print -quit 2>/dev/null)
        if [[ -n "$BAT_PATH" && -f "${BAT_PATH}/charge_control_end_threshold" ]]; then
            BAT_NAME=$(basename "$BAT_PATH")
            log_info "Charge-threshold support detected on ${BAT_NAME} (common on ThinkPads)."
            if ask "Cap charging at 80% to slow long-term battery wear (common ThinkPad recommendation)?" "N"; then
                priv mkdir -p /etc/tlp.d
                cat | priv tee /etc/tlp.d/60-battery-threshold.conf > /dev/null << EOF
# Written by 13-hardware.sh — charge threshold for ${BAT_NAME}.
# Full-charge fans of 100% can delete this file and run: doas tlp start
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
EOF
                priv tlp start &>/dev/null || true
                log_ok "Charge capped at 80% (starts topping up again below 75%). Edit /etc/tlp.d/60-battery-threshold.conf to change it."
            fi
        else
            log_info "No charge-threshold sysfs entry found on this machine — skipping (nothing to configure, not an error)."
        fi
    fi
fi

log_ok "Hardware support log_head complete."
log_warn "A reboot is recommended so newly installed firmware/microcode is loaded."
