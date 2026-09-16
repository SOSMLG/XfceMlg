#!/usr/bin/env bash
# DEBSWAY_DESC: WiFi/BT firmware, CPU microcode, fwupd, TLP, ThinkPad extras
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

    start_service fwupd
    log_ok "fwupd installed. Check for updates with: fwupdmgr get-updates"
fi

log_head "4/4  TLP (laptop power management, ThinkPad battery thresholds)"
if ask "Install TLP for battery/power tuning?"; then
    # power-profiles-daemon and TLP both try to manage the same knobs
    # (CPU governor, PCIe ASPM, etc.) — running both fights itself and
    # is a well-known source of "my settings keep reverting" reports.
    if is_installed power-profiles-daemon; then
        log_info "power-profiles-daemon conflicts with TLP — removing it first."
        start_service power-profiles-daemon 2>/dev/null || true
        priv apt-get purge -y power-profiles-daemon &>/dev/null || log_warn "Couldn't remove power-profiles-daemon — TLP may fight it for control."
    fi

    install_pkgs "TLP" tlp tlp-rdw

    start_service tlp

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
            # Hardware-specific: never auto-apply on --full, always confirm.
            if ask_no_full "Cap charging at 80% to slow long-term battery wear (common ThinkPad recommendation)?" "N"; then
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

log_ok "Hardware support complete."
log_warn "A reboot is recommended so newly installed firmware/microcode is loaded."

# ---------------------------------------------------------------------------
# ThinkPad-specific extras (auto-detected, only offered on matching hardware)
# ---------------------------------------------------------------------------
IS_THINKPAD=0
if [[ -d /sys/devices/platform/thinkpad_acpi ]] \
    || grep -qi "thinkpad" /sys/class/dmi/id/product_name 2>/dev/null \
    || grep -qi "thinkpad" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    IS_THINKPAD=1
fi

if [[ "$IS_THINKPAD" -eq 1 ]]; then
    echo
    log_head "ThinkPad extras (auto-detected)"

    if ask_no_full "Install thinkfan (thermal management for ThinkPads)?" "N"; then
        install_pkgs "ThinkFan" thinkfan
        start_service thinkfan
        log_ok "thinkfan installed. Edit /etc/thinkfan.conf to tune fan curves."
        log_info "Default: conservative — edit thresholds or run: doas thinkfan -n"
    fi

    if ask_no_full "Install powertop with auto-tune on boot (power savings)?" "N"; then
        install_pkgs "PowerTOP" powertop
        # Create a oneshot service/RC script for powertop --auto-tune
        POWERTOP_SERVICE="/etc/init.d/powertop-autotune"
        if [[ ! -f "$POWERTOP_SERVICE" ]]; then
            priv tee "$POWERTOP_SERVICE" > /dev/null << 'POWEOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          powertop-autotune
# Required-Start:    $local_fs
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: PowerTOP auto-tune
# Description:       Applies PowerTOP recommendations at boot
### END INIT INFO
case "$1" in
  start)
    /usr/sbin/powertop --auto-tune >/dev/null 2>&1 &
    ;;
  stop)
    ;;
  *)
    echo "Usage: $0 {start|stop}"
    exit 1
esac
exit 0
POWEOF
            priv chmod 755 "$POWERTOP_SERVICE"
            priv /usr/sbin/update-rc.d powertop-autotune defaults 2>/dev/null || true
            log_ok "powertop auto-tune service created and enabled."
        fi
    fi
fi
