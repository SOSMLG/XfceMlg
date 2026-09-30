#!/usr/bin/env bash
# =======================================================
# common.sh — shared helpers, sourced by every toolkit script
# -------------------------------------------------------
# Every script in this toolkit sources this file for the shared helpers
# (colors, logging, is_installed, ask, install_pkgs, service management,
# download verification). Each script remains independently runnable —
# `bash scripts/<name>.sh` works fine because lib/ ships with the repo.
#
# This file is the toolkit's own contract: every script sources it, and it
# owns the XMLG_* namespace, the priv() escalator and the ask/log helpers.
# It is self-contained — it depends on no other toolkit.
#
# Environment variables honored (all optional):
#   XMLG_ASSUME_YES=1        ask() answers with its default instead of prompting
#   XMLG_SKIP_APT_UPDATE=1   apt_update() is a no-op (run.sh updates once)
#   XMLG_PRIV=doas|sudo      force the privilege escalator (default: doas, sudo fallback)
# =======================================================

# sbin lives outside a normal user's PATH, but this toolkit drives sysadmin
# tools (usermod, rc-service, ufw, rfkill...). Export it once here so
# command -v checks and direct calls resolve before any escalation.
case ":$PATH:" in
*:/usr/sbin:*) ;;
*) export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH" ;;
esac

# Guard against being sourced twice in the same shell.
[ -n "${_XMLG_COMMON_SH_LOADED:-}" ] && return 0
_XMLG_COMMON_SH_LOADED=1

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m"

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

