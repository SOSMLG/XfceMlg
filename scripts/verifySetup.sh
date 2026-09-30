#!/usr/bin/env bash
# =======================================================
# Verify Setup — end-state audit (XFCE edition)
# -------------------------------------------------------
# One-pass check of the toolkit's expected end state:
# group membership, key packages, fonts, Firefox policy,
# Darkmatter theme markers, Thunar plugins, LightDM config,
# and enabled services. Designed to be run from
# run.sh --verify after a run, or standalone at any time.
#
# Prints PASS/FAIL/WARN lines and exits non-zero if any
# critical check failed, so it can gate CI/validation.
#
#   verifySetup.sh --json     emit a machine-readable JSON object as the
#                             final line ({"passed":N,"failed":N,"warned":N,
#                             "checks":[{"name","status","detail"},...]})
#                             — the exit code contract is unchanged.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

JSON=0
JSON_CHECKS=()
for arg in "$@"; do
	case "$arg" in
	--json) JSON=1 ;;
	-h | --help)
		sed -n '1,20p' "$0"
		exit 0
		;;
	*)
		printf 'verifySetup.sh: unknown option: %s (only --json is supported)\n' "$arg" >&2
		exit 2
		;;
	esac
done

json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}

PASS=0
FAIL=0
WARN=0

report() { # report <name> <status> <detail>
	if [ "$JSON" -eq 1 ]; then
		JSON_CHECKS+=("{\"name\":\"$(json_escape "$1")\",\"status\":\"$2\",\"detail\":\"$(json_escape "${3:-}")\"}")
	fi
	case "$2" in
	ok)
		printf '  PASS  %-48s %s\n' "$1" "${3:-}"
		PASS=$((PASS + 1))
		;;
	fail)
		printf '  FAIL  %-48s %s\n' "$1" "${3:-}"
		FAIL=$((FAIL + 1))
		;;
	warn)
		printf '  WARN  %-48s %s\n' "$1" "${3:-}"
		WARN=$((WARN + 1))
		;;
	info)
		printf '  INFO  %-48s %s\n' "$1" "${3:-}"
		;;
	esac
}

pkg() { # pkg <name> [critical|optional]
	local name="$1" level="${2:-critical}"
	local state detail
	if is_installed "$name"; then
		state="ok"
		detail="installed"
	elif [ "$level" = "optional" ]; then
		state="warn"
		detail="not installed (optional — OK to skip)"
	else
		state="fail"
		detail="missing — re-run the relevant script"
	fi
	report "$name" "$state" "$detail"
}

pkg_absent() { # pkg_absent <name> — must NOT be installed
	local name="$1"
	if is_installed "$name"; then
		report "$name absent" fail "still installed — purge it (20-xfce-debloat.sh)"
	else
		report "$name absent" ok
	fi
}

bin() { # bin <command> [critical|optional]
	local name="$1" level="${2:-critical}"
	local state detail
	if command -v "$name" >/dev/null 2>&1; then
		state="ok"
		detail="$(command -v "$name")"
	elif [ "$level" = "optional" ]; then
		state="warn"
		detail="not installed (optional — OK to skip)"
	else
		state="fail"
		detail="missing — re-run the relevant script"
	fi
	report "bin: $name" "$state" "$detail"
}

cfg() { # cfg <label> <path> [critical|optional]
	local label="$1" path="$2" level="${3:-critical}"
	local state detail
	if [ -e "$path" ]; then
		state="ok"
		detail="present"
	elif [ "$level" = "optional" ]; then
		state="warn"
		detail="missing (optional — OK to skip)"
	else
		state="fail"
		detail="missing — re-run the relevant script"
	fi
	report "cfg: $label" "$state" "$detail"
}

