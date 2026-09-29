#!/usr/bin/env bash
# XMLG_DESC: firmware, microcode, fwupd, TLP battery maximizer, boot params, XFCE power profile, ThinkPad extras
# XMLG_DEFAULT: Y
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

log_head "1/5  WiFi/Bluetooth firmware"
if ask "Install common WiFi/Bluetooth firmware (Intel/Realtek/Atheros/Broadcom)?"; then
	install_pkgs "WiFi/Bluetooth firmware" \
		firmware-iwlwifi firmware-realtek firmware-atheros \
		firmware-brcm80211 firmware-misc-nonfree firmware-linux
fi

log_head "2/5  CPU microcode (auto-detected)"
if ask "Install CPU microcode updates?"; then
	VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
	case "$VENDOR" in
	GenuineIntel)
		log_info "Detected Intel CPU."
		install_pkgs "Intel microcode" intel-microcode
		;;
	AuthenticAMD)
		log_info "Detected AMD CPU."
		install_pkgs "AMD microcode" amd64-microcode
		;;
	*) log_warn "Could not detect CPU vendor, skipping microcode." ;;
	esac
fi

log_head "3/5  fwupd (BIOS/UEFI + peripheral firmware updates)"
if ask "Install fwupd?"; then
	install_pkgs "fwupd" fwupd

	start_service fwupd
	log_ok "fwupd installed. Check for updates with: fwupdmgr get-updates"
fi

log_head "4/5  TLP (laptop power management, battery maximizer, ThinkPad charge thresholds)"
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
				# Don't silently overwrite a threshold someone already chose.
				# The previous version hard-wrote START=75 every run, so
				# re-running this script quietly raised a deliberately
				# lower START (e.g. the 60 set by hand on this box) back
				# to 75. A lower START is more conservative, so keep it
				# and say so instead of clobbering it.
				THRESH_CONF="/etc/tlp.d/60-battery-threshold.conf"
				existing_start=""
				if [[ -f "$THRESH_CONF" ]]; then
					existing_start=$(sed -n -E 's/^[[:space:]]*START_CHARGE_THRESH_BAT0="?([0-9]+)"?[[:space:]]*$/\1/p' \
						"$THRESH_CONF" 2>/dev/null | tail -1)
				fi
				start_thresh=75
				if [[ -n "$existing_start" && "$existing_start" -lt 75 ]]; then
					start_thresh="$existing_start"
					log_info "Keeping your existing START threshold of ${existing_start}% (lower than the 75% this script would write)."
				elif [[ -n "$existing_start" && "$existing_start" != 75 ]]; then
					log_info "Existing START threshold is ${existing_start}%; lowering it to 75%."
				fi

				priv mkdir -p /etc/tlp.d
				priv tee "$THRESH_CONF" >/dev/null <<EOF
# Written by 13-hardware.sh — charge threshold for ${BAT_NAME}.
# Full-charge fans of 100% can delete this file and run: doas tlp start
START_CHARGE_THRESH_BAT0=${start_thresh}
STOP_CHARGE_THRESH_BAT0=80
EOF
				priv tlp start &>/dev/null || true
				# Report what the hardware actually took, not what we asked
				# for: the EC can refuse or clamp a threshold, and the old
				# code claimed "capped at 80%" purely because the write
				# succeeded. (On this box the EC silently kept 80/80 and
				# ignored a 60% START, which this makes visible.)
				effective_stop="$(cat "${BAT_PATH}/charge_control_end_threshold" 2>/dev/null)"
				if [[ -n "$effective_stop" ]]; then
					log_ok "Charge threshold accepted by hardware: stops at ${effective_stop}%, resumes at ${start_thresh}%."
				else
					log_warn "Wrote $THRESH_CONF but the hardware reports no threshold — the EC may ignore it. Check: cat ${BAT_PATH}/charge_control_end_threshold"
				fi
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
		#
		# Only the battery side is pinned here. AC is deliberately left to
		# TLP's own defaults: the right AC governor/EPP pair is
		# driver-specific (on this AMD box amd-pstate-epp maps TLP's AC
		# default to governor=powersave with EPP=balance_performance, not
		# to governor=performance), so hardcoding a guessed pair would
		# change AC behaviour on hardware the script was not written for.
		# The effective AC policy is reported below instead.
		priv mkdir -p /etc/tlp.d
		priv tee /etc/tlp.d/70-maxbattery.conf >/dev/null <<'EOF'
