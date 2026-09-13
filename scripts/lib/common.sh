#!/usr/bin/env bash
# =======================================================
# common.sh — shared helpers, sourced by every toolkit script
# -------------------------------------------------------
# Every script in this toolkit sources this file for the shared helpers
# (colors, logging, is_installed, ask, install_pkgs, service management,
# download verification). Each script remains independently runnable —
# `bash scripts/<name>.sh` works fine because lib/ ships with the repo.
#
# Ported from deb-sway-thinkpad's lib/common.sh (same contract, same
# DEBSWAY_* env names so muscle memory transfers between the two toolkits).
#
# Environment variables honored (all optional):
#   DEBSWAY_ASSUME_YES=1        ask() answers with its default instead of prompting
#   DEBSWAY_SKIP_APT_UPDATE=1   apt_update() is a no-op (run.sh updates once)
#   DEBSWAY_PRIV=doas|priv      force the privilege escalator (default: doas, priv fallback)
# =======================================================

# sbin lives outside a normal user's PATH, but this toolkit drives sysadmin
# tools (usermod, rc-service, ufw, rfkill...). Export it once here so
# command -v checks and direct calls resolve before any escalation.
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH" ;;
esac

# Guard against being sourced twice in the same shell.
[ -n "${_DEBSWAY_COMMON_SH_LOADED:-}" ] && return 0
_DEBSWAY_COMMON_SH_LOADED=1

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; CYAN="\033[0;36m"; NC="\033[0m"

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

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
# DEBSWAY_PRIV=doas|sudo forces one. Flags pass through (-n and -u exist
# in both). Usage: priv apt-get install -y foo / priv -n reboot
priv() {
    local tool="${DEBSWAY_PRIV:-}"
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
    # Minimal installs often ship an escalator the user can't actually use
    # (sudo installed but user in no empowered group, doas without a rule):
    # escalation then dies mid-run with a bare password rejection. Warn once,
    # early, with the exact fix — never fatal, the user may know better.
    if ! id -nG 2>/dev/null | grep -qwE "sudo|wheel|doas" \
       && ! grep -qw "$USER" /etc/doas.conf 2>/dev/null; then
        log_warn "Your user is in no privilege group (sudo/wheel) and /etc/doas.conf names no rule for $USER."
        log_warn "Escalation is likely to fail. Fix with ONE of these (as root), then relogin:"
        log_warn "  usermod -aG sudo $USER   # Debian stock path"
        log_warn "  printf 'permit persist $USER as root\n' > /etc/doas.conf   # BSD-minimal path"
    fi
}

# Real (non-root) user, even if this got invoked via escalation upstream.
# doas exports DOAS_USER the way sudo exports SUDO_USER.
ACTUAL_USER="${SUDO_USER:-${DOAS_USER:-$USER}}"
[ -z "$ACTUAL_USER" ] && ACTUAL_USER="$(id -un)"

run_as_user() {
    if [ "$(id -un)" = "$ACTUAL_USER" ]; then
        "$@"
    else
        priv -u "$ACTUAL_USER" "$@"
    fi
}

# ensure_doas_persist [user] — make sure /etc/doas.conf grants
#   permit persist <user> as root
# (root-owned, mode 600). Idempotent: no-op when such a rule already
# exists. A persist-less rule for the same user is NOT edited in place —
# doas.conf(5) is "last match wins", so the correct line is appended and
# overrides any earlier one. Honors DOAS_CONF override (tests).
# Needs one working escalator for the write; on failure prints the manual
# fix instead of dying mid-run.
ensure_doas_persist() {
    local user="${1:-$ACTUAL_USER}"
    local conf="${DOAS_CONF:-/etc/doas.conf}"
    local want="permit persist $user as root"
    if [ -z "$user" ] || [ "$user" = "root" ]; then
        log_err "ensure_doas_persist: refusing bad user '$user'."
        return 1
    fi
    if [ -f "$conf" ] \
        && grep -Eq "^[[:space:]]*permit\b.*\bpersist\b.*\b$user\b" "$conf" 2>/dev/null; then
        log_ok "doas persist rule already present for '$user' ($conf)."
        if [ "$(stat -c%a "$conf" 2>/dev/null || echo '')" != "600" ]; then
            priv chmod 600 "$conf" 2>/dev/null \
                || log_warn "Could not chmod 600 $conf."
        fi
        return 0
    fi
    log_info "Ensuring doas persist rule: '$want' in $conf ..."
    if [ -f "$conf" ]; then
        priv cp -a "$conf" "$conf.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    if printf '%s\n' "$want" | priv tee -a "$conf" >/dev/null \
        && priv chmod 600 "$conf" 2>/dev/null; then
        if command_exists doas && ! priv doas -C "$conf" >/dev/null 2>&1; then
            log_warn "doas -C rejects $conf — check its syntax."
        fi
        log_ok "doas persist rule added for '$user' (root-owned, mode 600)."
        return 0
    fi
    log_err "Could not write $conf (no working escalator)."
    log_warn "As root, run: printf '$want\n' >> $conf && chmod 600 $conf"
    return 1
}