service_state() {
	local svc="$1" procname="$2" level="${3:-fail}"
	local enabled="" running=""
	if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
		if systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-enabled "${svc}.service" >/dev/null 2>&1; then
			enabled="systemd"
		fi
	elif command -v rc-update >/dev/null 2>&1; then
		if rc-update show 2>/dev/null | awk -v s="$svc" '$1==s{found=1} END{exit !found}'; then
			enabled="openrc"
		fi
	fi
	pgrep -x "$procname" >/dev/null 2>&1 && running="yes"

	if [ -n "$running" ]; then
		report "$svc (service)" ok "${enabled:-running, not enabled}"
	elif [ -n "$enabled" ]; then
		report "$svc (service)" ok "enabled, not running (reboot or start it)"
	elif [ "$level" = "optional" ]; then
		report "$svc (service)" warn "not running"
	else
		report "$svc (service)" fail "not running"
	fi
}

log_head "Setup verification"

echo -e "  (user: ${CYAN}${ACTUAL_USER}${NC})\n"

# --- 1. Group membership ------------------------------------------------
for g in input video render plugdev bluetooth lpadmin; do
	if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
		report "group: $g" ok
	else
		report "group: $g" warn "user not in $g (re-run 12-user-groups.sh / 14-bluetooth.sh / 30-desktop-essentials.sh)"
	fi
done

# --- 2. Lean core: session, WM, panel, terminal, DM ----------------------
pkg xorg
pkg xfce4-session
pkg xfwm4
pkg xfce4-panel
pkg xfce4-settings
pkg lightdm
pkg lightdm-gtk-greeter
pkg dbus-x11
pkg xfce-polkit

