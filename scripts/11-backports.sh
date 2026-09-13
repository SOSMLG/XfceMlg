#!/usr/bin/env bash
# DEBSWAY_DESC: Backports repo (excalibur-backports) + apt pinning
# DEBSWAY_DEFAULT: Y
# =======================================================
# Backports — enable <suite>-backports + apt pinning
# -------------------------------------------------------
# Backports let you pull newer versions of stable packages
# (e.g. a newer sway, mesa, linux-image) without upgrading
# the whole distro. They're installed at priority 100 here,
# so you only get them when you explicitly ask for a
# -t <suite>-backports install, or when something depends
# on a newer package pulled in that way.
#
# Works on Debian 13 "trixie" AND Devuan 6 "excalibur"
# (suites auto-detected from /etc/os-release).
# On Devuan the backports suite ships in the merged repo via
# sources.list already, so we only ensure the apt pinning and
# retire any stale Debian-mirror backports file from an earlier
# (wrong-Distro) run.
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

# Devuan already provides <suite>-backports from deb.devuan.org/merged,
# so the Debian-mirror file (URIs: deb.debian.org) is wrong AND redundant.
if [ "$ID" = "devuan" ]; then
    log_info "Detected Devuan $CODENAME — backports suite ships in sources.list already."
    if [ -f "$SRCS_FILE" ]; then
        priv cp -a "$SRCS_FILE" "${SRCS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        priv rm "$SRCS_FILE"
        log_ok "Removed stale Debian-mirror $SRCS_FILE (Devuan provides $BACKPORTS_SUITE)."
    else
        log_ok "$BACKPORTS_SUITE is provided by devuan.org/merged sources.list — no extra file needed."
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
        priv tee "$SRCS_FILE" > /dev/null << EOF
# Written by deb-sway-thinkpad 11-backports.sh — $BACKPORTS_SUITE
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
    priv tee "$PREFS_FILE" > /dev/null << EOF
# Written by deb-sway-thinkpad 11-backports.sh
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
if priv apt-get update; then
    if apt-cache policy 2>/dev/null | sed -n 's/^ .*n/\n&/p' | grep -qi "$BACKPORTS_SUITE" \
        || priv apt-cache policy 2>/dev/null | grep -qi "$BACKPORTS_SUITE"; then
        log_ok "$BACKPORTS_SUITE is live. Install from it with:"
        log_ok "    doas apt install -t ${BACKPORTS_SUITE} <package>"
        log_ok "e.g. newer sway: doas apt install -t ${BACKPORTS_SUITE} sway"
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