#!/usr/bin/env bash
# XMLG_DESC: Long-run maintenance — fstrim, apt cache, SMART, tmpfiles, litter pruning
# XMLG_DEFAULT: Y
# =======================================================
# 53-longrun.sh — long-run maintenance for a box that stays up
# -------------------------------------------------------
# A fresh XFCE install is fine on day one and quietly degrades
# over months: an SSD nobody ever TRIMs, a multi-GB apt archive
# nobody autocleans, no disk-health data at all, and a few
# hundred MB of "litter" in the home directory. Everything this
# step does is either "put the machine back on a timer" or
# "measure and report", using the mechanism the distribution
# itself uses for that class of work. No hand-rolled daemons, no
# systemd.
#
# Six jobs:
#   1. fstrim        weekly via /etc/cron.d — util-linux fstrim
#                    needs root, so a user crontab cannot host it
#   2. smartmontools install + a one-time SMART summary (read-only)
#   3. apt archive   /etc/apt/apt.conf.d autoclean keys, which the
#                    apt.systemd.daily job ALREADY scheduled via
#                    /etc/cron.daily/apt-compat consumes — so this
#                    adds no second scheduler and no duplicate run
#   4. ~/Trash + ~/.cache   bounded, age-limited, on-demand trim
#   5. tmpfiles.d    declarative drop-in for the toolkit's own
#                    paths, system scope and user scope
#   6. xfwm4-*.state prune: old AND its window id no longer resolves
#
# SAFETY CONTRACT
#   Every action that DELETES data (§3 autoclean, §4 trims, §6
#   prune) sits behind ask_no_full with default N. ask_no_full
#   ignores XMLG_FULL, so `./run.sh --full` and install.sh can
#   never delete anything: the answer there is the default, "no".
#   Everything else is either read-only (SMART) or a
#   content-compare-then-write config drop, so a second run is a
#   genuine no-op — same bytes, untouched mtime.
#
# WHY THE NON-DELETIVE PARTS ARE NOT BEHIND ask_no_full
#   - fstrim does not delete data. TRIM/discard tells the SSD
#     which LBAs are no longer referenced; a wrong TRIM wastes
#     space, it cannot lose a file. It defaults to yes for the same
#     reason security updates do.
#   - Writing apt.conf.d / tmpfiles.d / cron.d is additive
#     configuration, not data loss.
#   - SMART reads are read-only.
#
# Tunables (all optional, env-overridable):
#   XMLG_TRIM_DOW       0-6, day of week for fstrim  (default 0 = Sun)
#   XMLG_TRIM_HOUR      0-23, hour for fstrim        (default 3)
#   XMLG_APT_CLEAN_DAYS apt autoclean interval, days (default 7)
#   XMLG_LITTER_DAYS    age limit for Trash / ~/.cache / xfwm4
#                       state files                 (default 30)
#
# Privilege: priv() (doas-first, sudo fallback). Never bare sudo/doas.
# Init: OpenRC on sysvinit — this file never calls systemctl.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

# ------------------------------------------------------------------ knobs
TRIM_DOW="${XMLG_TRIM_DOW:-0}"
TRIM_HOUR="${XMLG_TRIM_HOUR:-3}"
APT_CLEAN_DAYS="${XMLG_APT_CLEAN_DAYS:-7}"
LITTER_DAYS="${XMLG_LITTER_DAYS:-30}"
case "$TRIM_DOW" in [0-6]) ;; *) TRIM_DOW=0 ;; esac
case "$TRIM_HOUR" in
[0-9] | [1-9] | 1[0-9] | 2[0-3]) TRIM_HOUR=$((10#$TRIM_HOUR)) ;;
*) TRIM_HOUR=3 ;;
esac
case "$APT_CLEAN_DAYS" in
[1-9] | [1-9][0-9]) ;;
*) APT_CLEAN_DAYS=7 ;;
esac
case "$LITTER_DAYS" in
[0-9] | [1-9][0-9] | [1-9][0-9][0-9]) ;;
*) LITTER_DAYS=30 ;;
esac

# The invoking user's home, resolved from the account rather than from
# $HOME, so a doas/sudo re-entry can never point a trim at /root.
TARGET_HOME="$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6)"
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then TARGET_HOME="$HOME"; fi

# ----------------------------------------------------------------- helpers

# can_escalate — true if a privilege escalator will work RIGHT NOW (warm
# doas persist / sudo timestamp, or we are already root). Lets a skipped
# privileged step be reported as "could not", never as "done".
can_escalate() { priv -n true >/dev/null 2>&1; }

# note_no_escalation <what> — honest message when a privileged step
# cannot run in this context (cron, CI, a headless test).
note_no_escalation() {
	log_warn "$1: no working privilege escalator right now (priv -n true failed)."
	log_warn "  Nothing was changed. Re-run this step interactively to apply it."
}

# human_bytes <n> — 1503238553 -> 1.4GB
human_bytes() {
	local n="${1:-0}"
	numfmt --to=iec --suffix=B --format='%.1f' "$n" 2>/dev/null || printf '%sB' "$n"
}

