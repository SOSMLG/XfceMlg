#!/usr/bin/env bash
# DEBSWAY_DESC: Lean XFCE core (minimal-install path, no tasksel/SLiM)
# DEBSWAY_DEFAULT: Y
# =======================================================
# XFCE core — the minimal-install path
# -------------------------------------------------------
# Installs a lean XFCE desktop WITHOUT tasksel's
# task-xfce-desktop (which drags in SLiM as its preferred
# DM plus Parole/QuodLibet/Mousepad/Xfburn that 20-*
# would only purge again). Everything here uses
# --no-install-recommends so only the named packages land.
#
# On a system where XFCE is already present (distro
# installer path) this is a no-op except for the LightDM
# assurance: SLiM purged when found, LightDM enabled.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "XFCE core (lean, no tasksel)"

# --- 1. Lean desktop set ---------------------------------------------
LEAN_PKGS=(
    xorg
    xfce4-session xfwm4 xfce4-panel xfce4-settings xfce4-appfinder
    alacritty
    xfce4-whiskermenu-plugin
    thunar thunar-volman tumbler
    xfce4-power-manager xfce4-notifyd flameshot
    xfce4-pulseaudio-plugin xfce4-taskmanager
    light-locker
    xfce-polkit dbus-x11
    lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
    gvfs-backends udisks2
    numlockx
)

missing=()
for pkg in "${LEAN_PKGS[@]}"; do
    is_installed "$pkg" || missing+=("$pkg")
done

if [ "${#missing[@]}" -eq 0 ]; then
    log_ok "Lean XFCE core already installed."
else
    log_info "Installing lean XFCE core (--no-install-recommends): ${missing[*]}"
    apt_update || log_warn "apt-get update failed (continuing with cached lists)."
    if priv apt-get install -y --no-install-recommends "${missing[@]}"; then
        log_ok "Lean XFCE core installed."
    else
        log_err "XFCE core install reported failures."
        exit 1
    fi
fi

# --- 2. tasksel's meta + SLiM must go ---------------------------------
# The distro-installer path landed task-xfce-desktop, a recommends-heavy
# meta (SLiM, Mousepad, Parole, QuodLibet, Xfburn). The lean path never
# installs it; when present, purge the meta so those recommends stop being
# held. The apps themselves are handled by 20-xfce-debloat.sh.
if is_installed task-xfce-desktop; then
    if ask "Purge task-xfce-desktop (tasksel's meta — pulls SLiM + Mousepad + Parole + Xfburn)?"; then
        priv apt-get purge -y task-xfce-desktop || log_warn "task-xfce-desktop purge had issues (continuing)."
        log_ok "task-xfce-desktop purged (its apps are trimmed by 20-xfce-debloat.sh)."
    fi
fi
if is_installed slim; then
    if ask "Purge SLiM (tasksel's default DM — LightDM replaces it)?"; then
        if command -v rc-service >/dev/null 2>&1; then
            priv rc-service slim stop >/dev/null 2>&1 || true
        fi
        priv apt-get purge -y slim || log_warn "SLiM purge had issues (continuing)."
        log_ok "SLiM purged."
    else
        log_warn "Keeping SLiM — make sure only ONE display manager is enabled (it will fight LightDM)."
    fi
fi

# --- 3. LightDM owns the console --------------------------------------
if is_installed lightdm; then
    start_service lightdm
    normalize_display_manager
    if is_installed greetd; then
        log_warn "greetd is also installed — disable it (rc-update del greetd default) so the two DMs don't fight."
    fi
else
    log_err "LightDM is not installed after step 1 — re-run this script."
    exit 1
fi

# --- 4. Optional network applet ----------------------------------------
# NOTE: the init script is lowercase `network-manager` on Devuan/OpenRC
# (capital `NetworkManager` only exists on systemd) — resolve it.
nm_service_name() {
    if [[ -x /etc/init.d/network-manager ]]; then
        printf 'network-manager\n'
    else
        printf 'NetworkManager\n'
    fi
}
if ! is_installed network-manager-gnome && ! is_installed connman-gtk; then
    if ask "Install network-manager + applet (no network GUI otherwise)?" "Y"; then
        apt_update || true
        install_pkgs "NetworkManager" network-manager network-manager-gnome || true
        start_service "$(nm_service_name)" || true
    fi
