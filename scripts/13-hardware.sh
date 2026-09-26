#!/usr/bin/env bash
# DEBSWAY_DESC: firmware, microcode, fwupd, TLP battery maximizer, boot params, XFCE power profile, ThinkPad extras
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

log_head "1/6  WiFi/Bluetooth firmware"
if ask "Install common WiFi/Bluetooth firmware (Intel/Realtek/Atheros/Broadcom)?"; then
    install_pkgs "WiFi/Bluetooth firmware" \
        firmware-iwlwifi firmware-realtek firmware-atheros \
        firmware-brcm80211 firmware-misc-nonfree firmware-linux
fi

log_head "2/6  CPU microcode (auto-detected)"
if ask "Install CPU microcode updates?"; then
    VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
    case "$VENDOR" in
        GenuineIntel) log_info "Detected Intel CPU."; install_pkgs "Intel microcode" intel-microcode ;;
        AuthenticAMD) log_info "Detected AMD CPU.";   install_pkgs "AMD microcode" amd64-microcode ;;
        *) log_warn "Could not detect CPU vendor, skipping microcode." ;;
    esac
fi

log_head "3/6  fwupd (BIOS/UEFI + peripheral firmware updates)"
if ask "Install fwupd?"; then
    install_pkgs "fwupd" fwupd

    start_service fwupd
    log_ok "fwupd installed. Check for updates with: fwupdmgr get-updates"
fi

log_head "4/6  TLP (laptop power management, battery maximizer, ThinkPad charge thresholds)"
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
            if ask_no_full "Cap charging at 80% to slow long-term battery wear (common ThinkPad recommendation)?" "Y"; then
                priv mkdir -p /etc/tlp.d
                priv tee /etc/tlp.d/60-battery-threshold.conf > /dev/null << EOF
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

        # Battery maximizer — cuts beyond TLP's own defaults. WIFI_PWR_ON_BAT,
        # SOUND_POWER_SAVE_ON_BAT and NMI_WATCHDOG are already TLP defaults;
        # the meaningful extra cuts are a power-leaning CPU energy policy
        # (AMD/HWP EPP) and forced powersave PCIe ASPM on the battery. CPU
        # boost is left ON so heavy work (MATLAB, builds) still has its headroom.
        # /etc/tlp.d/*.conf is re-applied by TLP at every boot/start regardless
        # of init system — no systemd unit or rc script involved.
        priv mkdir -p /etc/tlp.d
        priv tee /etc/tlp.d/70-maxbattery.conf > /dev/null << 'EOF'
# Written by 13-hardware.sh — battery maximizer (balanced, CPU boost preserved).
CPU_ENERGY_PERF_POLICY_ON_BAT=power
PCIE_ASPM_ON_BAT=powersave
EOF
        if priv tlp start >/dev/null 2>&1; then
            log_ok "Battery maximizer applied: CPU EPP=power + PCIe ASPM=powersave on battery (boost kept)."
            log_info "Tuned via /etc/tlp.d/70-maxbattery.conf — edit it to undo. Inspect with: tlp-stat -c"
        else
            log_warn "tlp start failed after tuning — inspect with: tlp-stat -c"
        fi
    fi
fi

log_head "5/6  Boot params — force PCIe ASPM (GRUB, init-agnostic)"
if ask "Force PCIe ASPM at boot (pcie_aspm=force) and rebuild GRUB?"; then
    GRUB_DEF="/etc/default/grub"
    if [[ -f "$GRUB_DEF" ]] && command -v update-grub >/dev/null; then
        priv cp -a "$GRUB_DEF" "${GRUB_DEF}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        if ! grep -q 'pcie_aspm=force' "$GRUB_DEF"; then
            priv sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 pcie_aspm=force"/' "$GRUB_DEF" 2>/dev/null \
                || log_warn "Could not edit $GRUB_DEF — edit GRUB_CMDLINE_LINUX_DEFAULT manually."
        fi
        if grep -q 'pcie_aspm=force' "$GRUB_DEF"; then
            log_ok "pcie_aspm=force added to GRUB_CMDLINE_LINUX_DEFAULT."
        fi
        if priv update-grub >/dev/null 2>&1; then
            log_ok "GRUB rebuilt — pcie_aspm=force takes effect after reboot."
        else
            log_warn "update-grub failed — run it manually as root: update-grub"
        fi
    else
        log_info "GRUB not detected (no /etc/default/grub or update-grub) — TLP already handles ASPM on battery; skipping boot params."
    fi
fi

log_head "6/6  XFCE Power Manager — battery-first profile"
if ask "Apply battery-first power-manager profile (blank 3/10 min, suspend 30 min, brightness 55% on battery)?"; then
    # Idempotent setter: -n create only when the property is new, plain -s on re-run.
    pm_set() {
        local prop="$1" type="$2" value="$3"
        local path="/xfce4-power-manager/$prop"
        if xfconf-query -c xfce4-power-manager -l 2>/dev/null | grep -qx "$path"; then
            xfconf-query -c xfce4-power-manager -p "$path" -s "$value" 2>/dev/null \
                && log_info "pm $prop = $value" \
                || log_warn "Could not set $prop via xfconf — a running desktop session is needed (the seed carries it for fresh installs)."
        else
            xfconf-query -c xfce4-power-manager -n -p "$path" -t "$type" -s "$value" 2>/dev/null \
                && log_info "pm $prop = $value (new)" \
                || log_warn "Could not set $prop via xfconf — a running desktop session is needed (the seed carries it for fresh installs)."
        fi
    }
    # presentation-mode off: otherwise the screen is pinned awake and never blanks.
    pm_set presentation-mode bool false
    pm_set inactivity-on-battery uint 3
    pm_set inactivity-on-ac uint 10
    pm_set dpms-on-battery-off uint 3
    pm_set dpms-on-battery-sleep uint 30
    pm_set dpms-on-ac-off uint 10
    pm_set dpms-on-ac-sleep uint 0
    # lid actions: 3 = suspend, 0 = do nothing (Undo in Settings → Power Manager).
    pm_set lid-action-on-battery uint 3
    pm_set lid-action-on-ac uint 0
    pm_set brightness-on-battery uint 55
    pm_set brightness-on-ac uint 100
    log_ok "Battery-first power profile applied (lid closes → suspend on battery, do nothing on AC)."
    log_info "The matching profile is seeded in configs/xfce4/ so fresh installs get it too."
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
            # Init-agnostic: start_service detects systemd / OpenRC / sysvinit
            # (rc-update+rc-service / update-rc.d+service) and enables accordingly.
            start_service powertop-autotune
            log_ok "powertop auto-tune service created and enabled via detect_init."
        else
            log_info "powertop auto-tune service already present — enabling it for this init."
            start_service powertop-autotune
        fi
    fi
fi