# --- 2b. Single polkit auth agent -----------------------------------------
# polkitd accepts one auth agent per subject; duplicates fail at login.
# 10-xfce-core.sh masks foreign agents — assert nothing else survives.
foreign_polkit=""
for f in /etc/xdg/autostart/*.desktop "$HOME"/.config/autostart/*.desktop; do
	[ -f "$f" ] || continue
	base="$(basename "$f")"
	case "$base" in
	xfce-polkit.desktop) continue ;;
	*polkit*.desktop) ;;
	*) continue ;;
	esac
	# A user-level Hidden=true override shadows the system entry.
	if [ -f "$HOME/.config/autostart/$base" ] &&
		grep -q '^Hidden=true' "$HOME/.config/autostart/$base" 2>/dev/null; then
		continue
	fi
	grep -q '^Hidden=true' "$f" 2>/dev/null && continue
	foreign_polkit="$foreign_polkit $base"
done
if [ -n "$foreign_polkit" ]; then
	report "single polkit agent" fail "extra agents:$foreign_polkit (re-run 10-xfce-core.sh to mask)"
else
	report "single polkit agent" ok
fi

if is_installed slim; then
	report "slim absent" fail "installed — purge it (10-xfce-core.sh) so it can't fight LightDM"
else
	report "slim absent" ok
fi

# Purged by 20-xfce-debloat.sh — Alacritty is the toolkit's terminal.
pkg_absent xfce4-terminal
pkg_absent xfce4-screenshooter

# --- 3. Thunar full set --------------------------------------------------
pkg thunar
pkg thunar-volman
pkg thunar-archive-plugin
pkg thunar-media-tags-plugin
pkg thunar-vcs-plugin
pkg thunar-gtkhash
pkg font-manager optional
pkg xarchiver
pkg tumbler
pkg gvfs-backends
pkg udisks2
cfg "Thunar custom actions" "$HOME/.config/Thunar/uca.xml" optional

# --- 4. Desktop apps & essentials ----------------------------------------
pkg xfce4-power-manager
pkg dunst
pkg flameshot
pkg xfce4-pulseaudio-plugin
pkg xfce4-taskmanager
pkg light-locker
pkg lightdm-gtk-greeter-settings optional
pkg pavucontrol optional
pkg smbclient optional
pkg cifs-utils optional
bin xflock4
pkg xfce4-clipman-plugin optional
pkg ristretto optional
pkg atril optional
pkg vlc optional
pkg firefox-esr
pkg flatpak
pkg timeshift
pkg redshift optional
pkg network-manager optional
pkg chrony optional
pkg tlp optional
pkg fwupd optional
pkg ffmpeg
pkg fonts-noto-color-emoji
pkg fastfetch
pkg codium optional
bin gcc optional
bin g++ optional
pkg python3-numpy optional
pkg python3-matplotlib optional
pkg steam optional
pkg heroic optional
pkg gimp optional
pkg xfce4-whiskermenu-plugin
pkg xfce4-docklike-plugin
pkg xfce4-datetime-plugin
pkg alacritty
pkg brightnessctl optional
pkg gufw optional
pkg gnome-software optional

# --- 5. Fonts -------------------------------------------------------------
if [ -n "$(fc-list 2>/dev/null | grep -i "JetBrainsMono Nerd Font")" ]; then
	report "JetBrainsMono Nerd Font" ok
else
	report "JetBrainsMono Nerd Font" fail "not found — re-run 17-fonts.sh"
fi

# --- 6. Firefox policy ----------------------------------------------------
if [ -f /usr/lib/firefox-esr/distribution/policies.json ]; then
	report "Firefox policies.json" ok
else
	report "Firefox policies.json" warn "not installed (re-run 16-firefox.sh)"
fi
if [ -f /etc/firefox-esr/xfcemlg.js ]; then
	report "Firefox Betterfox defaults" ok
else
	report "Firefox Betterfox defaults" warn "not installed (re-run 16-firefox.sh)"
fi

# --- 7. Darkmatter theme markers -----------------------------------------

# GTK + xfwm4 theme dirs exist
if [ -d "/usr/share/themes/Darkmatter" ]; then
	report "Darkmatter theme dir" ok
else
	report "Darkmatter theme dir" fail "missing — re-run 21-theme.sh"
fi
if [ -d "/usr/share/themes/Darkmatter/xfwm4" ]; then
	report "Darkmatter xfwm4 dir" ok
else
	report "Darkmatter xfwm4 dir" fail "missing — re-run 21-theme.sh"
fi

# Active theme references
CURRENT_GTK=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)
if [[ "$CURRENT_GTK" == "Darkmatter" ]]; then
	report "Active GTK theme" ok "Darkmatter"
else
	report "Active GTK theme" warn "set to '$CURRENT_GTK', expected Darkmatter"
fi
CURRENT_XFWM=$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null || true)
if [[ "$CURRENT_XFWM" == "Darkmatter" ]]; then
	report "Active xfwm4 theme" ok "Darkmatter"
else
	report "Active xfwm4 theme" warn "set to '$CURRENT_XFWM', expected Darkmatter"
fi

# Icons — Zafiro (dark), fetched at install time
if [ -d "/usr/share/icons/Zafiro-icons-Dark" ]; then
	report "Zafiro-icons-Dark dir" ok
else
	report "Zafiro-icons-Dark dir" fail "missing — re-run 21-theme.sh"
fi
CURRENT_ICONS=$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null || true)
if [[ "$CURRENT_ICONS" == "Zafiro-icons-Dark" ]]; then
	report "Active icon theme" ok "Zafiro-icons-Dark"
else
	report "Active icon theme" warn "set to '$CURRENT_ICONS', expected Zafiro-icons-Dark"
fi

# Static picker.colors (power-user widget palette) — engine is gone
XMLG_ENGINE="$HOME/.config/xfcemlg"
cfg "picker.colors" "$XMLG_ENGINE/picker.colors"
if [ -f "$XMLG_ENGINE/picker.colors" ]; then
	if grep -q '^bg0=#121113' "$XMLG_ENGINE/picker.colors" 2>/dev/null; then
		report "picker palette" ok "Darkmatter bg0 present"
	else
		report "picker palette" warn "picker.colors present but bg0 is not Darkmatter"
	fi
fi

# The old palette engine must be long gone
if [ -e "$XMLG_ENGINE/lib/theme-apply.sh" ] || [ -e "$HOME/.local/bin/xfce-theme-list" ]; then
	report "old theme engine absent" fail "theme engine leftovers found (re-run 21-theme.sh)"
else
	report "old theme engine absent" ok
fi
if [ -e "$HOME/.config/gtk-3.0/gtk.css" ]; then
	report "legacy session gtk.css absent" warn "present — Darkmatter themes itself, this is obsolete (remove it)"
else
	report "legacy session gtk.css absent" ok
fi

# Power-user commands (24-power-user.sh)
cfg "xfce-menu" "$HOME/.local/bin/xfce-menu"
cfg "xfce-update-gui" "$HOME/.local/bin/xfce-update-gui"
cfg "xfce-update-check" "$HOME/.local/bin/xfce-update-check"
cfg "xfce-lock" "$HOME/.local/bin/xfce-lock"
cfg "xfce-suspend" "$HOME/.local/bin/xfce-suspend"
# The file existing is not the same as suspend working. xfce-suspend walks a
# fallback chain (xfce4-session-logout, then busctl) and, if neither
# resolves, prints a diagnostic and exits 1 — so on a degraded install the
# command is present, the health check above says "ok", and the user only
# finds out when the laptop does not sleep. Resolve the chain here instead.
if [ -f "$HOME/.local/bin/xfce-suspend" ]; then
	if command -v xfce4-session-logout >/dev/null 2>&1; then
		report "suspend works" ok "xfce4-session-logout --suspend (xfce4-session)"
	elif command -v busctl >/dev/null 2>&1; then
		report "suspend works" warn "only the busctl fallback resolves (no xfce4-session-logout); install xfce4-session"
	else
		report "suspend works" fail "xfce-suspend is deployed but NEITHER xfce4-session-logout NOR busctl is installed — it will only print an error. Install xfce4-session (or elogind for busctl)."
	fi
fi
if crontab -l 2>/dev/null | grep -q 'xfce-update-check'; then
	report "update cron" ok "xfce-update-check scheduled (09:00 + 18:00)"
else
	report "update cron" warn "no cron entry for xfce-update-check (re-run 24-power-user.sh)"
fi

# Alacritty installed + configured (TOML, Post-0.13)
bin alacritty
cfg "alacritty config" "$HOME/.config/alacritty/alacritty.toml"
if grep -q '^TerminalEmulator=alacritty' "$HOME/.config/xfce4/helpers.rc" 2>/dev/null; then
	report "default terminal" ok "alacritty (helpers.rc)"
else
	report "default terminal" warn "not set to alacritty in helpers.rc (re-run 21-theme.sh)"
fi
XTERM_ALT=$(update-alternatives --get-selections 2>/dev/null | grep '^x-terminal-emulator' || true)
if echo "$XTERM_ALT" | grep -q alacritty; then
	report "x-terminal-emulator alt" ok "alacritty"
else
	report "x-terminal-emulator alt" warn "not set to alacritty (re-run 21-theme.sh)"
fi

# Fastfetch installed + configured
pkg fastfetch
cfg "fastfetch config" "$HOME/.config/fastfetch/config.jsonc"
cfg "fastfetch Devuan logo" "$HOME/.config/fastfetch/devuan.txt"

# Panel: docklike present, genmon gone (panel seeded by 21-theme.sh)
PANEL_XML="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
if [ -f "$PANEL_XML" ]; then
	HAS_DOCKLIKE=$(grep -c 'docklike' "$PANEL_XML" 2>/dev/null || true)
	HAS_GENMON=$(grep -c 'genmon' "$PANEL_XML" 2>/dev/null || true)
	HAS_DOCKLIKE=${HAS_DOCKLIKE:-0}
	HAS_GENMON=${HAS_GENMON:-0}
	if [[ "$HAS_DOCKLIKE" -gt 0 ]]; then
		report "panel XML" ok "docklike plugin present"
	else
		report "panel XML" warn "missing docklike ref (re-run 21-theme.sh)"
	fi
	if [[ "$HAS_GENMON" -gt 0 ]]; then
		report "panel genmon absent" warn "genmon refs still in panel XML — removing it broke nothing, but clean it manually"
	else
		report "panel genmon absent" ok
	fi
	if grep -q 'digital-time-font' "$PANEL_XML" 2>/dev/null; then
		report "panel clock font" ok "$(grep -o 'digital-time-font[^/]*' "$PANEL_XML" | sed 's/.*value="//;s/"$//')"
	else
		report "panel clock font" warn "clock font not seeded (re-run 21-theme.sh)"
	fi
else
	report "panel XML" warn "missing (re-run 21-theme.sh)"
fi

# Window manager: title font + decorations seeded from configs/xfce4/
XFWM_XML="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
if [ -f "$XFWM_XML" ] && grep -q 'title_font' "$XFWM_XML" 2>/dev/null; then
	report "xfwm title font" ok "$(grep -o 'title_font[^/]*' "$XFWM_XML" | sed 's/.*value="//;s/"$//')"
else
	report "xfwm title font" warn "not seeded (re-run 21-theme.sh)"
fi

# Update helper script (30-desktop-essentials.sh)
if [ -x "$HOME/.local/bin/check-apt-updates.sh" ]; then
	report "update helper script" ok
else
	report "update helper script" warn "missing (re-run 30-desktop-essentials.sh)"
fi
# Compositor — xfwm4 built-in (picom is gone)
XCOMP=$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || true)
if [ "$XCOMP" = "true" ]; then
	report "xfwm4 compositor" ok "built-in (use_compositing, shadows + dim)"
else
	report "xfwm4 compositor" warn "use_compositing not enabled (re-run 21-theme.sh)"
fi
if [ -e "$HOME/.config/autostart/picom.desktop" ] || [ -d "$HOME/.config/picom" ]; then
	report "picom absent" warn "picom leftovers present (re-run 21-theme.sh)"
else
	report "picom absent" ok "no leftover autostart or config"
fi

# Wallpapers
if [ -d "/usr/share/backgrounds/xfce/devuan-darkmatter" ]; then
	WP_COUNT=$(ls /usr/share/backgrounds/xfce/devuan-darkmatter/*.{jpg,jpeg,png} 2>/dev/null | wc -l)
	report "wallpapers" ok "${WP_COUNT} files"
else
	report "wallpapers" warn "missing (re-run 21-theme.sh)"
fi

# LightDM greeter CSS (root-only dir — skip inspection when unreadable)
if [ -r /var/lib/lightdm/.config/gtk-3.0/gtk.css ]; then
	if grep -q '#121113' /var/lib/lightdm/.config/gtk-3.0/gtk.css 2>/dev/null; then
		report "greeter login-box CSS" ok "Darkmatter"
	else
		report "greeter login-box CSS" warn "present but not Darkmatter (re-run 22-theme-boot.sh)"
	fi
elif [ ! -r /var/lib/lightdm ] && [ -e /var/lib/lightdm ]; then
	report "greeter login-box CSS" info "root-only; run as root to inspect"
else
	report "greeter login-box CSS" warn "missing (re-run 22-theme-boot.sh)"
fi
if [ -f /etc/lightdm/lightdm-gtk-greeter.conf ] && grep -q "^\[greeter\]" /etc/lightdm/lightdm-gtk-greeter.conf; then
	report "LightDM greeter themed" ok
else
	report "LightDM greeter themed" warn "not themed (re-run 22-theme-boot.sh)"
fi
if grep -q "^user-background = false" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
	report "greeter keeps staged art" ok "user-background = false"
else
	report "greeter keeps staged art" warn "user-background not pinned (re-run 22-theme-boot.sh)"
fi

# --- 8. Services -----------------------------------------------------------
service_state lightdm lightdm critical
service_state bluetooth bluetoothd optional
service_state tlp tlp optional
service_state cups cupsd optional
service_state chrony chronyd optional
# `ufw status` refuses to run unprivileged ("You need to be root to run this
# script"), so probing it here reported every correctly-configured box as
# "not active" — a permanent false WARN for a normal-user audit, whose advice
# (re-run 30-desktop-essentials.sh) could never clear it. /etc/ufw/ufw.conf is
# world-readable and holds the same ENABLED=yes/no the enable/disable path
# writes, so read that instead; only escalate when the file is missing.
if is_installed ufw; then
	if [ -r /etc/ufw/ufw.conf ]; then
		ufw_enabled=""
		ufw_enabled="$(grep -iE '^ENABLED' /etc/ufw/ufw.conf 2>/dev/null | head -1 |
			grep -qiE '^ENABLED=yes' && echo yes || echo no)"
		if [ "$ufw_enabled" = "yes" ]; then
			report "ufw firewall" ok "active (/etc/ufw/ufw.conf ENABLED=yes)"
		else
			report "ufw firewall" warn "installed but disabled (re-run 30-desktop-essentials.sh)"
		fi
	elif priv -n ufw status 2>/dev/null | grep -qi "Status: active"; then
		report "ufw firewall" ok "active"
	else
		report "ufw firewall" warn "installed, state unreadable without root (run: doas ufw status)"
	fi
else
	report "ufw firewall" warn "ufw not installed"
fi
if [ -f "$HOME/.config/redshift.conf" ]; then
	report "redshift config" ok
else
	report "redshift config" warn "missing (re-run 30-desktop-essentials.sh)"
fi
if [ -d "$HOME/.config/autostart" ] && ls "$HOME/.config/autostart/"*.desktop >/dev/null 2>&1; then
	report "user autostart entries" ok "$(ls "$HOME/.config/autostart/"*.desktop 2>/dev/null | wc -l) entries"
else
	report "user autostart entries" warn "none found"
fi
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
	service_state NetworkManager NetworkManager optional
else
	service_state network-manager NetworkManager optional
fi
if command -v nmcli >/dev/null 2>&1; then
	if nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -q ':wifi:unmanaged'; then
		report "wifi managed" warn "a wifi device is unmanaged (re-run 10-xfce-core.sh)"
	else
		report "wifi managed" ok
	fi
else
	report "wifi managed" warn "nmcli not found (10-xfce-core.sh installs network-manager)"
fi

# --- 9. Battery maximizer (13-hardware.sh) -------------------------------
if [ -f /etc/tlp.d/70-maxbattery.conf ]; then
	report "TLP max-battery config" ok "/etc/tlp.d/70-maxbattery.conf"
else
	report "TLP max-battery config" warn "missing (re-run 13-hardware.sh)"
fi
if [ -f "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" ] &&
	grep -q 'name="presentation-mode" type="bool" value="false"' "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml"; then
	report "xfce power-manager battery profile" ok "presentation-mode off"
else
	report "xfce power-manager battery profile" warn "presentation-mode on/absent (re-run 13-hardware.sh)"
fi

if [ "$JSON" -eq 1 ]; then
	printf '{"passed":%d,"failed":%d,"warned":%d,"checks":[%s]}\n' \
		"$PASS" "$FAIL" "$WARN" "$(
			IFS=,
			printf '%s' "${JSON_CHECKS[*]}"
		)"
else
	echo
	echo -e "${GREEN}  ${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
fi
if [ "$FAIL" -gt 0 ]; then
	[ "$JSON" -eq 1 ] || log_err "Some checks failed — see lines above, then re-run the relevant script."
	exit 1
fi
exit 0