# ask() — "Y/n" (default Y) or "y/N" (default N) prompt. With
# DEBSWAY_ASSUME_YES set (run.sh --yes, or install.sh), the default is
# taken without prompting so the toolkit can run unattended.
ask() {
    local prompt="$1" default="${2:-Y}" reply
    local hint="(Y/n)"
    [ "$default" = "N" ] && hint="(y/N)"
    if [ -n "${DEBSWAY_ASSUME_YES:-}" ]; then
        reply="$default"
    else
        read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${NC}")" reply
        reply=${reply:-$default}
    fi
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_pkgs() {
    local label="$1"; shift
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
    if priv apt-get install -y "${to_install[@]}"; then
        log_ok "$label installed."
        return 0
    else
        log_warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

# apt_update — refresh package lists exactly once per run. run.sh updates
# once up front and exports DEBSWAY_SKIP_APT_UPDATE=1 so the per-script
# refreshes are no-ops; standalone runs still refresh here. Returns
# apt-get update's exit code so callers can abort if they want to.
apt_update() {
    [ -n "${DEBSWAY_SKIP_APT_UPDATE:-}" ] && return 0
    if command_exists apt-get; then
        priv apt-get update "$@"
    else
        log_err "apt-get not found — this needs a Debian/Devuan APT system."
        return 1
    fi
}

# ensure_repo_component <component> [suite] — make sure an APT component
# (e.g. non-free-firmware) is actually available, adding an xfce-setup snippet
# file if the configured sources lack it. Minimal installs often ship
# without it, which would silently drop all firmware/microcode. Idempotent:
# no-op when already present, never edits existing files (writes only
# xfce-setup-<component>.sources), and refreshes package lists on change.
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
    log_info "APT component '$comp' missing — adding ${srcd}/xfce-setup-${comp}.sources ..."
    local uris="http://deb.debian.org/debian" sig=""
    if [ "$id" = "devuan" ]; then
        uris="http://deb.devuan.org/merged"
    else
        sig=$'\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg'
    fi
    mkdir -p "$srcd" 2>/dev/null || priv mkdir -p "$srcd"
    if [ -f "$srcd/xfce-setup-${comp}.sources" ]; then
        priv cp -a "$srcd/xfce-setup-${comp}.sources" "$srcd/xfce-setup-${comp}.sources.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    priv tee "$srcd/xfce-setup-${comp}.sources" > /dev/null << EOF
# Written by xfce-setup (ensure_repo_component) — base suite + firmware
# components. Safe to delete once your main sources carry '$comp' themselves.
Types: deb
URIs: $uris
Suites: $suite
Components: main contrib non-free non-free-firmware${sig}
EOF
    # Refresh only when the lists lack the component (common case: no-op above).
    priv apt-get update || { log_warn "apt-get update failed after adding '$comp'."; return 1; }
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
    elif { command_exists rc-service || [ -x /usr/sbin/rc-service ]; } \
            && [ -d /run/openrc/softlevel ]; then
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
    [ -f "$file" ] || { log_err "sha256_verify: $file not found"; return 1; }
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
    [ -f "$file" ] || { log_err "verify_download: $file not found."; return 1; }

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
        *.tar.gz|*.tgz)
            if ! tar -tzf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar.gz."; return 1; fi
            ;;
        *.tar.bz2)
            if ! tar -tjf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar.bz2."; return 1; fi
            ;;
        *.tar.xz)
            if ! tar -tJf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar.xz."; return 1; fi
            ;;
        *.tar)
            if ! tar -tf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar."; return 1; fi
            ;;
        *.zip)
            if ! unzip -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid zip."; return 1; fi
            ;;
        *.gz)
            if ! gzip -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid gzip."; return 1; fi
            ;;
        *.xz)
            if ! xz -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid xz."; return 1; fi
            ;;
        *.bz2)
            if ! bzip2 -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid bz2."; return 1; fi
            ;;
    esac

    log_ok "Download verified: $(basename "$file") (${size} bytes)."
    return 0
}