# bytes_of <path> [path...] — total size in bytes; 0 when absent/unreadable.
bytes_of() {
	local total
	total="$(du -sc --block-size=1 -- "$@" 2>/dev/null | tail -1 | cut -f1)"
	case "$total" in
	'' | *[!0-9]*) printf '0' ;;
	*) printf '%s' "$total" ;;
	esac
}

# write_root_file_if_changed <path> <mode> <srcfile> <label>
# The idempotency primitive: compare content, write only on a real
# difference. A second run leaves the file — its mtime, and any package
# trigger that watches it — completely untouched.
write_root_file_if_changed() {
	local path="$1" mode="$2" src="$3" label="$4"
	local want cur
	want="$(cat "$src" 2>/dev/null || true)"
	cur="$(priv cat "$path" 2>/dev/null || true)"
	if [ -n "$cur" ] && [ "$cur" = "$want" ]; then
		log_ok "$label: $path already current — left untouched (no write)."
		return 0
	fi
	if [ -n "$cur" ]; then
		priv cp -a "$path" "${path}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
	fi
	if priv install -m "$mode" -o root -g root "$src" "$path"; then
		log_ok "$label: wrote $path (mode $mode)."
		return 0
	fi
	log_err "$label: could not write $path (escalation failed)."
	return 1
}

# write_user_file_if_changed <path> <srcfile> <label> — same, without priv.
write_user_file_if_changed() {
	local path="$1" src="$2" label="$3"
	mkdir -p "$(dirname "$path")" 2>/dev/null || {
		log_err "$label: cannot create $(dirname "$path")"
		return 1
	}
	if [ -f "$path" ] && cmp -s "$path" "$src"; then
		log_ok "$label: $path already current — left untouched (no write)."
		return 0
	fi
	if install -m 0644 "$src" "$path"; then
		log_ok "$label: wrote $path."
		return 0
	fi
	log_err "$label: could not write $path."
	return 1
}

# Reference file whose mtime is exactly $LITTER_DAYS ago, so a single-file
# age test is a plain `[ f -ot ref ]` instead of a find(1) per file.
AGE_MARK="$(mktemp)"
touch -d "@$(($(date +%s) - LITTER_DAYS * 86400))" "$AGE_MARK" 2>/dev/null || true
# Single-quoted so AGE_MARK is expanded when the trap fires, not now: the
# temp file has to outlive every comparison made below.
trap 'rm -f "$AGE_MARK"' EXIT

# escalation_ok — true when a privileged step can proceed *without* an
# interactive password prompt: we are root, a warm persist timestamp
# exists, or there is a tty to prompt on. Keeps `bash 53-longrun.sh` from
# stalling on a doas password when it runs unattended (cron, CI, a pipe)
# while preserving normal prompting for a human at a terminal.
escalation_ok() { can_escalate || [ -t 0 ]; }

CRON_D_LONGRUN="/etc/cron.d/xfcemlg-longrun"
CRON_MARKER="# xfcemlg: fstrim"
APT_CONF="/etc/apt/apt.conf.d/99xfcemlg-autoclean"
TMPF_SYS="/etc/tmpfiles.d/xfcemlg-longrun.conf"
TMPF_USER="$TARGET_HOME/.config/user-tmpfiles.d/xfcemlg-longrun.conf"

# ==================================================================
log_head "Long-run maintenance (53-longrun.sh)"

# ------------------------------------------------------------------
# 1/6  fstrim — SSD TRIM, weekly
# ------------------------------------------------------------------
log_head "1/7  SSD TRIM (fstrim)"

TRIM_BIN=""
for c in fstrim /usr/sbin/fstrim /sbin/fstrim; do
	if command -v "$c" >/dev/null 2>&1; then
		TRIM_BIN="$(command -v "$c")"
		break
	fi
done

if [ -z "$TRIM_BIN" ]; then
	log_warn "fstrim not found in PATH (util-linux missing, or a trimmed install)."
	log_warn "  Nothing scheduled, nothing run. Install it with: apt-get install util-linux"