# Written by 13-hardware.sh — battery maximizer (balanced, CPU boost preserved).
# Battery only; AC stays at TLP's driver-appropriate defaults.
CPU_ENERGY_PERF_POLICY_ON_BAT=power
PCIE_ASPM_ON_BAT=powersave
EOF
		if priv tlp start >/dev/null 2>&1; then
			log_ok "Battery maximizer applied: CPU EPP=power + PCIe ASPM=powersave on battery (boost kept)."
			log_info "Tuned via /etc/tlp.d/70-maxbattery.conf — edit it to undo. Inspect with: tlp-stat -c"
			# Show the policy that is actually in force, AC included, rather
			# than asking the user to take "applied" on trust.
			eff_gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
			eff_epp="$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
			if [[ -n "$eff_gov" || -n "$eff_epp" ]]; then
				log_info "Effective now (${*:-unknown source}): governor=${eff_gov:-n/a} EPP=${eff_epp:-n/a}"
			fi
		else
			log_warn "tlp start failed after tuning — inspect with: tlp-stat -c"
		fi

		# --- Resume hook -------------------------------------------------
		# Without this, `tlp resume` never runs and none of the policy
		# above survives a suspend: the 80% cap, the CPU governor/EPP and
		# wifi.powersave are all left as the pre-suspend kernel set them,
		# because an s2idle resume restores kernel power state but not
		# userspace policy.
		#
		# It is needed because TLP's own two sleep hooks are both dead
		# here. TLP installs 49-tlp-sleep into /usr/lib/elogind/system-sleep
		# and tlp into /usr/lib/systemd/system-sleep — but elogind
		# 255.17-2 scans neither. It scans exactly two directories, and
		# the one that would let us own the file does not exist until
		# something creates it.
		HOOK_SRC="$SCRIPT_DIR/../configs/system-sleep/50-xfcemlg-tlp"
		HOOK_DIR="/etc/elogind/system-sleep"
		HOOK_DST="$HOOK_DIR/50-xfcemlg-tlp"
		if [[ -f "$HOOK_SRC" ]]; then
			if priv mkdir -p "$HOOK_DIR" &&
				priv install -m 0755 "$HOOK_SRC" "$HOOK_DST" 2>/dev/null; then
				log_ok "Resume hook installed at $HOOK_DST (re-applies TLP after suspend)."
			else
				log_warn "Could not install $HOOK_DST — TLP policy will not be re-applied after a resume. Create it by hand from $HOOK_SRC."
			fi
		else
			log_warn "Resume hook source missing ($HOOK_SRC) — skipping."
		fi
	fi
fi

log_head "5/5  XFCE Power Manager — battery-first profile"
if ask "Apply battery-first power-manager profile (blank 3/10 min, suspend 30 min, brightness 55% on battery)?"; then
	# ------------------------------------------------------------------
	# Property names come from an explicit allowlist, on purpose.
	#
	# `xfconf-query -n` creates ANY key and returns success. The previous
	# version of this block set `brightness-on-ac` / `brightness-on-battery`
	# and cheerfully logged "pm brightness-on-ac = 100 (new)" — but those
	# names do not exist in xfce4-power-manager. Checked against the
	# xfce4-power-manager-4.20.0 tag: the real properties are
	# `brightness-level-on-ac` / `brightness-level-on-battery`
	# (settings/xfpm-settings.c), and the string "brightness-on-ac" does
	# not occur anywhere upstream. So the old code created two dead keys
	# and reported success, and battery brightness was never actually set.
	#
	# A substring search of the daemon binary is NOT a usable guard here:
	# the settings GUI's widget id is also "brightness-on-ac", so it
	# false-positives. This list is therefore the single source of truth,
	# and tests/consistency.sh binds it to the seed XML so the script and
	# the seed cannot drift apart again.
	# ------------------------------------------------------------------
	XFPM_PROPS="presentation-mode dpms-enabled