log_head() {
	echo -e "${CYAN}=========================================================${NC}"
	echo -e "${CYAN} $1${NC}"
	echo -e "${CYAN}=========================================================${NC}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# have_priv — true if any privilege escalator is available
have_priv() { command_exists doas || command_exists sudo; }

# priv() — run a command as root. Prefers doas (BSD-minimal, the toolkit
# default once scripts/12-user-groups.sh sets up opendoas), falls back to
# sudo so scripts keep working on machines that only have sudo.
# XMLG_PRIV=doas|sudo forces one. Flags pass through (-n and -u exist
# in both). Usage: priv apt-get install -y foo / priv -n reboot
priv() {
	local tool="${XMLG_PRIV:-}"
	if [ -z "$tool" ]; then
		if command_exists doas; then tool=doas; else tool=sudo; fi
	fi
	"$tool" "$@"
}

is_installed() {
	dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

require_not_root() {
	if [ "$(id -u)" -eq 0 ]; then
		log_err "Do not run this as root — run it as your normal user; it will escalate itself when needed (doas, sudo fallback)."
		exit 1
	fi
	if ! have_priv; then
		log_err "Neither doas nor sudo found — install one (scripts/12-user-groups.sh sets up opendoas)."
		exit 1
	fi
	# Proven fast path: a warm doas persist / sudo timestamp means
	# escalation works right now — no need for the heuristic below
	# (which cannot read root-only /etc/doas.conf and would cry wolf).
	if command_exists doas && doas -n true >/dev/null 2>&1; then
		return 0
	fi
	if command_exists sudo && sudo -n true >/dev/null 2>&1; then
		return 0
	fi
	# Minimal installs often ship an escalator the user can't actually use
	# (sudo installed but user in no empowered group, doas without a rule):
	# escalation then dies mid-run with a bare password rejection. Warn once,
	# early, with the exact fix — never fatal, the user may know better.
	# NOTE: /etc/doas.conf is root-only 600, so this grep only sees it when
	# readable; a cold (yet valid) persist timestamp still lands here and
	# will simply ask once — that is normal, not broken.
	# $ACTUAL_USER rather than $USER: it is already resolved (see its
	# definition below) and is the semantically correct "real user" even when
	# escalation happened upstream, so it cannot be unset.
	if ! id -nG 2>/dev/null | grep -qwE "sudo|wheel|doas" &&
		! grep -qw "$ACTUAL_USER" /etc/doas.conf 2>/dev/null; then
		log_warn "Your user is in no privilege group (sudo/wheel) and /etc/doas.conf names no rule for $ACTUAL_USER."
		log_warn "Escalation is likely to fail. Fix with ONE of these (as root), then relogin:"
		log_warn "  usermod -aG sudo $ACTUAL_USER   # Debian stock path"
		log_warn "  printf 'permit persist $ACTUAL_USER as root\n' > /etc/doas.conf   # BSD-minimal path"
	fi
}

# Real (non-root) user, even if this got invoked via escalation upstream.
# doas exports DOAS_USER the way sudo exports SUDO_USER.
#
# The ${USER:-} is load-bearing, not defensive decoration. Nearly every
# script here runs under `set -u`, and under `set -u` a bare $USER with no
# default is a fatal "unbound variable" — which killed the script at *source*
# time, before the `id -un` fallback on the next line could ever run. That is
# not hypothetical: any caller with a scrubbed environment (cron, `env -i`, a
# CI runner, a systemd-style ExecStart) has no USER, so verifySetup.sh died
# with one line of output and a false "everything is fine" for a health check
# that must never be able to report that.
ACTUAL_USER="${SUDO_USER:-${DOAS_USER:-${USER:-}}}"
[ -z "$ACTUAL_USER" ] && ACTUAL_USER="$(id -un)"

run_as_user() {
	if [ "$(id -un)" = "$ACTUAL_USER" ]; then
		"$@"
	else
		priv -u "$ACTUAL_USER" "$@"
	fi
}

# detect_xfce_origin — where did the XFCE desktop come from? The toolkit
# ships its own lean path (10-xfce-core.sh, --no-install-recommends); the
# distro-installer path lands task-xfce-desktop, a recommends-heavy meta
# that drags SLiM + Mousepad + Parole + QuodLibet + Xfburn in. Echoes one
# of: "task" | "lean" | "none".
detect_xfce_origin() {
	if is_installed task-xfce-desktop; then
		echo "task"
	elif is_installed xfce4-panel; then
		echo "lean"
	else
		echo "none"
	fi
}

# normalize_display_manager — make sure /etc/X11/default-display-manager
# points at lightdm (idempotent, backs up first). Several DMs fighting over
# the VT / /tmp/.X11-unix is a classic "boots to a black screen, no login"
# cause, and lightdm is this toolkit's one DM.
normalize_display_manager() {
	local dm_file="/etc/X11/default-display-manager"
	if [ -f "$dm_file" ] && grep -qx '/usr/sbin/lightdm' "$dm_file"; then
		log_ok "LightDM already the default display manager."
		return 0
	fi
	if [ -f "$dm_file" ]; then
		priv cp "$dm_file" "${dm_file}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
	fi
	if printf '/usr/sbin/lightdm\n' | priv tee "$dm_file" >/dev/null; then
		log_ok "Default display manager set to LightDM."
		return 0
	fi
	log_warn "Could not write $dm_file."
	return 1
}

# ini_dedup_key file section key value — ensure `key=value` inside `[section]`
# of an INI file WITHOUT appending duplicate section headers. lightdm.conf(5)
# reads only the FIRST [Seat:*] block, so a naive tee -a of a fresh section
# means later keys silently never apply — this replaces in place when the
# header already exists, and only appends header+key when neither exists.
# Fixed-string matching throughout (section names like `Seat:*` carry regex
# metachars that grep -E/sed would misread). The update/insert branches are
# SECTION-AWARE: only lines inside the named [section] block are matched, so
# a same-named key in a different section is never touched (lightdm.conf
# style files can carry identical keys under [Seat:*] and [Seat:x]).
# Content is computed by a root awk and written back through root tee, so no
# ownership/nesting hazards.
ini_dedup_key() {
	local file="$1" section="$2" key="$3" value="$4"
	if [ ! -f "$file" ] || ! grep -qF "[${section}]" "$file"; then
		if printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" | priv tee -a "$file" >/dev/null; then
			log_ok "Wrote ${key}=${value} under [${section}] in $file"
		else
			log_warn "Could not write $file."
		fi
		return 0
	fi
	local hdr="[${section}]" seek="${key}="
	# Was the key already present inside [section]? (drives the log label)
	local had_key
	had_key="$(priv awk -v h="$hdr" -v k="$seek" '
        $0 == h { insec = 1; next }
        insec && /^\[/ { insec = 0 }
        insec && index($0, k) == 1 { found = 1; exit }
        END { if (found) print 1 }
    ' "$file" 2>/dev/null)"
	local content
	content="$({ priv awk -v h="$hdr" -v k="$seek" -v kv="${key}=${value}" '
        $0 == h && !seen { seen = 1; insec = 1; print; next }
        seen && insec && /^\[/ {
            if (!replaced) { print kv; replaced = 1 }
            insec = 0; print; next
        }
        insec && index($0, k) == 1 {
            if (!replaced) { print kv; replaced = 1 }
            next
        }
        { print }
        END { if (seen && insec && !replaced) print kv }
    ' "$file"; } 2>/dev/null)" || return 1
	if [ -z "$content" ]; then
		log_warn "ini_dedup_key: nothing read from $file."
		return 1
	fi
	printf '%s\n' "$content" | priv tee "$file" >/dev/null
	if [ "$had_key" = "1" ]; then
		log_ok "updated: ${key}=${value} in $file ([${section}])"
	else
		log_ok "inserted (existing [${section}] kept, no duplicate header): ${key}=${value} in $file"
	fi
}

# ensure_doas_persist [user] — make sure /etc/doas.conf grants
#   permit persist <user> as root
# (root-owned, mode 600). doas.conf(5) is "last match wins", so a stale
# persist-less `permit <user> ...` line sitting AFTER ours silently
# re-enables a password prompt on every single invocation — the classic
# "doas keeps asking" complaint. This therefore NORMALIZES whenever the
# file is readable through privilege: every permit line naming the user
# is replaced by the one canonical persist line (comments, deny lines
# and other users untouched; a deliberate `nopass` rule is respected and
# left alone). Idempotent: pure no-op when already canonical.
# A rewrite rejected by `doas -C` is rolled back from backup.
# Honors DOAS_CONF override (tests). Needs one working escalator for the
# read/write; on failure prints the manual fix instead of dying mid-run.
ensure_doas_persist() {
	local user="${1:-$ACTUAL_USER}"
	local conf="${DOAS_CONF:-/etc/doas.conf}"
	local want="permit persist $user as root"
	if [ -z "$user" ] || [ "$user" = "root" ]; then
		log_err "ensure_doas_persist: refusing bad user '$user'."
		return 1
	fi
	fix_mode() {
		if [ "$(priv stat -c%a "$conf" 2>/dev/null || echo '')" != "600" ]; then
			priv chmod 600 "$conf" 2>/dev/null ||
				log_warn "Could not chmod 600 $conf."
		fi
	}
	check_syntax() {
		if command_exists doas && ! priv doas -C "$conf" >/dev/null 2>&1; then
			log_warn "doas -C rejects $conf — check its syntax."
			return 1
		fi
		return 0
	}
	# doas.conf is root-only 600 — read it through privilege. Empty means
	# unreadable (cold auth / no rule yet) or missing: fall back to append
	# (last match wins, so a correct trailing line still overrides earlier
	# stale ones; re-running after one successful auth normalizes fully).
	local cur=""
	cur="$(priv cat "$conf" 2>/dev/null || true)"
	if [ -z "$cur" ]; then
		log_info "Ensuring doas persist rule: '$want' in $conf ..."
		if printf '%s\n' "$want" | priv tee -a "$conf" >/dev/null &&
			priv chmod 600 "$conf" 2>/dev/null; then
			check_syntax || true
			log_ok "doas persist rule appended for '$user' (root-owned, mode 600)."
			return 0
		fi
		log_err "Could not write $conf (no working escalator)."
		log_warn "As root, run: printf '$want\n' > $conf && chmod 600 $conf"
		return 1
	fi
	# Effective rule = LAST permit line naming the user (comments stripped).
	local last_line last_kind last_scoped
	last_line="$(printf '%s\n' "$cur" | sed 's/#.*//' |
		grep -E "^[[:space:]]*permit[[:space:]]+.*\b$user\b" | tail -1 || true)"
	last_kind="$(printf '%s\n' "$last_line" | grep -Eo 'persist|nopass' | head -1 || true)"
	# A `... as root command foo` rule is command-scoped: it authorizes one
	# binary, not the toolkit. Treating it as "already effective" strands
	# the user with a rule that fails on the next command we run, so it must
	# fall through to the normalize branch below.
	last_scoped="$(printf '%s\n' "$last_line" | grep -Ew 'command' | head -1 || true)"
	if [ -n "$last_kind" ] && [ -z "$last_scoped" ]; then
		if [ "$last_kind" = "nopass" ]; then
			log_ok "doas nopass rule already effective for '$user' — leaving it (stronger than persist)."
		else
			log_ok "doas persist rule already present for '$user' ($conf)."
		fi
		fix_mode
		return 0
	fi
	if [ -n "$last_scoped" ]; then
		log_warn "doas rule for '$user' is command-scoped — widening to the toolkit's full rule."
	fi
	# Stale/shadowed: strip every permit line naming the user, append ours.
	local filtered candidate backup
	filtered="$(printf '%s\n' "$cur" | grep -vE "^[[:space:]]*permit[[:space:]]+.*\b$user\b" || true)"
	if [ -z "$filtered" ]; then
		candidate="$want"
	else
		candidate="$(printf '%s\n%s' "$filtered" "$want")"
	fi
	log_info "Normalizing $conf: replacing stale permit line(s) for '$user' with '$want' ..."
	backup="${conf}.bak.$(date +%Y%m%d_%H%M%S)"
	priv cp -a "$conf" "$backup" 2>/dev/null || true
	if printf '%s\n' "$candidate" | priv tee "$conf" >/dev/null &&
		priv chmod 600 "$conf" 2>/dev/null; then
		if check_syntax; then
			log_ok "doas persist rule normalized for '$user' (backup: $backup)."
			return 0
		fi
		log_err "New $conf rejected — rolling back."
		priv cp -a "$backup" "$conf" 2>/dev/null || true
		return 1
	fi
	log_err "Could not write $conf (escalation failed mid-run)."
	log_warn "As root, run: printf '$want\n' > $conf && chmod 600 $conf"
	return 1
}

# ask() — "Y/n" (default Y) or "y/N" (default N) prompt. With
# XMLG_ASSUME_YES set (run.sh --yes, or install.sh), the default is
# taken without prompting so the toolkit can run unattended.
# With XMLG_FULL set (run.sh --full, used by install.sh), every ask()
# answers Yes automatically so a full run never stops mid-way.
ask() {
	local prompt="$1" default="${2:-Y}" reply
	# Full mode: everything runs automatically — no stops.
	if [ -n "${XMLG_FULL:-}" ]; then
		return 0
	fi
	local hint="(Y/n)"
	[ "$default" = "N" ] && hint="(y/N)"
	if [ -n "${XMLG_ASSUME_YES:-}" ]; then
		reply="$default"
	else
		read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${NC}")" reply
		reply=${reply:-$default}
	fi
	[[ "$reply" =~ ^[Yy]$ ]]
}

# ask_no_full() — same as ask(), but XMLG_FULL does NOT force Yes.
# Use for destructive / hardware-specific / version-mismatch prompts that
# must never auto-fire on a full run: apt full-upgrade, backup restore,
# battery-cap, PhotoGIMP version mismatch, dead-symlink deletes.
ask_no_full() {
	local prompt="$1" default="${2:-Y}" reply
	local hint="(Y/n)"
	[ "$default" = "N" ] && hint="(y/N)"
	if [ -n "${XMLG_ASSUME_YES:-}" ]; then
		reply="$default"
	else
		read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${NC}")" reply
		reply=${reply:-$default}
	fi
	[[ "$reply" =~ ^[Yy]$ ]]
}

# migrate_legacy_path <old> <new> <label> [needs_root]
# One-shot namespace migration. Moves a pre-0.8.0 path onto its xfcemlg
# equivalent so the rename does not orphan live state (which is how the
# 62 MB of .bak.* litter accumulated in the first place).
#
# Rules, in order:
#   old missing            -> no-op (the common case on a fresh install)
#   new already present    -> never clobber; warn and leave both alone
#   otherwise              -> move
#
# Interactive runs are asked (ask_no_full, so --full cannot force it).
# Unattended runs move without asking: a rename preserves every file's
# content, the toolkit owns these paths and rewrites them anyway, so the
# only outcome of asking would be to strand the old copies forever — the
# exact litter this exists to prevent. The "new already present" guard
# above is what actually protects data.
#
# Idempotent: a second run sees new-present and does nothing.
migrate_legacy_path() {
	local old="$1" new="$2" label="$3" needs_root="${4:-N}"
	[ -e "$old" ] || return 0
	if [ -e "$new" ]; then
		log_warn "$label: both the old and new location exist — leaving both."
		log_warn "  old: $old"
		log_warn "  new: $new"
		return 0
	fi
	log_info "$label: $old -> $new"
	if [ -z "${XMLG_ASSUME_YES:-}${XMLG_FULL:-}" ] &&
		! ask_no_full "Move $label from the legacy location to the xfcemlg one?" "N"; then
		log_warn "$label: left in place at $old (harmless, re-runnable later)."
		return 0
	fi
	local parent
	parent="$(dirname "$new")"
	if [ "$needs_root" = "Y" ]; then
		priv mkdir -p "$parent" || {
			log_err "$label: cannot create $parent"
			return 1
		}
		priv mv "$old" "$new" || {
			log_err "$label: move failed"
			return 1
		}
	else
		mkdir -p "$parent" || {
			log_err "$label: cannot create $parent"
			return 1
		}
		mv "$old" "$new" || {
			log_err "$label: move failed"
			return 1
		}
	fi
	log_ok "$label: migrated."
}

# migrate_legacy_paths() — move every pre-0.8.0 `devuan-xfce-*` path this
# toolkit owns onto its `xfcemlg` equivalent. Called once by run.sh before
# any step, and safe to call again from any step.
migrate_legacy_paths() {
	local legacy="devuan-xfce-setup"
	local srcd="${APT_SOURCES_D:-/etc/apt/sources.list.d}"
	local anything=0 p
	# Every path below is under $HOME, and callers run under `set -u`, so an
	# unset HOME would abort here on the first expansion. There is no safe
	# guess to make: relocating a user's config into a directory we invented
	# would be worse than doing nothing. Say so and return.
	if [ -z "${HOME:-}" ]; then
		log_warn "HOME is not set — skipping the namespace migration (nothing was moved)."
		return 0
	fi
	for p in "$HOME/.config/$legacy" "$HOME/.local/state/$legacy" "$HOME/.cache/$legacy"; do
		[ -e "$p" ] && anything=1
	done
	[ -e "/usr/share/$legacy-assets" ] && anything=1
	# The apt component snippet ensure_repo_component() writes also carries
	# the old name; leaving it behind would give apt a duplicate source.
	for p in "$srcd"/xfce-setup-*.sources; do
		[ -e "$p" ] && anything=1
	done
	[ "$anything" -eq 1 ] || return 0

	log_head "Namespace migration (pre-0.8.0 devuan-xfce-setup -> xfcemlg)"
	migrate_legacy_path "$HOME/.config/$legacy" "$HOME/.config/xfcemlg" "user config"
	migrate_legacy_path "$HOME/.local/state/$legacy" "$HOME/.local/state/xfcemlg" "run state (keeps last-run.log)"
	migrate_legacy_path "$HOME/.cache/$legacy" "$HOME/.cache/xfcemlg" "download cache"
	migrate_legacy_path "/usr/share/$legacy-assets" "/usr/share/xfcemlg-assets" "installed assets" "Y"
	for p in "$srcd"/xfce-setup-*.sources; do
		[ -e "$p" ] || continue
		migrate_legacy_path "$p" "${p/xfce-setup-/xfcemlg-}" "apt component snippet" "Y"
	done
	echo
}

install_pkgs() {
	local label="$1"
	shift
	local to_install=()
	local pkg
	for pkg in "$@"; do
		is_installed "$pkg" || to_install+=("$pkg")
	done
	if [ "${#to_install[@]}" -eq 0 ]; then
		log_ok "$label already installed."
		return 0
	fi
	log_info "$label: installing ${to_install[*]}"
	if priv env DEBIAN_FRONTEND=noninteractive apt-get install -y \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		"${to_install[@]}"; then
		log_ok "$label installed."
		return 0
	else
		log_warn "$label: some packages failed to install (continuing)."
		return 1
	fi
}

# ensure_single_polkit_agent — polkitd accepts exactly ONE authentication
# agent per subject; a second agent dies at login with "an authentication
# agent already exists for the given subject". Hand-built installs often
# stack lxpolkit / mate-polkit / polkit-gnome next to the xfce-polkit this
# toolkit installs. Keep xfce-polkit and mask every other *system*
# autostart agent with a user-level Hidden=true override — never editing
# the package-owned /etc/xdg/autostart files, so the fix survives package
# upgrades and is reverted by deleting the mask. Read-only on the system;
# writes only into $XMLG_POLKIT_USER_AUTOSTART (default
# $HOME/.config/autostart). Idempotent: existing masks are left alone.
ensure_single_polkit_agent() {
	local sys_dir="${XMLG_POLKIT_SYS_AUTOSTART:-/etc/xdg/autostart}"
	local usr_dir="${XMLG_POLKIT_USER_AUTOSTART:-$HOME/.config/autostart}"
	local agent_re='lxpolkit|polkit-mate|polkit-gnome|lxqt-policykit|polkit-kde'
	local masked=() f name
	if [ ! -d "$sys_dir" ]; then
		log_info "No autostart dir at $sys_dir — single-polkit guard is a no-op."
		return 0
	fi
	if ! mkdir -p "$usr_dir" 2>/dev/null; then
		log_warn "Cannot create $usr_dir — single-polkit guard skipped."
		return 1
	fi
	for f in "$sys_dir"/*.desktop; do
		[ -f "$f" ] || continue
		# Only entries that are (or run) a foreign polkit auth agent.
		if ! grep -qiE "$agent_re" "$f" 2>/dev/null; then
			continue
		fi
		# The agent this toolkit installs is always welcome.
		if grep -qi 'xfce-polkit' "$f" 2>/dev/null; then
			continue
		fi
		name="$(basename "$f")"
		# Already masked at user level?
		if [ -f "$usr_dir/$name" ] && grep -q '^Hidden=true' "$usr_dir/$name" 2>/dev/null; then
			continue
		fi
		cat >"$usr_dir/$name" <<EOF
[Desktop Entry]
Type=Application
Name=${name%.desktop} (masked)
Comment=Disabled by xfcemlg: only xfce-polkit runs as the polkit auth agent
Exec=/bin/true
NoDisplay=true
Hidden=true
EOF
		masked+=("$name")
	done
	if [ "${#masked[@]}" -eq 0 ]; then
		log_ok "Single polkit agent: kept xfce-polkit, no foreign agents to mask."
	else
		log_ok "Single polkit agent: kept xfce-polkit; masked ${#masked[@]} foreign autostart(s)."
	fi
	return 0
}

# apt_update — refresh package lists exactly once per run. run.sh updates
# once up front and exports XMLG_SKIP_APT_UPDATE=1 so the per-script
# refreshes are no-ops; standalone runs still refresh here. Returns
# apt-get update's exit code so callers can abort if they want to.
apt_update() {
	[ -n "${XMLG_SKIP_APT_UPDATE:-}" ] && return 0
	if command_exists apt-get; then
		priv apt-get update "$@"
	else
		log_err "apt-get not found — this needs a Debian/Devuan APT system."
		return 1
	fi
}

# ensure_repo_component <component> [suite] — make sure an APT component
# (e.g. non-free-firmware) is actually available, adding an xfcemlg snippet
# file if the configured sources lack it. Minimal installs often ship
# without it, which would silently drop all firmware/microcode. Idempotent:
# no-op when already present, never edits existing files (writes only
# xfcemlg-<component>.sources), and refreshes package lists on change.
# Honors APT_SOURCES_D override (tests). Usage:
#   ensure_repo_component non-free-firmware && install_pkgs ...firmware...
ensure_repo_component() {
	local comp="$1" suite="${2:-}"
	local srcd="${APT_SOURCES_D:-/etc/apt/sources.list.d}"
	. /etc/os-release 2>/dev/null || true
	local id="${ID:-debian}"
	[ -z "$suite" ] && suite="${VERSION_CODENAME:-}"
	if [ -z "$suite" ]; then
		log_warn "ensure_repo_component: cannot detect suite codename."
		return 1
	fi
	if apt-cache policy 2>/dev/null | grep -Eq "(^|[, ])c=${comp}([, ]|$)"; then
		return 0
	fi
	log_info "APT component '$comp' missing — adding ${srcd}/xfcemlg-${comp}.sources ..."
	local uris="http://deb.debian.org/debian" sig=""
	if [ "$id" = "devuan" ]; then
		uris="http://deb.devuan.org/merged"
	else
		sig=$'\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg'
	fi
	mkdir -p "$srcd" 2>/dev/null || priv mkdir -p "$srcd"
	if [ -f "$srcd/xfcemlg-${comp}.sources" ]; then
		priv cp -a "$srcd/xfcemlg-${comp}.sources" "$srcd/xfcemlg-${comp}.sources.bak.$(date +%Y%m%d_%H%M%S)"
	fi
	priv tee "$srcd/xfcemlg-${comp}.sources" >/dev/null <<EOF
# Written by xfcemlg (ensure_repo_component) — base suite + firmware
# components. Safe to delete once your main sources carry '$comp' themselves.
Types: deb
URIs: $uris
Suites: $suite
Components: main contrib non-free non-free-firmware${sig}
EOF
	# Refresh only when the lists lack the component (common case: no-op above).
	priv apt-get update || {
		log_warn "apt-get update failed after adding '$comp'."
		return 1
	}
	apt-cache policy 2>/dev/null | grep -Eq "(^|[, ])c=${comp}([, ]|$)"
}

# check_repo_package — probe whether a package is even available before
# trying to install it. If it isn't, that almost always means a repo
# component (non-free-firmware / contrib) isn't enabled in sources.list.
# Usage: check_repo_package <probe-pkg> <component-hint>  -> 0 if available
check_repo_package() {
	local probe="$1" component="$2"
	local cand
	cand="$(apt-cache policy "$probe" 2>/dev/null | awk -F': ' '/Candidate:/{gsub(/ /,"",$2); print $2; exit}')"
	if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then
		return 0
	fi
	log_warn "$probe is not available — the '$component' repo component is probably missing."
	log_warn "On Debian, add the component to /etc/apt/sources.list.d/ (or run"
	log_warn "scripts/11-backports.sh which enables trixie-backports with all components),"
	log_warn "run 'apt-get update' as root, then re-run this step."
	return 1
}

# start_service — enable+start a service under whatever init this box
# actually runs: systemd (Debian default), OpenRC or sysvinit (Devuan).
# Never assumes systemd exists. sbin tools are invoked by absolute path
# because an escalator's PATH may not include /usr/sbin.
start_service() {
	local svc="$1"
	if command_exists systemctl && [ -d /run/systemd/system ]; then
		priv systemctl enable --now "$svc" >/dev/null 2>&1 || true
	elif { command_exists rc-service || [ -x /usr/sbin/rc-service ]; } &&
		[ -e /run/openrc/softlevel ]; then
		# Only offer services that actually have an OpenRC init script.
		# Several packages ship a systemd unit and nothing else (fwupd is
		# one), so the old unconditional rc-update/rc-service pair failed
		# silently behind >/dev/null 2>&1 || true and the caller logged a
		# success that never happened. Say so instead of pretending.
		if [ ! -x "/etc/init.d/$svc" ]; then
			log_warn "start_service: no /etc/init.d/$svc — $svc ships no OpenRC service (systemd-only package?)."
			log_warn "  Nothing was enabled or started. Schedule it yourself if it needs to run."
			return 1
		fi
		priv /usr/sbin/rc-update add "$svc" default >/dev/null 2>&1 || true
		priv /usr/sbin/rc-service "$svc" start >/dev/null 2>&1 || true
	else
		if command_exists update-rc.d || [ -x /usr/sbin/update-rc.d ]; then
			priv /usr/sbin/update-rc.d "$svc" defaults >/dev/null 2>&1 || true
		fi
		if command_exists service || [ -x /usr/sbin/service ]; then
			priv /usr/sbin/service "$svc" start >/dev/null 2>&1 || true
		fi
	fi
}

# sha256_verify — strict checksum verification where upstream publishes a
# known-good hash. Usage: sha256_verify <file> <expected-sha256>
sha256_verify() {
	local file="$1" expected="$2"
	[ -f "$file" ] || {
		log_err "sha256_verify: $file not found"
		return 1
	}
	local actual
	actual="$(sha256sum "$file" | cut -d' ' -f1)"
	if [ "$actual" = "$expected" ]; then
		log_ok "sha256 verified for $(basename "$file")."
		return 0
	fi
	log_err "sha256 MISMATCH for $(basename "$file")."
	log_err "  got:      $actual"
	log_err "  expected: $expected"
	return 1
}

# deploy_seed_file <src> <dest> [mode]
#
# Install a seed file WITHOUT silently destroying a file someone has since
# edited. The old behaviour in 21-theme.sh was: back up the destination to a
# timestamped .bak, then `cp` over it unconditionally. That is recoverable only
# by digging through an ever-growing pile of backups, and it means every re-run
# throws away whatever the user did in the GUI.
#
# A stamp file "<dest>.xfcemlg.sha256" records the sha256 of the seed exactly as
# it was installed, which lets a later run tell four cases apart:
#
#   dest missing            -> install, write the stamp
#   dest == stamp == src    -> already correct: no-op, no backup noise
#   dest == stamp, != src   -> nobody touched it since we wrote it, so it is
#                              safe to update in place (this is the upgrade path)
#   dest != stamp           -> someone edited it. DO NOT clobber. Back up, say
#                              so plainly, and leave the user's file in place.
#
# The fourth case is what the timestamped backup was trying to paper over.
# Escape hatch for the cases where the seed is policy and should win:
# XMLG_FORCE_SEEDS=1.
#
# Returns: 0 installed / updated / already correct
#          1 destination was modified since install — left alone
#          2 source seed missing
deploy_seed_file() {
	local src="$1" dest="$2" mode="${3:-}"
	local stamp="${dest}.xfcemlg.sha256"
	local src_sum dest_sum stamp_sum bak

	if [[ ! -f "$src" ]]; then
		log_warn "Seed missing: $src — leaving $(basename "$dest") unchanged."
		return 2
	fi

	src_sum="$(sha256sum "$src" 2>/dev/null | cut -d' ' -f1)"
	if [[ -z "$src_sum" ]]; then
		log_err "Could not checksum $src — refusing to deploy."
		return 2
	fi

	if [[ ! -f "$dest" ]]; then
		mkdir -p "$(dirname "$dest")" || return 1
		install ${mode:+-m "$mode"} "$src" "$dest" || return 1
		printf '%s\n' "$src_sum" >"$stamp"
		log_ok "Installed $(basename "$dest")."
		return 0
	fi

	dest_sum="$(sha256sum "$dest" 2>/dev/null | cut -d' ' -f1)"
	stamp_sum=""
	[[ -f "$stamp" ]] && stamp_sum="$(cat "$stamp" 2>/dev/null)"

	# Identical to the seed: nothing to do, and crucially no new .bak.
	if [[ "$dest_sum" == "$src_sum" ]]; then
		printf '%s\n' "$src_sum" >"$stamp"
		return 0
	fi

	# Modified since we installed it. Unless the operator has explicitly said
	# the seed wins, the user's edits are the truth.
	if [[ -n "$stamp_sum" && "$dest_sum" != "$stamp_sum" && "${XMLG_FORCE_SEEDS:-0}" != "1" ]]; then
		bak="${dest}.user.$(date +%Y%m%d%H%M%S)"
		cp -a "$dest" "$bak" 2>/dev/null || bak=""
		log_warn "$(basename "$dest") has local changes — left in place."
		[[ -n "$bak" ]] && log_info "  Your version backed up to $bak"
		log_info "  To take the shipped seed instead: XMLG_FORCE_SEEDS=1, or delete $dest"
		return 1
	fi

	# Unmodified since install (or forced): safe to update.
	if [[ -f "$dest" ]]; then
		cp -a "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
	fi
	install ${mode:+-m "$mode"} "$src" "$dest" || return 1
	printf '%s\n' "$src_sum" >"$stamp"
	log_ok "Updated $(basename "$dest") to the shipped seed."
	return 0
}

# xfce_xinitrc_path — the user xinitrc, i.e. the file startxfce4 prefers over
# the stock /etc/xdg/xfce4/xinitrc.
xfce_xinitrc_path() { printf '%s\n' "${HOME}/.config/xfce4/xinitrc"; }

# xfce_xinitrc_handoff — true when the user xinitrc still hands control back
# to the stock one. startxfce4 execs ~/.config/xfce4/xinitrc *instead of*
# /etc/xdg/xfce4/xinitrc, and only the stock file runs `exec xfce4-session`.
# A user xinitrc that reaches EOF without that handoff makes the session exit
# immediately: LightDM starts it, it returns, and you land back on the
# greeter with no panel, no wallpaper and no wm. Everything that writes to
# this file must go through xfce_xinitrc_append so the handoff survives.
xfce_xinitrc_handoff() {
	local f; f="$(xfce_xinitrc_path)"
	[[ -f "$f" ]] || return 1
	grep -qE '^[[:space:]]*exec[[:space:]]+/etc/xdg/xfce4/xinitrc' "$f"
}

# xfce_xinitrc_repair — restore the handoff on a user xinitrc that lost it
# (typically written by an older version of this toolkit). Backs up first, and
# is a no-op when the handoff is present or there is no file yet.
# Returns: 0 repaired / already fine, 1 nothing to do, 2 write failed
xfce_xinitrc_repair() {
	local f; f="$(xfce_xinitrc_path)"

	[[ -f "$f" ]] || return 1
	xfce_xinitrc_handoff && return 0

	cp -a "$f" "${f}.nohandoff.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
	{
		echo
		echo "# -- xfcemlg: hand off to the stock xinitrc --"
		echo "# Added by xfcemlg: without this, the XFCE session never starts."
		echo "exec /etc/xdg/xfce4/xinitrc \"\$@\""
	} >>"$f" || return 2

	chmod +x "$f" 2>/dev/null || true
	xfce_xinitrc_handoff || return 2
	log_ok "Restored the missing xinitrc handoff in $f (a backup was kept)."
	return 0
}

# xfce_xinitrc_append — append a snippet to the user xinitrc exactly once.
#
# The marker is a literal substring of what the caller writes, so the
# idempotence check and the written text can never drift apart. That drift is
# what shipped before: both snippets grepped for a string ("xfcemlg: natural
# scroll", "xfcemlg: Qt theme") that the heredoc never wrote, so every re-run
# appended a second copy.
#
# When the handoff is already present the snippet is spliced in *above* it.
# A plain append would land after the `exec`, and an exec never returns, so
# the snippet would be dead code.
#
# Usage: xfce_xinitrc_append <marker> <<'EOF' ... EOF
# Returns: 0 appended, 1 already present, 2 write failed
xfce_xinitrc_append() {
	local marker="$1" f snippet ins
	f="$(xfce_xinitrc_path)"

	[[ -n "$marker" ]] || { log_err "xfce_xinitrc_append: empty marker."; return 2; }

	if [[ -f "$f" ]] && grep -qF -- "$marker" "$f"; then
		return 1
	fi

	mkdir -p "$(dirname "$f")" || return 2
	snippet="$(mktemp)" || return 2
	cat >"$snippet" || { rm -f "$snippet"; return 2; }

	if [[ -f "$f" ]]; then
		cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
	fi

	# First line of the handoff block: our own comment if we added it,
	# otherwise the exec itself (a hand-written handoff may lack the comment).
	ins="$(grep -nE \
		'xfcemlg: hand off to the stock xinitrc|^[[:space:]]*exec[[:space:]]+/etc/xdg/xfce4/xinitrc' \
		"$f" 2>/dev/null | head -1 | cut -d: -f1)"

	if [[ -n "$ins" ]]; then
		{
			head -n "$((ins - 1))" "$f"
			cat "$snippet"
			echo
			tail -n "+$ins" "$f"
		} >"$f.new" || { rm -f "$snippet" "$f.new"; return 2; }
		mv "$f.new" "$f" || { rm -f "$snippet"; return 2; }
	else
		cat "$snippet" >>"$f" || { rm -f "$snippet"; return 2; }
		# The snippet landed; make sure the session can still start afterwards.
		xfce_xinitrc_repair >/dev/null || true
	fi

	rm -f "$snippet"
	chmod +x "$f" 2>/dev/null || true

	# If the snippet landed below the handoff it is unreachable, which is the
	# very failure this whole helper exists to prevent.
	if ! grep -qE '^[[:space:]]*exec[[:space:]]+/etc/xdg/xfce4/xinitrc' "$f"; then
		log_err "xinitrc has no /etc/xdg/xfce4/xinitrc handoff — XFCE will not start."
		return 2
	fi
	return 0
}

# verify_download — structural sanity check for anything this toolkit
# fetches: non-empty, and a valid archive/package/zip of its expected
# kind. This is a *plausibility* check (catches truncation, HTML error
# pages, 404 bodies), not a substitute for sha256_verify where upstream
# publishes hashes. Always logs the computed sha256 so you can compare
# against a release page manually.
# Usage: verify_download <file> [min-size-bytes]  (min default 1024)
verify_download() {
	local file="$1"
	local min_size="${2:-1024}"
	[ -f "$file" ] || {
		log_err "verify_download: $file not found."
		return 1
	}

	local size
	size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
	if [ "$size" -lt "$min_size" ]; then
		log_err "$(basename "$file") looks empty/truncated (${size} bytes)."
		return 1
	fi

	case "$file" in
	*.deb)
		if ! dpkg-deb --info "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid .deb package."
			return 1
		fi
		;;
	*.tar.gz | *.tgz)
		if ! tar -tzf "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid tar.gz."
			return 1
		fi
		;;
	*.tar.bz2)
		if ! tar -tjf "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid tar.bz2."
			return 1
		fi
		;;
	*.tar.xz)
		if ! tar -tJf "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid tar.xz."
			return 1
		fi
		;;
	*.tar)
		if ! tar -tf "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid tar."
			return 1
		fi
		;;
	*.zip)
		if ! unzip -t "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid zip."
			return 1
		fi
		;;
	*.gz)
		if ! gzip -t "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid gzip."
			return 1
		fi
		;;
	*.xz)
		if ! xz -t "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid xz."
			return 1
		fi
		;;
	*.bz2)
		if ! bzip2 -t "$file" >/dev/null 2>&1; then
			log_err "$(basename "$file") is not a valid bz2."
			return 1
		fi
		;;
	esac

	log_ok "Download verified: $(basename "$file") (${size} bytes)."
	return 0
}
