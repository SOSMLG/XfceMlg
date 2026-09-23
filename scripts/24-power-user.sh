#!/usr/bin/env bash
# DEBSWAY_DESC: power-user commands (menu, update-check/gui, lock, suspend)
# DEBSWAY_DEFAULT: Y
#  24-power-user.sh — deploy xfce-menu, xfce-update-{check,gui},
#  xfce-lock, xfce-suspend, and the cron update notifier.
#
#  Python GUIs (xfce-menu, xfce-update-gui) need python3-gi + VTE.
#  xfce-update-check runs from cron (09:00 + 18:00) and pops a
#  desktop notification with a clickable "Update now" action.
#
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root


apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/4  Dependencies"
install_pkgs "Power-user deps" \
    python3-gi gir1.2-gtk-3.0 gir1.2-vte-2.91 libnotify-bin cron
log_ok "Dependencies installed."

log_head "2/4  Python apps + shell launchers"
LOCAL_BIN="$HOME/.local/bin"
TOOL_DIR="$HOME/.local/share/devuan-xfce-setup"
mkdir -p "$LOCAL_BIN" "$TOOL_DIR"

# Python apps from the toolkit's configs/share/
APP_DIR="$SCRIPT_DIR/../configs/share/devuan-xfce-setup"
if [[ -d "$APP_DIR" ]]; then
    for py in "$APP_DIR"/*.py; do
        [[ -f "$py" ]] || continue
        cp -f "$py" "$TOOL_DIR/"
    done
    chmod 755 "$TOOL_DIR"/*.py 2>/dev/null || true
    log_ok "Python apps deployed to $TOOL_DIR"
else
    log_warn "$APP_DIR not found — GUI commands will not work."
fi

# Shell launchers + CLI commands from configs/bin/
BIN_DIR="$SCRIPT_DIR/../configs/bin"
LAUNCHERS="xfce-menu xfce-update-gui"
CLI_CMDS="xfce-update-check xfce-lock xfce-suspend"
for f in $LAUNCHERS $CLI_CMDS; do
    [[ -f "$BIN_DIR/$f" ]] || continue
    [[ -f "$LOCAL_BIN/$f" ]] && cp "$LOCAL_BIN/$f" "$LOCAL_BIN/$f.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    cp -f "$BIN_DIR/$f" "$LOCAL_BIN/$f"
    chmod +x "$LOCAL_BIN/$f"
done
log_ok "Shell launchers deployed to $LOCAL_BIN"

log_head "3/4  Cron update notifier (09:00 + 18:00)"
CHECKER="$LOCAL_BIN/xfce-update-check"
CRON_MARKER="# devuan-xfce-setup: update notifier"
NEW_CRON=$(mktemp)
( crontab -l 2>/dev/null | grep -vF "$CHECKER" | grep -vF "$CRON_MARKER" ) > "$NEW_CRON" || true
{
    echo "$CRON_MARKER"
    echo "0 9,18 * * * $CHECKER >/dev/null 2>&1"
} >> "$NEW_CRON"
if crontab "$NEW_CRON"; then
    log_ok "Cron job installed (runs at 09:00 and 18:00 daily)."
else
    log_err "Failed to install the cron job — add manually: crontab -e"
    echo "  0 9,18 * * * $CHECKER"
fi
rm -f "$NEW_CRON"

start_service cron
log_ok "cron enabled and started via init (verify with: rc-service cron status / service cron status)."

log_head "4/4  Verify"
if command -v xfce-menu >/dev/null 2>&1; then
    log_ok "xfce-menu installed (Super+M or 'xfce-menu')"
else
    log_warn "xfce-menu not on PATH"
fi
if command -v xfce-update-gui >/dev/null 2>&1; then
    log_ok "xfce-update-gui installed"
else
    log_warn "xfce-update-gui not on PATH"
fi
log_ok "Power-user commands deployed."
echo -e "  xfce-menu           searchable launcher (Apps / AI / System)"
echo -e "  xfce-update-check   runs from cron, notifies with 'Update now'"
echo -e "  xfce-update-gui     VTE window running apt-get full-upgrade"
echo -e "  xfce-lock           xfce4-screensaver / xflock4"
echo -e "  xfce-suspend        pm-suspend via doas/sudo"
