#!/usr/bin/env bash
# DEBSWAY_DESC: NTP time sync via chrony
# DEBSWAY_DEFAULT: N
# =======================================================
# Time Sync (NTP) via chrony
# -------------------------------------------------------
# Enables automatic time synchronization with chrony, the
# default NTP daemon on Devuan/Debian. Works under any
# init (systemd, OpenRC, sysvinit) through start_service().
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Time Sync (NTP)"

if is_installed chrony; then
    log_ok "chrony already installed."
else
    if ask "Install and enable NTP time sync via chrony?"; then
        apt_update || { log_err "apt-get update failed, aborting."; exit 1; }
        install_pkgs "chrony" chrony
    else
        log_info "Skipped."
        exit 0
    fi
fi

start_service chrony

# One NTP daemon is enough, and chrony is the toolkit standard: park the
# overlapping openntpd wherever it is enabled (both init systems — package
# stays installed, re-enable any time). Best-effort; absent is the norm.
if command_exists update-rc.d || [ -x /usr/sbin/update-rc.d ]; then
    priv /usr/sbin/update-rc.d openntpd disable >/dev/null 2>&1 || true
fi
if command_exists rc-update || [ -x /usr/sbin/rc-update ]; then
    priv /usr/sbin/rc-update del openntpd default >/dev/null 2>&1 || true
fi
priv service openntpd stop >/dev/null 2>&1 || true

# Sanity check — chronyc tracking as a normal user usually works.
if sleep 2 && command_exists chronyc && chronyc tracking >/dev/null 2>&1; then
    log_ok "chrony is tracking time; system clock will stay in sync."
else
    log_warn "chrony is installed but not tracking yet (normal on the first boot before"
    log_warn "it picks a server). Verify later with: chronyc tracking"
fi