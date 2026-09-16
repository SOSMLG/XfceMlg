#!/usr/bin/env bash
# DEBSWAY_DESC: First-run welcome + wallpaper seeder + Firefox bookmarks
# DEBSWAY_DEFAULT: Y
# =======================================================
# First run — welcome wizard + wallpaper seeder
# -------------------------------------------------------
# Deploys two autostart entries (sources in configs/bin/):
#   xfce-first-run      once per user (done-file): welcome, system
#                       update (chrony-aware clock wait), Timeshift
#                       check, ~/Screenshots seed.
#   xfce-seed-wallpaper every login: default backdrop ONLY on monitors
#                       with no backdrop yet — never overwrites a
#                       wallpaper the user already chose.
# Adapted from Butterbian's first-run-setup + set-wallpaper (their
# timedatectl NTP wait is systemd-only; chrony is used here).
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "First-run welcome + wallpaper seeder"

BIN_SRC_DIR="$SCRIPT_DIR/../configs/bin"
LOCAL_BIN="$HOME/.local/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$LOCAL_BIN" "$AUTOSTART_DIR"

deploy() {  # deploy <src-name> <autostart-name> <app-name> <comment>
    local src="$BIN_SRC_DIR/$1" dest="$LOCAL_BIN/$1"
    if [[ ! -f "$src" ]]; then
        log_warn "Source missing: $src — skipping."
        return 1
    fi
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        log_ok "$1 already deployed and current."
    else
        [[ -f "$dest" ]] && cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
        cp "$src" "$dest"
        chmod +x "$dest"
        log_ok "Deployed $dest."
    fi
    local entry="$AUTOSTART_DIR/$2"
    if [[ -f "$entry" ]]; then
        log_ok "Autostart entry already present: $2"
    else
        cat > "$entry" << EOF
[Desktop Entry]
Type=Application
Name=$3
Comment=$4
Exec=$dest
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        log_ok "Autostart entry created: $2"
    fi
}

if ask "Deploy the first-run welcome wizard (runs once, on next graphical login)?"; then
    deploy "xfce-first-run" "xfce-first-run.desktop" \
        "XFCE First Run" "Welcome wizard: update + Timeshift check (once)." || true
fi

if ask "Deploy the wallpaper seeder (fills only monitors with no backdrop yet)?"; then
    deploy "xfce-seed-wallpaper" "xfce-seed-wallpaper.desktop" \
        "Seed Default Wallpaper" "Default backdrop for new monitors only — never overwrites yours." || true
fi

# Curated bookmark set (Devuan, XFCE, ThinkPad, tools) — deployed as an
# importable HTML, not injected into a live places.sqlite (writing to a
# running Firefox profile DB is fragile and version-sensitive).
if ask "Deploy the curated Firefox bookmarks file (~/bookmarks.html, import in one click)?"; then
    BK_SRC="$SCRIPT_DIR/../configs/firefox/bookmarks.html"
    if [[ -f "$BK_SRC" ]]; then
        cp "$BK_SRC" "$HOME/bookmarks.html"
        log_ok "Bookmarks deployed to ~/bookmarks.html."
        log_info "Import with: firefox -import-bookmarks-from-html ~/bookmarks.html"
    else
        log_warn "Bookmarks source missing at $BK_SRC — skipping."
    fi
fi

# ~/.local/bin must be on PATH for the autostart Exec lines to resolve
# when the session starts with a minimal PATH.
if ! grep -qF "$LOCAL_BIN" "$HOME/.bashrc" 2>/dev/null; then
    echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$HOME/.bashrc"
    log_ok "Added $LOCAL_BIN to PATH in ~/.bashrc"
fi

log_ok "First-run step complete."
