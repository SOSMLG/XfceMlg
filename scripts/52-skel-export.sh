#!/usr/bin/env bash
# DEBSWAY_DESC: (utility) per-user defaults into /etc/skel
# DEBSWAY_DEFAULT: Y
# =======================================================
# Export to /etc/skel
# -------------------------------------------------------
# Copies a curated set of per-user config produced by this
# toolkit into /etc/skel, so every FUTURE user account on
# that machine (and any image built from this toolkit) starts
# with the same defaults: alacritty, GTK, panel, fastfetch,
# Thunar, fonts, .desktop entries.
#
# Existing files in /etc/skel are never clobbered unless
# --force is given. Uses priv() for privilege escalation.
#
#   bash scripts/52-skel-export.sh              # copy (escalated via priv)
#   bash scripts/52-skel-export.sh --user bob   # copy from bob's HOME
#   bash scripts/52-skel-export.sh --list       # show what would be copied
#   bash scripts/52-skel-export.sh --dry-run    # copy plan, no changes
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Which user's config to export. Default: the invoking user; when run with
# doas exports DOAS_USER (sudo exports SUDO_USER). In the ISO chroot (root, neither set) use --user.
SOURCE_USER="${SUDO_USER:-${DOAS_USER:-$USER}}"
MODE="copy"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --user) SOURCE_USER="$2"; shift 2 ;;
        --list) MODE="list" ; shift ;;
        --dry-run) MODE="dry-run"; shift ;;
        --force) FORCE=1; shift ;;
        *) log_err "Unknown option: $1 (use --user, --list, --dry-run, --force)."; exit 1 ;;
    esac
done

SOURCE_HOME="$(getent passwd "$SOURCE_USER" 2>/dev/null | cut -d: -f6)"
if [ -z "$SOURCE_HOME" ] || [ ! -d "$SOURCE_HOME" ]; then
    log_err "Could not resolve a home directory for '$SOURCE_USER'. Aborting."
    exit 1
fi
SKEL="${SKEL_DIR:-/etc/skel}"

CANDIDATES=(
    "$SOURCE_HOME/.local/share/fonts"
    "$SOURCE_HOME/.local/share/applications"
    "$SOURCE_HOME/.local/share/icons"
    "$SOURCE_HOME/.config/xfce4"
    "$SOURCE_HOME/.config/Thunar"
    "$SOURCE_HOME/.config/fastfetch"
    "$SOURCE_HOME/.config/butterbash"
    "$SOURCE_HOME/.butterbash"
)

found=0
for src in "${CANDIDATES[@]}"; do
    [ -e "$src" ] && found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
    log_warn "Nothing in the export set exists under $SOURCE_HOME yet."
    log_warn "Run the toolkit scripts first (or pick a different --user)."
    exit 0
fi

if [ "$MODE" = "list" ]; then
    echo -e "${CYAN}Would export from $SOURCE_HOME into $SKEL:${NC}"
    for src in "${CANDIDATES[@]}"; do
        [ -e "$src" ] && echo "  $src"
    done
    exit 0
fi

log_head "Exporting default config to $SKEL (user: $SOURCE_USER)"

copied=0
for src in "${CANDIDATES[@]}"; do
    [ -e "$src" ] || continue
    # Rebuild the destination path under /etc/skel (e.g. ~/.config/foo -> /etc/skel/.config/foo).
    dest="$SKEL/${src#"$SOURCE_HOME"/}"

    if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
        [ "$MODE" = "copy" ] && log_warn "Already in skel, not clobbering: $dest (--force to overwrite)"
        continue
    fi

    if [ "$MODE" = "copy" ]; then
        priv mkdir -p "$(dirname "$dest")"
        if priv cp -r "$src" "$dest"; then
            log_ok "  → $dest"
            copied=$((copied + 1))
        else
            log_err "  ✗ $src (copy failed)"
        fi
    else
        echo "  → $dest"
    fi
done

if [ "$MODE" = "copy" ]; then
    [ "$copied" -eq 0 ] && log_ok "Nothing new to copy."
    echo
    log_info "New accounts will inherit these defaults. Existing users are unchanged"
    log_info "(their HOME was already created without skel)."
fi