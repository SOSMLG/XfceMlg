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
    xfce4-terminal
    thunar thunar-volman tumbler
    xfce4-power-manager xfce4-notifyd xfce4-screenshooter
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

# --- 2. SLiM must go (tasksel's unwanted default) ---------------------
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
    if [ -f /etc/X11/default-display-manager ]; then
        if ! grep -q "lightdm" /etc/X11/default-display-manager 2>/dev/null; then
            echo "/usr/sbin/lightdm" | priv tee /etc/X11/default-display-manager >/dev/null
            log_ok "Default display manager set to LightDM."
        else
            log_ok "LightDM already the default display manager."
        fi
    fi
    if is_installed greetd; then
        log_warn "greetd is also installed — disable it (rc-update del greetd default) so the two DMs don't fight."
    fi
else
    log_err "LightDM is not installed after step 1 — re-run this script."
    exit 1
fi

# --- 4. Optional network applet ----------------------------------------
if ! is_installed network-manager-gnome && ! is_installed connman-gtk; then
    if ask "Install network-manager + applet (no network GUI otherwise)?" "N"; then
        apt_update || true
        install_pkgs "NetworkManager" network-manager network-manager-gnome || true
        start_service NetworkManager || true
    fi
fi

log_ok "XFCE core step complete. Your session at the LightDM picker: 'Xfce Session'."
