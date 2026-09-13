#!/usr/bin/env bash
# DEBSWAY_DESC: (utility) timestamped HOME config backup
# DEBSWAY_DEFAULT: N
# =======================================================
# Config Backup / Restore
# -------------------------------------------------------
# Snapshots the per-user config this toolkit creates
# (~/.config, dotfiles, ~/.local/bin, fonts, desktop
# entries) into one timestamped archive, so a fresh
# reinstall — or a new ISO test VM — can restore your
# setup in one command instead of re-running everything.
#
#   bash scripts/51-backup.sh                # backup
#   bash scripts/51-backup.sh backup         # same
#   bash scripts/51-backup.sh list           # contents of newest archive
#   bash scripts/51-backup.sh restore        # restore newest (asks first)
#
# Keeps the 5 newest archives. Override the output dir with
# CONFIG_BACKUP_DIR=/path (default: $HOME).
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

ACTION="${1:-backup}"
BACKUP_ROOT="${CONFIG_BACKUP_DIR:-$HOME}"
KEEP=5

# Paths this toolkit actually creates/touches, collected under one roof.
CANDIDATES=(
    "$HOME/.config"
    "$HOME/.local/share/applications"
    "$HOME/.local/share/fonts"
    "$HOME/.local/share/icons"
    "$HOME/.themes"
    "$HOME/.icons"
    "$HOME/.local/bin"
    "$HOME/.bashrc"
    "$HOME/.bash_aliases"
    "$HOME/.profile"
)

# Heavy, throwaway or not-safely-restorable state we never want in the archive.
# Relative to $HOME (tar runs with -C $HOME, so excludes must match too).
EXCLUDES=(
    ".config/google-chrome"
    ".config/chromium"
    ".config/BraveSoftware"
    ".config/microsoft-edge"
    ".cache"
    "*Cache*"
    "*/node_modules/*"
    "*/__pycache__/*"
)

# newest_archive <glob...> — newest file by mtime, no ls-parsing (spaces safe).
newest_archive() {
    local best="" best_mtime=0 f m
    shopt -s nullglob
    for f in "$BACKUP_ROOT"/xfce-config-backup-*.tar.gz; do
        m="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
        if [ "$m" -gt "$best_mtime" ]; then best_mtime="$m"; best="$f"; fi
    done
    shopt -u nullglob
    [ -n "$best" ] && printf '%s\n' "$best"
}

latest_archive() { newest_archive; }

do_backup() {
    local existing=()
    local include=()
    local src
    for src in "${CANDIDATES[@]}"; do
        [ -e "$src" ] && include+=("$src")
    done
    [ "${#include[@]}" -eq 0 ] && { log_warn "Nothing in the backup set exists yet — nothing to back up."; return 1; }

    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local archive="$BACKUP_ROOT/xfce-config-backup-${stamp}.tar.gz"

    mkdir -p "$BACKUP_ROOT"
    log_info "Creating backup: $archive"
    log_info "  including: ${include[*]}"

    local tar_args=(-czf "$archive")
    local ex
    for ex in "${EXCLUDES[@]}"; do
        tar_args+=(--exclude="$ex")
    done
    # Relative to $HOME so the archive extracts cleanly with -C $HOME
    # (absolute paths would restore to $HOME/home/$USER/... instead).
    local rel=()
    local src
    for src in "${include[@]}"; do
        rel+=("${src#"$HOME"/}")
    done

    if ! tar -C "$HOME" "${tar_args[@]}" "${rel[@]}" >/dev/null 2>&1; then
        log_err "Backup failed — see message above."
        rm -f "$archive"
        return 1
    fi

    # Stash the runner log alongside (not inside) the archive for context.
    [ -f "$HOME/.local/state/devuan-xfce-setup/last-run.log" ] \
        && cp "$HOME/.local/state/devuan-xfce-setup/last-run.log" "$archive.log"

    log_ok "Backup created: $archive ($(du -h "$archive" | cut -f1))"

    # Rotation: keep only the KEEP newest archives (and their .log siblings).
    local all=() f
    shopt -s nullglob
    all=("$BACKUP_ROOT"/xfce-config-backup-*.tar.gz)
    shopt -u nullglob
    if [ "${#all[@]}" -gt "$KEEP" ]; then
        local sorted old
        sorted="$(for f in "${all[@]}"; do printf '%s\t%s\n' "$(stat -c %Y "$f" 2>/dev/null || echo 0)" "$f"; done | sort -rn | cut -f2-)"
        local n=0
        while IFS= read -r old; do
            [ -z "$old" ] && continue
            n=$((n + 1))
            [ "$n" -le "$KEEP" ] && continue
            log_warn "Rotating out old backup: $old"
            rm -f "$old" "$old.log"
        done <<< "$sorted"
    fi

    return 0
}

do_list() {
    local archive
    archive="$(latest_archive)" || true
    [ -z "$archive" ] && { log_warn "No backups found in $BACKUP_ROOT."; return 1; }
    log_info "Newest backup: $archive"
    echo
    tar -tzf "$archive" 2>/dev/null | sort -u | grep -v '^$' | head -80
    echo
    log_info "(first 80 unique paths shown — full list in the archive itself)"
}

do_restore() {
    local archive="${2:-}"
    [ -z "$archive" ] && archive="$(latest_archive)"
    if [ -z "$archive" ] || [ ! -f "$archive" ]; then
        log_err "No backup archive to restore (looked in $BACKUP_ROOT)."
        exit 1
    fi
    log_warn "Restoring $archive into $HOME — this overwrites files in the paths it contains."
    if ! ask "Continue with restore?" "N"; then
        log_info "Restore cancelled."
        exit 0
    fi
    if ! tar -xzf "$archive" -C "$HOME" --overwrite; then
        log_err "Restore failed (see message above)."
        exit 1
    fi
    log_ok "Restore complete. Log out and back in to pick up config changes."
}

case "$ACTION" in
    backup)
        do_backup
        ;;
    list)
        do_list
        ;;
    restore)
        do_restore "$@"
        ;;
    *)
        log_err "Unknown action '$ACTION' — use backup, list, or restore."
        exit 1
        ;;
esac