fi

# --- 5. Hand interface management to NetworkManager -----------------------
# Minimal-install fingerprint: the Debian installer claims physical ifaces
# in /etc/network/interfaces, and Debian ships NM with
# [ifupdown] managed=false — together NM shows "device not managed"
# (wifi unusable from the applet) even though everything is installed.
# Fix: trim interfaces(5) to loopback-only (backed up, only when it
# actually claims a non-lo iface) + set managed=true, then bounce NM.
# Runs whenever NM is present, not just right after installing it.
if is_installed network-manager; then
    INTERFACES_FILE="/etc/network/interfaces"
    if [[ -f "$INTERFACES_FILE" ]]; then
        if awk '
            /^[[:space:]]*($|#)/ || /^source(-directory)?[[:space:]]/ { next }
            /^(auto|allow-[a-z-]+)[[:space:]]/ {
                for (i = 2; i <= NF; i++) if ($i != "lo") { claimed = 1; exit }
                next
            }
            /^iface[[:space:]]/ { if ($2 != "lo") { claimed = 1; exit } }
            END { exit !claimed }
        ' "$INTERFACES_FILE" 2>/dev/null; then
            BACKUP="${INTERFACES_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
            priv cp "$INTERFACES_FILE" "$BACKUP"
            log_info "Backed up $INTERFACES_FILE to $BACKUP"
            priv tee "$INTERFACES_FILE" > /dev/null << 'EOF'
# Trimmed by 10-xfce-core.sh — NetworkManager owns physical interfaces now.
# Loopback stays here; everything else moved to NM (see the .bak file).
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback
EOF
            log_ok "Trimmed $INTERFACES_FILE to loopback-only (physical ifaces handed to NM)."
        else
            log_ok "$INTERFACES_FILE already loopback-only — leaving it alone."
        fi
    fi

    NM_CONF="/etc/NetworkManager/NetworkManager.conf"
    if [[ -f "$NM_CONF" ]]; then
        if grep -Eq '^[[:space:]]*managed[[:space:]]*=[[:space:]]*true' "$NM_CONF" 2>/dev/null; then
            log_ok "NetworkManager already set to manage ifupdown interfaces."
        else
            priv cp "$NM_CONF" "${NM_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
            if grep -Eq '^[[:space:]]*managed[[:space:]]*=' "$NM_CONF" 2>/dev/null; then
                priv sed -i -E 's/^[[:space:]]*managed[[:space:]]*=.*/managed=true/' "$NM_CONF"
            elif grep -Eq '^\[ifupdown\]' "$NM_CONF" 2>/dev/null; then
                priv sed -i '/^\[ifupdown\]/a managed=true' "$NM_CONF"
            else
                printf '\n[ifupdown]\nmanaged=true\n' | priv tee -a "$NM_CONF" > /dev/null
            fi
            log_ok "Set [ifupdown] managed=true in $NM_CONF."
        fi
    fi

    # Bounce NM so both changes take effect (enable alone isn't a restart).
    NM_SVC="$(nm_service_name)"
    if command_exists systemctl && [ -d /run/systemd/system ]; then
        priv systemctl restart "$NM_SVC" >/dev/null 2>&1 || true
    elif [ -x "/etc/init.d/$NM_SVC" ]; then
        priv "/etc/init.d/$NM_SVC" restart >/dev/null 2>&1 || true
    else
        start_service "$NM_SVC" || true
    fi
    if command -v nmcli &>/dev/null; then
        sleep 2
        NM_STATE="$(nmcli -t -f DEVICE,STATE device 2>/dev/null || true)"
        if echo "$NM_STATE" | grep -q ':unmanaged'; then
            log_warn "A device is still unmanaged — check 'nmcli device status'."
        elif echo "$NM_STATE" | grep -q ':unavailable'; then
            log_info "A device is unavailable (no cable, or radio firmware still loading — see 13-hardware.sh)."
        else
            log_ok "NetworkManager owns the interfaces now — pick your Wi-Fi from the applet."
        fi
    fi
fi

log_ok "XFCE core step complete. Your session at the LightDM picker: 'Xfce Session'."
