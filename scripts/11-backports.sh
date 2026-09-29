#!/usr/bin/env bash
# XMLG_DESC: Backports repo (excalibur-backports) + apt pinning
# XMLG_DEFAULT: Y
# =======================================================
# Backports — enable <suite>-backports + apt pinning
# -------------------------------------------------------
# Backports let you pull newer versions of stable packages
# (e.g. a newer mesa, linux-image, xfce4-panel) without upgrading
# the whole distro. They're installed at priority 100 here,
# so you only get them when you explicitly ask for a
# -t <suite>-backports install, or when something depends
# on a newer package pulled in that way.
#
# Works on Debian 13 "trixie" AND Devuan 6 "excalibur"
# (suites auto-detected from /etc/os-release).
# On Devuan the backports suite normally ships via the merged repo, so the
# common path only ensures the apt pinning. We VERIFY that assumption
# against apt-cache rather than trusting it, and write the suite ourselves
# when it is missing; a stale Debian-mirror backports file is retired only
# after asking, because it can shadow the pinned suite.
#
# Also ensures the 'contrib' component, which a minimal Devuan sources.list
# lacks but libdvd-pkg (15) and steam/winetricks (44) require.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

log_head "Backports"

. /etc/os-release
ID="${ID:-debian}"
CODENAME="${VERSION_CODENAME:-}"
if [ -z "$CODENAME" ]; then
	CODENAME="$(grep -oP '(?<=\t)[a-z]+(?=$)' /etc/debian_version 2>/dev/null || true)"
fi
if [ -z "$CODENAME" ]; then
	log_err "Couldn't detect the suite codename from /etc/os-release."
	log_err "Set CODENAME=<suite> and re-run, or add backports manually."
	exit 1
fi

BACKPORTS_SUITE="${CODENAME}-backports"
PREFS_FILE="/etc/apt/preferences.d/backports"
SRCS_FILE="/etc/apt/sources.list.d/debian-backports.sources"
DEVSRCS_FILE="/etc/apt/sources.list.d/devuan-backports.sources"

# contrib/non-free are NOT in a minimal Devuan sources.list, but
# libdvd-pkg (15) and steam/winetricks (44) live there. One call, and it
# returns immediately when the component is already present.
ensure_repo_component contrib ||
	log_warn "Could not ensure the 'contrib' component — some installs may fail."

# backports_suite_live — is the suite actually visible to apt?
backports_suite_live() {
	apt-cache policy 2>/dev/null | grep -qi -- "$BACKPORTS_SUITE"
}

# Devuan usually provides <suite>-backports from deb.devuan.org/merged, but
# that is NOT guaranteed on a minimal sources.list. Verify it, and write the
# suite ourselves when it is missing rather than claiming that it is there.
NEED_WRITE=0
if [ "$ID" = "devuan" ]; then
	if backports_suite_live; then
		log_ok "$BACKPORTS_SUITE is live (provided by devuan.org/merged) — no extra file needed."
	elif [ -f "$DEVSRCS_FILE" ] && grep -qi "$BACKPORTS_SUITE" "$DEVSRCS_FILE"; then
		log_ok "$DEVSRCS_FILE already provides $BACKPORTS_SUITE."
	else
		log_info "$BACKPORTS_SUITE is not in apt's view — enabling it explicitly."
		NEED_WRITE=1
		priv mkdir -p /etc/apt/sources.list.d
		if [ -f "$DEVSRCS_FILE" ]; then
			priv cp -a "$DEVSRCS_FILE" "${DEVSRCS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
		fi
		priv tee "$DEVSRCS_FILE" >/dev/null <<EOF
