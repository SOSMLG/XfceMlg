#!/usr/bin/env bash
# XMLG_DESC: power-user commands (menu, update-check/gui, lock, suspend, health, selfupdate)
# XMLG_DEFAULT: Y
#  24-power-user.sh — deploy xfce-menu, xfce-update-{check,gui},
#  xfce-lock, xfce-suspend, xfcemlg (self-update), and the cron
#  update notifier, and autostart the login health check.
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
TOOL_DIR="$HOME/.local/share/xfcemlg"
mkdir -p "$LOCAL_BIN" "$TOOL_DIR"

# Python apps from the toolkit's configs/share/
APP_DIR="$SCRIPT_DIR/../configs/share/xfcemlg"
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
LAUNCHERS="xfce-menu xfce-update-gui xfce-record xfce-scratch"
CLI_CMDS="xfce-update-check xfce-lock xfce-suspend xfce-battery-warn xfce-temp-warn xfce-raise xfcemlg"
for f in $LAUNCHERS $CLI_CMDS; do
	[[ -f "$BIN_DIR/$f" ]] || continue
	[[ -f "$LOCAL_BIN/$f" ]] && cp "$LOCAL_BIN/$f" "$LOCAL_BIN/$f.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
	cp -f "$BIN_DIR/$f" "$LOCAL_BIN/$f"
	chmod +x "$LOCAL_BIN/$f"
done
log_ok "Shell launchers deployed to $LOCAL_BIN"

# xfcemlg-health — the read-only end-state reporter, deployed separately from
# the loop above because it is a diagnostic rather than a launcher, and because
# it needs to be findable under a name a user would actually type.
#
# It deliberately runs the repo's scripts/verifySetup.sh, which is NOT itself
# deployed. So the deployed copy is pointed at the *source tree* when one is
# present (the common case: the user keeps the checkout), and says plainly
# which copy it used rather than silently reporting "no checks" as success.
# With no checkout available it reports a tooling failure (exit 2), not a pass.
if [[ -f "$BIN_DIR/xfcemlg-health" ]]; then
	cp -f "$BIN_DIR/xfcemlg-health" "$LOCAL_BIN/xfcemlg-health"
	chmod +x "$LOCAL_BIN/xfcemlg-health"
	if [[ -f "$SCRIPT_DIR/verifySetup.sh" ]]; then
		log_ok "Health reporter deployed to $LOCAL_BIN/xfcemlg-health (uses this checkout's verifySetup.sh)"
		log_info "  Run it:      xfcemlg-health"
		log_info "  Cron entry:  0 9,18 * * * $LOCAL_BIN/xfcemlg-health --quiet"

		# Login-time health check: silent on success, notifies ONLY on
		# problems (same contract as the cron entry — quiet + notify on FAIL).
		# Only written when verification is resolvable, so a deb-only box
		# without a checkout never nags at every login.
		mkdir -p "$HOME/.config/autostart"
		{
			echo "[Desktop Entry]"
			echo "Type=Application"
			echo "Name=xfcemlg-health"
			echo "Comment=Silent login health check; notifies only on problems"
			echo "Exec=$LOCAL_BIN/xfcemlg-health --quiet"
			echo "X-GNOME-Autostart-enabled=true"
			echo "NoDisplay=true"
		} >"$HOME/.config/autostart/xfcemlg-health.desktop"
		log_ok "Autostarted login health check ($HOME/.config/autostart/xfcemlg-health.desktop)"
		log_info "  Toolkit self-update: $LOCAL_BIN/xfcemlg selfupdate"
	else
		log_warn "Health reporter deployed, but this checkout has no scripts/verifySetup.sh."
		log_warn "  It will exit 2 (tooling problem) until XFCEMLG_VERIFY points at a real one."
	fi
fi

# Battery + thermal warning daemons: autostart with the session
WARN_DIR="$HOME/.config/autostart"
for d in xfce-battery-warn xfce-temp-warn; do
	[[ -f "$LOCAL_BIN/$d" ]] || continue
	mkdir -p "$WARN_DIR"
	{
		echo "[Desktop Entry]"
		echo "Type=Application"
		echo "Name=$d"
		echo "Comment=Darkmatter battery/thermal notifier (dunst)"
		echo "Exec=$LOCAL_BIN/$d"
		echo "X-GNOME-Autostart-enabled=true"
		echo "NoDisplay=true"
	} >"$WARN_DIR/$d.desktop"
	log_ok "Autostarted $d ($WARN_DIR/$d.desktop)"
done

log_head "3/4  Cron update notifier (09:00 + 18:00)"
CHECKER="$LOCAL_BIN/xfce-update-check"
CRON_MARKER="# xfcemlg: update notifier"
NEW_CRON=$(mktemp)
(crontab -l 2>/dev/null | grep -vF "$CHECKER" | grep -vF "$CRON_MARKER") >"$NEW_CRON" || true
{
	echo "$CRON_MARKER"
	echo "0 9,18 * * * $CHECKER >/dev/null 2>&1"
} >>"$NEW_CRON"
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
echo -e "  xfce-suspend        xfce4-session-logout --suspend (elogind, no root)"
echo -e "  xfcemlg-health      read-only end-state health check (exit 1 = something is wrong)"