else
	ROOT_FSTYPE="$(findmnt -no FSTYPE / 2>/dev/null || true)"
	if [ -z "$ROOT_FSTYPE" ]; then ROOT_FSTYPE="$(stat -f -c %T / 2>/dev/null || true)"; fi
	ROOT_FSTYPE="$(printf '%s' "$ROOT_FSTYPE" | tr '[:upper:]' '[:lower:]')"

	# /etc/fstrim is util-linux's own mount allowlist. Debian does not
	# ship one, so fall back to a fstype test rather than assuming.
	TRIM_TARGET=""
	if [ -f /etc/fstrim ]; then
		log_info "/etc/fstrim found — fstrim will honour its mount allowlist."
	else
		case "$ROOT_FSTYPE" in
		xfs | ext2 | ext3 | ext4 | btrfs | f2fs | jfs | reiserfs | nilfs2 | ubifs)
			TRIM_TARGET="/"
			;;
		*)
			log_warn "Root filesystem is '$ROOT_FSTYPE', which does not implement discard."
			log_warn "  fstrim would be a no-op there — not scheduling one. Nothing was lost."
			;;
		esac
	fi

	if [ -n "$TRIM_TARGET" ]; then
		log_ok "fstrim: $TRIM_BIN (root fs = $ROOT_FSTYPE, TRIM-capable)."
		# One-time pass now. NOT destructive (see the header), so this is
		# an ordinary ask() and does default to yes under --full.
		if ask "Run one fstrim pass on $TRIM_TARGET now (it only tells the SSD which blocks went free)?" "Y"; then
			if escalation_ok; then
				TRIM_OUT="$(priv "$TRIM_BIN" -v "$TRIM_TARGET" 2>&1)"
				TRIM_RC=$?
				printf '%s\n' "$TRIM_OUT" | sed 's/^/      /'
				if [ "$TRIM_RC" -eq 0 ]; then
					log_ok "One-time fstrim pass completed."
				else
					log_warn "fstrim exited $TRIM_RC (see the output above)."
				fi
			else
				note_no_escalation "one-time fstrim pass"
				log_info "  As root: $TRIM_BIN -v $TRIM_TARGET"
			fi
		else
			log_info "Skipped the one-time fstrim pass (answered no)."
		fi

		# --- weekly schedule. Write the job; never run it here.
		if ask "Schedule a weekly fstrim ($TRIM_TARGET) through $CRON_D_LONGRUN?" "Y"; then
			# logger() keeps this from inventing a new growing log file:
			# it goes to rsyslog, which logrotate already rotates. That
			# is logrotate being used where it genuinely applies — by
			# using it, not by adding a second stanza.
			if command -v logger >/dev/null 2>&1; then
				TRIM_REDIRECT="2>&1 | logger -t xfcemlg-trim -p daemon.info"
			else
				TRIM_REDIRECT=">/dev/null 2>&1"
				log_warn "logger(1) not found — fstrim output will be discarded."
			fi
			CRON_JOB="$(mktemp)"
			CRON_NEW="$(mktemp)"
			{
				echo "$CRON_MARKER"
				echo "# Weekly SSD TRIM. Root-only, hence /etc/cron.d and its 'root'"
				echo "# user field rather than a user crontab. Without this the SSD"
				echo "# never learns which blocks went free, and its garbage"
				echo "# collection degrades with write amplification indefinitely."
				echo "$TRIM_HOUR $TRIM_DOW * * * root $TRIM_BIN -v $TRIM_TARGET $TRIM_REDIRECT"
			} >"$CRON_JOB"
			{
				echo "# $CRON_D_LONGRUN — written by xfcemlg scripts/53-longrun.sh"
				echo "# Safe to delete: the toolkit recreates it on the next run of that step."
				echo "SHELL=/bin/bash"
				echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
				echo 'MAILTO=""'
				echo ""
				# Keep any other job already in the file, but never a second
				# copy of ours: the marker is stripped, and the fstrim binary
				# name is stripped too, so a hand-edited or pre-0.8.0 line
				# cannot survive alongside the new one. This is the same
				# marker + grep -vF discipline scripts/24-power-user.sh uses
				# for the user crontab, and it is what makes a re-run a no-op.
				grep -vF "$CRON_MARKER" "$CRON_D_LONGRUN" 2>/dev/null |
					grep -vF "$TRIM_BIN" || true
				cat "$CRON_JOB"
			} >"$CRON_NEW"
			rm -f "$CRON_JOB"
			if ! escalation_ok; then
				rm -f "$CRON_NEW"
				note_no_escalation "write $CRON_D_LONGRUN"
				log_info "  As root, add to $CRON_D_LONGRUN (mode 0644):"
				echo "  $TRIM_HOUR $TRIM_DOW * * * root $TRIM_BIN -v $TRIM_TARGET $TRIM_REDIRECT"
			elif [ -f "$CRON_D_LONGRUN" ] && priv cmp -s "$CRON_NEW" "$CRON_D_LONGRUN"; then
				rm -f "$CRON_NEW"
				log_ok "Weekly fstrim job already current in $CRON_D_LONGRUN — left untouched (no write)."
			elif write_root_file_if_changed "$CRON_D_LONGRUN" 0644 "$CRON_NEW" "weekly fstrim"; then
				rm -f "$CRON_NEW"
				start_service cron
				log_ok "cron enabled/started via init (check: rc-service cron status)."
			else
				rm -f "$CRON_NEW"
				log_warn "Could not install $CRON_D_LONGRUN — add it by hand:"
				echo "  $TRIM_HOUR $TRIM_DOW * * * root $TRIM_BIN -v $TRIM_TARGET $TRIM_REDIRECT"
			fi
		else
			log_info "Not scheduling fstrim (answered no)."
		fi
	fi
fi

# ------------------------------------------------------------------
# 2/6  Disk health — smartmontools + a one-time SMART summary
# ------------------------------------------------------------------
log_head "2/7  Disk health (SMART)"