# Written by xfcemlg 11-backports.sh — $BACKPORTS_SUITE
# Devuan's merged archive. Never auto-upgraded to; see the pin below.
Types: deb
URIs: http://deb.devuan.org/merged
Suites: ${BACKPORTS_SUITE}
Components: main contrib non-free non-free-firmware
EOF
		log_ok "Wrote $DEVSRCS_FILE"
	fi
	# A Debian-mirror backports file is wrong on Devuan (different archive,
	# and it would shadow the pinned suite). Retire it — but only after
	# asking, because it lives in a shared system directory we do not own.
	if [ -f "$SRCS_FILE" ]; then
		if ask_no_full "Devuan provides $BACKPORTS_SUITE itself. Remove the redundant Debian-mirror $SRCS_FILE?" "N"; then
			priv cp -a "$SRCS_FILE" "${SRCS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
			priv rm "$SRCS_FILE"
			log_ok "Removed stale Debian-mirror $SRCS_FILE (backup kept)."
		else
			log_warn "Left $SRCS_FILE in place — it may shadow $BACKPORTS_SUITE."
		fi
	fi
	# fall through to pinning only
else
	log_info "Detected Debian suite: $CODENAME  →  enabling ${BACKPORTS_SUITE}"

	# ---------------------------------------------------------------------------
	# 1. The repo itself (deb822 .sources — the trixie-native format)
	# ---------------------------------------------------------------------------
	NEED_WRITE=1
	if [ -f "$SRCS_FILE" ] && grep -qi "$BACKPORTS_SUITE" "$SRCS_FILE"; then
		log_ok "$SRCS_FILE already references $BACKPORTS_SUITE."
		NEED_WRITE=0
	fi

	if [ "$NEED_WRITE" -eq 1 ]; then
		priv mkdir -p /etc/apt/sources.list.d
		if [ -f "$SRCS_FILE" ]; then
			priv cp "$SRCS_FILE" "${SRCS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
		fi
		priv tee "$SRCS_FILE" >/dev/null <<EOF
# Written by xfcemlg 11-backports.sh — $BACKPORTS_SUITE
# Backports hold newer versions of stable packages; they are NOT
# installed automatically (see the apt pinning in $PREFS_FILE).
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${BACKPORTS_SUITE}
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
		log_ok "Wrote $SRCS_FILE"
	fi
fi

# ---------------------------------------------------------------------------
# 2. Apt pinning — backports at priority 100 (don't auto-upgrade to them)
# ---------------------------------------------------------------------------
if [ -f "$PREFS_FILE" ] && grep -q "release a=${BACKPORTS_SUITE}" "$PREFS_FILE"; then
	log_ok "Apt pin for $BACKPORTS_SUITE already present."
else
	if [ -f "$PREFS_FILE" ]; then
		priv cp "$PREFS_FILE" "${PREFS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
	fi
	priv tee "$PREFS_FILE" >/dev/null <<EOF
# Written by xfcemlg 11-backports.sh
# Never auto-upgrade to backports; only explicit -t ${BACKPORTS_SUITE}
# installs (or direct dependency pulls) select these versions.
Package: *
Pin: release a=${BACKPORTS_SUITE}
Pin-Priority: 100
EOF
	log_ok "Wrote $PREFS_FILE (pin-priority 100)"
fi

# ---------------------------------------------------------------------------
# 3. Refresh + verify
# ---------------------------------------------------------------------------
log_info "Refreshing package lists (backports included)..."
# run.sh already refreshes once and exports XMLG_SKIP_APT_UPDATE=1; only
# re-update here when this script actually wrote a source file (Debian case).
if [ "$NEED_WRITE" -ne 1 ] && [ -n "${XMLG_SKIP_APT_UPDATE:-}" ]; then
	log_info "Package lists already refreshed this run (XMLG_SKIP_APT_UPDATE=1)."
elif priv apt-get update; then
	if backports_suite_live; then
		log_ok "$BACKPORTS_SUITE is live. Install from it with:"
		log_ok "    doas apt install -t ${BACKPORTS_SUITE} <package>"
		log_ok "e.g. newer mesa: doas apt install -t ${BACKPORTS_SUITE} mesa"
	else
		log_warn "$BACKPORTS_SUITE didn't visibly show up in apt-cache policy yet —"
		log_warn "double-check $SRCS_FILE contents, then 'doas apt-get update'."
	fi
else
	log_warn "apt-get update failed — check your network and the new sources file."
fi

echo
log_ok "Backports setup complete."
log_info "Tip: to check what huge kernels/mesa are available:"
log_info "  apt policy linux-image-amd64   (shows backports candidate)"
