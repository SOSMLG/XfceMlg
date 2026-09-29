#!/usr/bin/env bash
# XMLG_DESC: Lean XFCE core (minimal-install path, no tasksel/SLiM)
# XMLG_DEFAULT: Y
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

# --- 1b. Exactly one polkit auth agent ---------------------------------
# polkitd accepts ONE auth agent per subject; on hand-built installs
# lxpolkit / mate-polkit / polkit-gnome routinely sit next to the
# xfce-polkit installed above and one of them dies at login with
# "an authentication agent already exists for the given subject".
# Keep xfce-polkit; mask the rest with user-level Hidden=true overrides
# (package files are never touched — the fix survives upgrades).
ensure_single_polkit_agent

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
# --- 3. LightDM owns the console --------------------------------------
# Exactly one display manager may be enabled. Two of them race for the
# console on every boot and which one wins is arbitrary — on this machine
# BOTH greetd and lightdm were symlinked into the default runlevel:
# lightdm happened to win and greetd sat there owning no session, waiting
# for a boot where it might not lose. The previous code only printed a
# warning about greetd, so the conflict survived every run.
#
# This section is therefore the fix, not a warning. Taking a rival out of
# the runlevel is reversible (`rc-update add <svc> <runlevel>` restores it),
# so it is offered directly; removing the package is a separate, explicit
# choice afterwards.
DM_RIVALS="slim greetd sddm gdm3 gdm xdm"