if is_installed smartmontools && command_exists smartctl; then
	log_ok "smartmontools already installed and smartctl is on PATH."
elif escalation_ok; then
	log_info "smartmontools not installed — installing it (reads disk health, writes nothing to the disk)."
	apt_update
	if install_pkgs "Disk health tooling" smartmontools; then
		log_ok "smartmontools installed."
	else
		log_warn "smartmontools could not be installed — no disk-health data today."
	fi
else
	note_no_escalation "install smartmontools"
	log_info "  Run: apt-get install smartmontools   (then re-run this step for the SMART summary)"
fi

if ! command_exists smartctl; then
	log_warn "smartctl still not on PATH — skipping the SMART summary."
	log_warn "  That is a missing tool, not a clean bill of health. Nothing was read."
else
	# Whole block devices only. smartctl refuses partitions ("cannot
	# satisfy UNIQUE part of ...") and loop/ram/dm devices have no SMART
	# at all, so any name that is not an unambiguous whole-disk name is
	# skipped rather than guessed at.
	SMART_DEVS=()
	for sd_path in /sys/class/block/*; do
		[ -d "$sd_path" ] || continue
		sd_name="$(basename "$sd_path")"
		case "$sd_name" in
		nvme[0-9]n[0-9]) ;;
		nvme[0-9]n[0-9]p[0-9]*) continue ;;
		sd[a-z]*) ;;
		sd[a-z]*[0-9]) continue ;;
		mmcblk[0-9]) ;;
		mmcblk[0-9]p[0-9]*) continue ;;
		*) continue ;;
		esac
		[ -e "$sd_path/device" ] || continue
		SMART_DEVS+=("/dev/$sd_name")
	done

	if [ "${#SMART_DEVS[@]}" -eq 0 ]; then
		log_warn "No whole-disk block device under /sys/class/block — cannot read SMART."
	else
		log_info "Whole-disk device(s): ${SMART_DEVS[*]}"
		if escalation_ok; then
			for sd_dev in "${SMART_DEVS[@]}"; do
				echo -e "  ${CYAN}--- smartctl -H -A $sd_dev ---${NC}"
				SD_OUT="$(priv smartctl -H -A "$sd_dev" 2>&1)"
				SD_RC=$?
				printf '%s\n' "$SD_OUT" | sed 's/^/      /'
				[ "$SD_RC" -eq 0 ] || log_warn "smartctl exited $SD_RC for $sd_dev (unsupported device, or permission denied?)"
				# Verdict taken only from the tool's own words.
				if printf '%s' "$SD_OUT" | grep -qiE 'self-assessment test result: *FAILED|SMART Health Status: *FAILED'; then
					log_err "$sd_dev: SMART reports FAILED — back up now and replace this disk."
				elif printf '%s' "$SD_OUT" | grep -qiE 'PASSED|SMART Health Status: *OK'; then
					log_ok "$sd_dev: SMART health OK."
				else
					log_warn "$sd_dev: no PASSED/FAILED verdict in the output — read it above."
				fi
			done
		else
			note_no_escalation "SMART summary"
			for sd_dev in "${SMART_DEVS[@]}"; do
				log_info "  As root: smartctl -H -A $sd_dev"
			done
		fi
	fi
fi

# ------------------------------------------------------------------
# 3/6  apt archive — declare autoclean for the job apt already runs
# ------------------------------------------------------------------
log_head "3/7  apt archive cache"

APT_CACHE_DIR="/var/cache/apt"
APT_DEB_N="$(find "$APT_CACHE_DIR/archives" -maxdepth 1 -type f -name '*.deb' 2>/dev/null | wc -l)"
APT_NOW="$(bytes_of "$APT_CACHE_DIR")"
log_info "${APT_CACHE_DIR} holds $(human_bytes "$APT_NOW") across ${APT_DEB_N} .deb file(s)."

# THE DISTRIBUTION-NATIVE MECHANISM. /etc/cron.daily/apt-compat already
# runs /usr/lib/apt/apt.systemd.daily every day on a non-systemd box, and
# that script performs "apt-get autoclean" whenever
# APT::Periodic::AutocleanInterval is non-zero. So the fix is two
# declarative apt-config keys — NOT a new cron job, which would put a
# second scheduler in competition with an existing one.
APT_TMP="$(mktemp)"
{
	echo "# Written by xfcemlg scripts/53-longrun.sh — safe to delete."
	echo "#"
	echo "# apt.systemd.daily (run daily by /etc/cron.daily/apt-compat) reads"
	echo "# these keys and runs 'apt-get autoclean' every $APT_CLEAN_DAYS days."
	echo "# autoclean only drops .deb files that no repository index references"
	echo "# any more, so it cannot strand a package that is still installable."
	echo "APT::Periodic::Autoclean \"1\";"
	echo "APT::Periodic::AutocleanInterval \"$APT_CLEAN_DAYS\";"
} >"$APT_TMP"
if escalation_ok; then
	write_root_file_if_changed "$APT_CONF" 0644 "$APT_TMP" "apt autoclean policy" || true
else
	note_no_escalation "write $APT_CONF"
	log_info "  As root: install -m 0644 <generated file> $APT_CONF"
fi
rm -f "$APT_TMP"

APT_CONF_SEEN="$(priv cat "$APT_CONF" 2>/dev/null || true)"
case "$APT_CONF_SEEN" in
*"AutocleanInterval \"$APT_CLEAN_DAYS\""*)
	log_ok "apt.systemd.daily will autoclean the archive every $APT_CLEAN_DAYS days from now on."
	log_info "  No new cron entry: /etc/cron.daily/apt-compat already runs that job daily."
	;;
*)
	log_warn "Could not confirm $APT_CONF declares AutocleanInterval=$APT_CLEAN_DAYS — check it by hand."
	;;
esac

# One-time autoclean NOW. This deletes .deb files, so it is ask_no_full
# with default N: --full and install.sh can never reach it.
if [ "$APT_NOW" -gt 0 ]; then
	if ask_no_full "Run 'apt-get autoclean' now and delete $(human_bytes "$APT_NOW") of unreferenced .deb files?" "N"; then
		if escalation_ok; then
			if priv apt-get autoclean; then
				APT_AFTER="$(bytes_of "$APT_CACHE_DIR")"
				APT_FREED=$((APT_NOW - APT_AFTER))
				log_ok "apt autoclean done: $(human_bytes "$APT_NOW") -> $(human_bytes "$APT_AFTER") (freed $(human_bytes "$APT_FREED"))."
			else
				log_warn "apt-get autoclean failed — the archive was left as it was."
			fi
		else
			note_no_escalation "one-time apt-get autoclean"
			log_info "  As root: apt-get autoclean"
		fi
	else
		log_info "Skipped the one-time apt autoclean (default is no). The $APT_CLEAN_DAYS-day policy above still applies."
	fi
else
	log_ok "apt archive is empty — nothing to autoclean."
fi

# ------------------------------------------------------------------
# 4/6  Home litter — Trash + ~/.cache, bounded and age-limited
# ------------------------------------------------------------------
log_head "4/7  Home litter (Trash + ~/.cache), age limit ${LITTER_DAYS}d"

# Top level only (find -mindepth 1 -maxdepth 1): this is a *bounded*
# trim. Recursing into ~/.cache would be a different and far riskier
# operation — one top-level entry can be a several-hundred-MB tree the
# user still wants, and some of them (a running app's cache) are in use.
TRASH_FILES="$TARGET_HOME/.local/share/Trash/files"
TRASH_INFO="$TARGET_HOME/.local/share/Trash/info"
USER_CACHE="$TARGET_HOME/.cache"

LITTER_BEFORE="$(bytes_of "$TRASH_FILES" "$USER_CACHE")"
log_info "Before: Trash/files + ~/.cache = $(human_bytes "$LITTER_BEFORE")"

TRASH_CANDS=()
if [ -d "$TRASH_FILES" ]; then
	while IFS= read -r t; do
		[ -n "$t" ] && TRASH_CANDS+=("$t")
	done < <(find "$TRASH_FILES" -xdev -mindepth 1 -maxdepth 1 -mtime "+$LITTER_DAYS" 2>/dev/null)
else
	log_info "No $TRASH_FILES — nothing to trim in the Trash."
fi

CACHE_CANDS=()
if [ -d "$USER_CACHE" ]; then
	while IFS= read -r c; do
		[ -n "$c" ] && CACHE_CANDS+=("$c")
	done < <(find "$USER_CACHE" -xdev -mindepth 1 -maxdepth 1 -mtime "+$LITTER_DAYS" 2>/dev/null)
else
	log_info "No $USER_CACHE — nothing to trim in the cache."
fi

LITTER_N=$((${#TRASH_CANDS[@]} + ${#CACHE_CANDS[@]}))
if [ "$LITTER_N" -eq 0 ]; then
	log_ok "Nothing in Trash/files or ~/.cache is older than $LITTER_DAYS days — no trim needed."
	log_info "  (An empty result here is a real measurement, not a skipped check.)"
else
	LITTER_HIT="$(bytes_of "${TRASH_CANDS[@]}" "${CACHE_CANDS[@]}")"
	log_warn "$LITTER_N entr(y/ies) older than $LITTER_DAYS days, $(human_bytes "$LITTER_HIT") total:"
	for entry in "${TRASH_CANDS[@]}" "${CACHE_CANDS[@]}"; do
		[ -n "$entry" ] && printf '     %s (%s)\n' "$entry" "$(human_bytes "$(bytes_of "$entry")")"
	done
	log_info "Trash entries are gone for good; .cache entries are rebuilt by their app on next use."
	if ask_no_full "Delete these $LITTER_N entries?" "N"; then
		removed=0
		for entry in "${TRASH_CANDS[@]}" "${CACHE_CANDS[@]}"; do
			[ -n "$entry" ] || continue
			if rm -rf -- "$entry" 2>/dev/null; then
				removed=$((removed + 1))
				# Keep the Trash self-consistent: deleting a file but
				# leaving its .trashinfo behind is precisely the litter
				# this section exists to remove, so the metadata goes
				# with it. Same act, one gate.
				[ -d "$TRASH_INFO" ] &&
					rm -f -- "${TRASH_INFO}/$(basename -- "$entry").trashinfo" 2>/dev/null
			else
				log_warn "Could not remove $entry (permissions?) — left in place."
			fi
		done
		LITTER_AFTER="$(bytes_of "$TRASH_FILES" "$USER_CACHE")"
		LITTER_FREED=$((LITTER_BEFORE - LITTER_AFTER))
		# Concurrent growth (a running app writing its cache) can make this
		# negative; report the reclaim honestly rather than a negative.
		[ "$LITTER_FREED" -lt 0 ] && LITTER_FREED=0
		log_ok "Removed $removed entries: $(human_bytes "$LITTER_BEFORE") -> $(human_bytes "$LITTER_AFTER") (freed $(human_bytes "$LITTER_FREED"))."
	else
		log_info "Left all $LITTER_N entries alone (default is no). Re-run this step whenever you like."
	fi
fi

# ------------------------------------------------------------------
# 5/6  tmpfiles.d — declarative, and honest about who will read it
# ------------------------------------------------------------------
log_head "5/7  tmpfiles.d drop-in"

# /etc/tmpfiles.d is the administrator's override directory and does not
# even exist on a minimal install (only /usr/lib/tmpfiles.d does), so it
# is created rather than assumed.
TMPF_TMP="$(mktemp)"
{
	echo "# Written by xfcemlg scripts/53-longrun.sh — safe to delete."
	echo "#"
	echo "# Scope is deliberately narrow: the only two paths this toolkit could"
	echo "# ever own in SYSTEM space. Nothing here says anything about /tmp,"
	echo "# /var/tmp, or any path another package has an opinion about."
	echo "#"
	echo "# 'e' = clean an EXISTING directory's contents by age (tmpfiles.d(5))."
	echo "#   Unlike 'd'/'D' it never creates the directory, so a path the"
	echo "#   toolkit never used stays absent instead of gaining an empty shell."
	echo "#   The age column is the cleanup age: older entries go. Age is tested"
	echo "#   against mtime AND atime, so a cache still in use is never a"
	echo "#   candidate, and the aging pass takes a BSD lock per entry."
	echo "e /var/cache/xfcemlg 0755 root root ${LITTER_DAYS}d -"
	echo "e /run/xfcemlg 0755 root root 7d -"
} >"$TMPF_TMP"
if escalation_ok; then
	priv mkdir -p /etc/tmpfiles.d 2>/dev/null || true
	write_root_file_if_changed "$TMPF_SYS" 0644 "$TMPF_TMP" "system tmpfiles drop-in" || true
else
	note_no_escalation "write $TMPF_SYS"
	log_info "  As root: install -m 0644 <generated file> $TMPF_SYS"
fi
rm -f "$TMPF_TMP"

# The same declaration for the litter that actually exists on a real
# desktop — all of it in the user's home, none of it in system space.
TMPF_UTMP="$(mktemp)"
{
	echo "# Written by xfcemlg scripts/53-longrun.sh — safe to delete."
	echo "# User scope (~/.config/user-tmpfiles.d), read by 'systemd-tmpfiles --user'."
	echo "# The toolkit's own litter and nothing else: the download cache left by"
	echo "# the theme-fetch steps, and the run log."
	echo "#"
	echo "# Deliberately NOT declared here:"
	echo "#   * ~/.cache as a whole, and ~/.local/share/Trash — other packages own"
	echo "#     those. A blanket rule over them is exactly the 'trampling other"
	echo "#     packages' outcome this step is meant to avoid."
	echo "#   * ~/.cache/sessions/xfwm4-*.state — a state file is prunable by age"
	echo "#     alone only when the window it remembers is gone too, and no"
	echo "#     tmpfiles rule can express that. Section 6 does it with an X"
	echo "#     liveness check. Do not 'tidy' it by adding an age rule here."
	echo "e $TARGET_HOME/.cache/xfcemlg 0755 $ACTUAL_USER $ACTUAL_USER ${LITTER_DAYS}d -"
	echo "e $TARGET_HOME/.local/state/xfcemlg 0755 $ACTUAL_USER $ACTUAL_USER 90d -"
} >"$TMPF_UTMP"
write_user_file_if_changed "$TMPF_USER" "$TMPF_UTMP" "user tmpfiles drop-in" || true
rm -f "$TMPF_UTMP"

# The honest part: a tmpfiles.d drop-in is only ever a *declaration*. If
# nothing on this box executes systemd-tmpfiles, both files above are
# inert text, and claiming otherwise would be a lie.
if command_exists systemd-tmpfiles; then
	log_ok "systemd-tmpfiles is installed — the drop-in(s) above are live config."
	log_info "  Apply now: systemd-tmpfiles --create   (age-based pass: --clean)"
else
	log_warn "systemd-tmpfiles is NOT installed here, so those drop-in(s) are INERT."
	log_warn "  Expected on a no-systemd install: systemd itself is absent, and"
	log_warn "  elogind (the logind replacement) does not ship tmpfiles. Nothing"
	log_warn "  reads /etc/tmpfiles.d, so no cleanup ran and none is being claimed."
	log_warn "  The files are kept because they are correct and cost 4 KiB each:"
	log_warn "  install systemd (or systemd-tmpfiles) and they take effect."
	log_warn "  Until then the age-limited trims in section 4 are what actually"
	log_warn "  reclaim space — re-run this step whenever you want them."
fi

# ------------------------------------------------------------------
# 6/7  fwupd metadata refresh (cron.daily)
# ------------------------------------------------------------------
log_head "6/7  fwupd metadata refresh"

# fwupd ships ONLY systemd units — fwupd.service and fwupd-refresh.timer.
# Neither can fire on OpenRC/sysvinit, and `systemctl` does not even exist
# here, so the timer is inert. With nothing else refreshing,
# /var/lib/fwupd/metadata/ stays empty and `fwupdmgr get-updates` reports
# "no updates" on a machine that has never once asked. That is worse than no
# output, because it looks like an answer.
#
# The job is a stock /etc/cron.daily script, which is the distribution-native
# scheduler here — it needs no new daemon and no user crontab, and run-parts
# already runs apt-compat, dpkg, logrotate and man-db through the same door.
# Its own internals (weekly download throttle, "unknown" instead of a false
# zero) are documented in the script itself.
FWUPD_JOB_SRC="$SCRIPT_DIR/../configs/cron.daily/xfcemlg-fwupd-refresh"
FWUPD_JOB="/etc/cron.daily/xfcemlg-fwupd-refresh"

if ! command_exists fwupdmgr; then
	log_info "fwupdmgr not installed — nothing to refresh."
elif ! is_installed fwupd; then
	log_info "fwupd package not installed — nothing to refresh."
elif [ ! -f "$FWUPD_JOB_SRC" ]; then
	log_warn "Job source missing at $FWUPD_JOB_SRC — skipping."
else
	# run-parts only executes files whose names are [A-Za-z0-9_-]+ with no
	# dots, so the name is not free-form; assert it rather than assume it.
	case "$(basename "$FWUPD_JOB")" in
	*[!A-Za-z0-9_-]* | *.*)
		log_warn "'$(basename "$FWUPD_JOB")' is not a valid run-parts filename; skipping."
		;;
	*)
		if escalation_ok; then
			# 0755 and not 0644: run-parts skips non-executable entries.
			if write_root_file_if_changed "$FWUPD_JOB" 0755 "$FWUPD_JOB_SRC" \
				"fwupd refresh job" || true; then
				log_ok "Runs daily via $FWUPD_JOB (download throttled to weekly)."
				log_info "  Metadata now:  fwupdmgr get-updates"
				log_info "  Log:           /var/log/xfcemlg-fwupd.log"
				log_info "  It refreshes metadata only and never flashes firmware;"
				log_info "  installing an update stays a deliberate 'fwupdmgr update'."
			fi
		else
			note_no_escalation "write $FWUPD_JOB"
			log_info "  As root: install -m 0755 $FWUPD_JOB_SRC $FWUPD_JOB"
		fi
		;;
	esac
fi

# ------------------------------------------------------------------
# 7/7  Stale xfwm4 window-state files — old AND dead
# ------------------------------------------------------------------
log_head "7/7  Stale xfwm4 window-state files"

# Where they actually live: xfwm4 writes one file per remembered window
# under $XDG_CACHE_HOME/sessions. The pre-4.14 config location is kept in
# the list so older layouts are covered too.
STATE_DIRS=(
	"${XDG_CACHE_HOME:-$TARGET_HOME/.cache}/sessions"
	"$TARGET_HOME/.config/xfce4/xfwm4"
)

STATE_TOTAL=0
STATE_OLD=()
for sdir in "${STATE_DIRS[@]}"; do
	[ -d "$sdir" ] || continue
	while IFS= read -r sfile; do
		[ -n "$sfile" ] || continue
		STATE_TOTAL=$((STATE_TOTAL + 1))
		[ "$sfile" -ot "$AGE_MARK" ] && STATE_OLD+=("$sfile")
	done < <(find "$sdir" -xdev -maxdepth 1 -type f -name 'xfwm4-*.state' 2>/dev/null)
done

if [ "$STATE_TOTAL" -eq 0 ]; then
	log_ok "No xfwm4-*.state files in ${STATE_DIRS[*]} — nothing to prune."
elif [ "${#STATE_OLD[@]}" -eq 0 ]; then
	log_ok "$STATE_TOTAL xfwm4-*.state file(s) present, none older than $LITTER_DAYS days — nothing pruned."
	log_info "  (All of them are recent: they are live window-position memory, not litter.)"
else
	log_warn "${#STATE_OLD[@]} of $STATE_TOTAL xfwm4-*.state file(s) are older than $LITTER_DAYS days."
fi

if [ "${#STATE_OLD[@]}" -gt 0 ]; then
	# LIVENESS GATE. Pruning a state file whose window is still open throws
	# away that window's remembered geometry, so the age test is never
	# sufficient on its own.
	#
	# This gate is not belt-and-braces, it is a correctness requirement.
	# `xdotool getwindowname` exits non-zero with "Can't open display" when
	# DISPLAY is unset — byte-for-byte the same signal it gives for a
	# genuinely dead window id. Run from cron (no DISPLAY), a naive probe
	# would declare every window dead and delete live state. So prove the X
	# connection works first, and if it cannot be proven, prune nothing.
	LIVE_PROBE=""
	if xdpyinfo >/dev/null 2>&1 || xdotool getdisplaygeometry >/dev/null 2>&1; then
		LIVE_PROBE="xdotool"
	elif xprop -root >/dev/null 2>&1; then
		LIVE_PROBE="xprop"
	fi

	if [ -z "$LIVE_PROBE" ]; then
		log_warn "Cannot reach the X server (DISPLAY=${DISPLAY:-unset}, or no xdotool/xprop)."
		log_warn "  Window liveness is undecidable, so NOTHING was pruned: pruning on"
		log_warn "  age alone would lose the remembered position of open windows."
		log_warn "  Re-run this step from inside the graphical session to prune."
	else
		log_info "X connection confirmed via $LIVE_PROBE (DISPLAY=${DISPLAY:-unset})."
		PRUNE=()
		KEPT_LIVE=0
		for sfile in "${STATE_OLD[@]}"; do
			# A state file can hold several [CLIENT] blocks. Conservative
			# rule: if ANY remembered window is still alive, keep the file.
			is_dead=1
			ids="$(grep -oE '^\[CLIENT\][[:space:]]+0x[0-9a-fA-F]+' "$sfile" 2>/dev/null |
				awk '{print $2}' | sort -u)"
			if [ -z "$ids" ]; then
				# No parsable client id at all: the file describes no
				# window, so there is no position it can be holding. (If
				# xfwm4 is mid-write the read is racy either way, but a
				# 30-day-old file is not one it is writing.)
				is_dead=1
			else
				while IFS= read -r wid; do
					[ -n "$wid" ] || continue
					if [ "$LIVE_PROBE" = "xdotool" ]; then
						xdotool getwindowname "$wid" >/dev/null 2>&1 && is_dead=0
					else
						xprop -id "$wid" >/dev/null 2>&1 && is_dead=0
					fi
					[ "$is_dead" -eq 0 ] && break
				done <<<"$ids"
			fi
			if [ "$is_dead" -eq 1 ]; then
				PRUNE+=("$sfile")
			else
				KEPT_LIVE=$((KEPT_LIVE + 1))
			fi
		done

		if [ "${#PRUNE[@]}" -eq 0 ]; then
			log_ok "All $KEPT_LIVE aged state file(s) still describe a live window — kept, their geometry is in use."
		else
			log_warn "${#PRUNE[@]} aged state file(s) describe windows that no longer exist ($KEPT_LIVE kept because a window is still live):"
			for sfile in "${PRUNE[@]}"; do
				printf '     %s (mtime %s)\n' "$sfile" "$(stat -c %y "$sfile" 2>/dev/null | cut -d' ' -f1)"
			done
			if ask_no_full "Delete these ${#PRUNE[@]} state file(s)? (A still-open window would lose its remembered position.)" "N"; then
				pruned=0
				pruned_bytes=0
				for sfile in "${PRUNE[@]}"; do
					# Measure BEFORE the unlink — afterwards the file is
					# gone and bytes_of would report 0.
					sz="$(bytes_of "$sfile")"
					if rm -f -- "$sfile" 2>/dev/null; then
						pruned=$((pruned + 1))
						pruned_bytes=$((pruned_bytes + sz))
					else
						log_warn "Could not remove $sfile — left in place."
					fi
				done
				log_ok "Pruned $pruned stale xfwm4 state file(s) (freed $(human_bytes "$pruned_bytes"))."
			else
				log_info "Left all ${#PRUNE[@]} file(s) alone (default is no)."
			fi
		fi
	fi
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
log_head "Long-run maintenance done"
log_ok "Nothing destructive ran: apt autoclean, the Trash/cache trim and the"
log_ok "xfwm4 prune are all gated on ask_no_full, which defaults to no and"
log_ok "ignores XMLG_FULL."
echo -e "  Re-run any time:      ${CYAN}bash scripts/53-longrun.sh${NC}"
echo -e "  fstrim schedule:      ${CYAN}cat $CRON_D_LONGRUN${NC}"
echo -e "  apt autoclean policy: ${CYAN}apt-config dump | grep -i autoclean${NC}"
echo -e "  tmpfiles drop-in:     ${CYAN}cat $TMPF_SYS ${TMPF_USER}${NC}"
echo -e "  fwupd refresh job:    ${CYAN}cat $FWUPD_JOB${NC}  (log: /var/log/xfcemlg-fwupd.log)"
exit 0