inactivity-on-ac inactivity-on-battery
dpms-on-ac-off dpms-on-ac-sleep dpms-on-battery-off dpms-on-battery-sleep
lid-action-on-ac lid-action-on-battery logind-handle-lid-switch
brightness-level-on-ac brightness-level-on-battery"

	# Idempotent setter: -n create only when the property is new, plain -s on re-run.
	pm_set() {
		local prop="$1" type="$2" value="$3"
		local path="/xfce4-power-manager/$prop"
		case " $XFPM_PROPS " in
		*" $prop "*) ;;
		*)
			log_err "Refusing to write '$prop': not a real xfce4-power-manager property."
			log_err "  xfconf would accept it and XFPM would silently ignore it."
			return 1
			;;
		esac
		if xfconf-query -c xfce4-power-manager -l 2>/dev/null | grep -qx "$path"; then
			xfconf-query -c xfce4-power-manager -p "$path" -s "$value" 2>/dev/null &&
				log_info "pm $prop = $value" ||
				log_warn "Could not set $prop via xfconf — a running desktop session is needed (the seed carries it for fresh installs)."
		else
			xfconf-query -c xfce4-power-manager -n -p "$path" -t "$type" -s "$value" 2>/dev/null &&
				log_info "pm $prop = $value (new)" ||
				log_warn "Could not set $prop via xfconf — a running desktop session is needed (the seed carries it for fresh installs)."
		fi
	}

	# Lid integers, from XfpmLidTriggerAction in common/xfpm-enum-glib.h
	# (4.20.0). The old comment here read "3 = suspend, 0 = do nothing".
	# Both were wrong, and the effect was the opposite of the intent:
	#   0 LID_TRIGGER_DPMS         blank the display
	#   1 LID_TRIGGER_SUSPEND      suspend
	#   2 LID_TRIGGER_HIBERNATE    hibernate
	#   3 LID_TRIGGER_LOCK_SCREEN  lock the screen
	#   4 LID_TRIGGER_NOTHING      do nothing
	#   5 LID_TRIGGER_HYBRID_SLEEP hybrid sleep
	#   6 LID_TRIGGER_SHUTDOWN     shut down
	# So battery=3 LOCKED on lid close instead of suspending, and AC=0
	# BLANKED the screen instead of doing nothing. Correct: 1 and 4.
	pm_set lid-action-on-battery uint 1
	pm_set lid-action-on-ac uint 4

	# elogind's own HandleLidSwitch defaults to true and acts on the lid
	# before XFPM ever sees it; false hands the decision to XFPM alone.
	pm_set logind-handle-lid-switch bool false

	# Blanking has to be possible in the first place. presentation-mode
	# pins the screen awake — it was live-true on this box, so the screen
	# never blanked on AC or battery, which is what made the dpms-on-*
	# timers below do nothing. dpms-enabled=false would disable DPMS
	# outright and make those timers meaningless too.
	pm_set presentation-mode bool false
	pm_set dpms-enabled bool true

	pm_set inactivity-on-ac uint 10
	pm_set inactivity-on-battery uint 3
	pm_set dpms-on-ac-off uint 10
	pm_set dpms-on-ac-sleep uint 0
	pm_set dpms-on-battery-off uint 3
	pm_set dpms-on-battery-sleep uint 30

	# Real names, NOT brightness-on-{ac,battery}.
	pm_set brightness-level-on-ac uint 100
	pm_set brightness-level-on-battery uint 55

	# Remove the two dead keys older versions of this script created, so
	# they stop appearing in the power-manager property list implying
	# they mean something.
	for dead_prop in brightness-on-ac brightness-on-battery; do
		if xfconf-query -c xfce4-power-manager -l 2>/dev/null | grep -qx "/xfce4-power-manager/$dead_prop"; then
			xfconf-query -c xfce4-power-manager -r "/xfce4-power-manager/$dead_prop" 2>/dev/null &&
				log_ok "Removed dead property $dead_prop (XFPM never read it)."
		fi
	done

	log_ok "Battery-first power profile applied (lid closes → suspend on battery, do nothing on AC)."
	log_info "The matching profile is seeded in configs/xfce4/ so fresh installs get it too."
fi

log_ok "Hardware support complete."
log_warn "A reboot is recommended so newly installed firmware/microcode is loaded."

# ---------------------------------------------------------------------------
# ThinkPad-specific extras (auto-detected, only offered on matching hardware)
# ---------------------------------------------------------------------------
IS_THINKPAD=0
if [[ -d /sys/devices/platform/thinkpad_acpi ]] ||
	grep -qi "thinkpad" /sys/class/dmi/id/product_name 2>/dev/null ||
	grep -qi "thinkpad" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
	IS_THINKPAD=1
fi

if [[ "$IS_THINKPAD" -eq 1 ]]; then
	echo
	log_head "ThinkPad extras (auto-detected)"

	# Default Y: benign install, and this block only runs on ThinkPads — a
	# full/unattended run installs thinkfan without prompting.
	if ask_no_full "Install thinkfan (thermal management for ThinkPads)?"; then
		install_pkgs "ThinkFan" thinkfan
		start_service thinkfan
		log_ok "thinkfan installed. Edit /etc/thinkfan.conf to tune fan curves."
		log_info "Default: conservative — edit thresholds or run: doas thinkfan -n"
	fi

	# Default Y — same rationale as thinkfan: benign, ThinkPad-only.
	if ask_no_full "Install powertop with auto-tune on boot (power savings)?"; then
		install_pkgs "PowerTOP" powertop
		# Create a oneshot service/RC script for powertop --auto-tune
		POWERTOP_SERVICE="/etc/init.d/powertop-autotune"
		if [[ ! -f "$POWERTOP_SERVICE" ]]; then
			priv tee "$POWERTOP_SERVICE" >/dev/null <<'POWEOF'
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