# dm_enabled_runlevel <svc> — echo the runlevel that has it enabled, or
# nothing. Reads the runlevel symlinks directly: `rc-update show` pads
# service names with leading spaces, so an anchored ^name grep misses them.
dm_enabled_runlevel() {
	local svc="$1" d
	for d in /etc/runlevels/*/; do
		[ -e "${d}${svc}" ] || continue
		basename "$d"
		return 0
	done
	return 1
}

if is_installed lightdm; then
	start_service lightdm
	normalize_display_manager

	for dm in $DM_RIVALS; do
		[ -x "/etc/init.d/$dm" ] || continue             # not installed: nothing to disable
		dm_rl="$(dm_enabled_runlevel "$dm")" || continue # installed but not enabled: fine

		log_warn "Display manager '$dm' is enabled in the '$dm_rl' runlevel alongside LightDM."
		if ask_no_full "Disable $dm (remove it from $dm_rl) so only LightDM owns the console?" "Y"; then
			if [ -x /usr/sbin/rc-update ]; then
				priv /usr/sbin/rc-update del "$dm" >/dev/null 2>&1 || true
			fi
			if [ -x /usr/sbin/rc-service ]; then
				priv /usr/sbin/rc-service "$dm" stop >/dev/null 2>&1 || true
			fi
			if [ -e "/etc/runlevels/$dm_rl/$dm" ]; then
				log_err "Could not remove $dm from $dm_rl — do it by hand: rc-update del $dm"
			else
				log_ok "Disabled $dm (still installed — restore with: rc-update add $dm $dm_rl)"
			fi
		else
			log_warn "Leaving $dm enabled — it will race LightDM for the console at boot."
		fi

		# Package removal is a distinct, destructive choice: the service
		# may be wanted for something else, or kept for an easy rollback.
		if is_installed "$dm"; then
			if ask_no_full "Purge the $dm package too?" "N"; then
				priv apt-get purge -y "$dm" || log_warn "$dm purge had issues (continuing)."
				log_ok "$dm purged."
			fi
		fi
	done

	# Final proof rather than an assumption: exactly one DM enabled?
	dm_left=""
	for dm in lightdm $DM_RIVALS; do
		[ -x "/etc/init.d/$dm" ] || continue
		dm_enabled_runlevel "$dm" >/dev/null 2>&1 && dm_left="$dm_left $dm"
	done
	set -- $dm_left
	if [ "$#" -eq 1 ]; then
		log_ok "Exactly one display manager enabled: $1"
	elif [ "$#" -eq 0 ]; then
		log_err "No display manager is enabled — the next boot will drop to a TTY."
		log_err "  Fix: rc-update add lightdm default"
	else
		log_err "More than one display manager is still enabled:$dm_left"
		log_err "  Fix: for each one you do not want — rc-update del <name> default"
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

	# Every file ifupdown actually reads: the main file plus whatever its
	# `source` / `source-directory` lines pull in (one level of nesting,
	# with a visited guard so a cycle cannot hang). The old check read only
	# the main file and explicitly `next`ed on `source` lines, so any claim
	# living in /etc/network/interfaces.d/ was invisible — the script would
	# print "already loopback-only" and leave a genuine double-ownership in
	# place (ifupdown's `ifup -a` at sysinit, plus NM with managed=true).
	ifaces_effective_files() {
		local queue=("$INTERFACES_FILE") seen="" cur kw spath f
		while [ ${#queue[@]} -gt 0 ]; do
			cur="${queue[0]}"
			queue=("${queue[@]:1}")
			case " $seen " in *" $cur "*) continue ;; esac
			seen="$seen $cur"
			[ -f "$cur" ] || continue
			printf '%s\n' "$cur"
			# Split keyword from path with an explicit separator. Do NOT
			# squeeze whitespace here: doing so glues "source" onto the
			# path, and ${x#source/} then eats the separator *and* the
			# path's leading "/", turning every absolute path relative so
			# its glob silently matches nothing.
			while IFS='@' read -r kw spath; do
				spath="${spath%%#*}"
				spath="${spath#"${spath%%[![:space:]]*}"}"
				spath="${spath%"${spath##*[![:space:]]}"}"
				[ -n "$spath" ] || continue
				case "$kw" in
				source)
					# `source` takes a GLOB path and ifupdown reads
					# every match. The file this very script writes
					# is `source /etc/network/interfaces.d/*`, so
					# not expanding the glob would miss the whole
					# drop-in directory — which is the exact blind
					# spot being fixed.
					case "$spath" in
					*'*'* | *'?'* | *'['*)
						# shellcheck disable=SC2086 # glob on purpose
						for f in $spath; do
							[ -f "$f" ] && queue+=("$f")
						done
						;;
					*)
						queue+=("$spath")
						;;
					esac
					;;
				source-directory)
					[ -d "$spath" ] || continue
					for f in "$spath"/*; do
						[ -f "$f" ] && queue+=("$f")
					done
					;;
				esac
			done < <(sed -n -E 's/^[[:space:]]*(source|source-directory)[[:space:]]+/\1@/p' "$cur" 2>/dev/null)
		done
	}

	if [[ -f "$INTERFACES_FILE" ]]; then
		ifaces_files=()
		while IFS= read -r _f; do
			[ -n "$_f" ] && ifaces_files+=("$_f")
		done < <(ifaces_effective_files)

		# Reports WHERE a non-loopback interface is claimed, so the log
		# names the drop-in rather than just saying "something claims one".
		ifaces_claim="$(awk '
            /^[[:space:]]*($|#)/ { next }
            /^(auto|allow-[a-z-]+)[[:space:]]/ {
                for (i = 2; i <= NF; i++)
                    if ($i != "lo") { printf "%s:%d: `%s` claims %s\n", FILENAME, FNR, $1, $i; exit }
                next
            }
            /^iface[[:space:]]/ {
                if ($2 != "lo") { printf "%s:%d: `iface` claims %s\n", FILENAME, FNR, $2; exit }
            }
        ' "${ifaces_files[@]}" 2>/dev/null)"

		if [ -n "$ifaces_claim" ]; then
			log_info "ifupdown claims a non-loopback interface:"
			printf '%s\n' "$ifaces_claim" | while IFS= read -r _l; do
				log_info "  $_l"
			done
			BACKUP="${INTERFACES_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
			priv cp "$INTERFACES_FILE" "$BACKUP"
			log_info "Backed up $INTERFACES_FILE to $BACKUP"
			priv tee "$INTERFACES_FILE" >/dev/null <<'EOF'
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
				printf '\n[ifupdown]\nmanaged=true\n' | priv tee -a "$NM_CONF" >/dev/null
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
