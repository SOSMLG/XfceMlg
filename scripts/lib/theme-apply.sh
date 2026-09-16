#!/usr/bin/env bash
# =======================================================
# theme-apply.sh — the devuan-xfce-setup theme engine
# -------------------------------------------------------
# Palette-driven rendering of the per-app theme layer. A palette is a
# shell-sourced file (themes/<id>/palette.sh) defining hex colors plus
# the active GTK/xfwm4 theme names; templates live in themes/_base/tpl/
# with @TOKEN@ placeholders. Applying a palette re-renders:
#   alacritty.yml     -> ~/.config/alacritty/alacritty.yml
#   gtk-session.css   -> ~/.config/gtk-3.0/gtk.css      (panel accent)
#   fastfetch.jsonc   -> ~/.config/fastfetch/config.jsonc
# and sets the active GTK/xfwm4 themes via xfconf (live session only).
#
# Sourced by scripts/21-theme-tokyonight.sh (install-time apply) and by
# the deployed ~/.local/bin/xfce-theme-list / xfce-theme-set commands,
# and by blend/.../sync-overlay.sh (ISO seed). Self-contained: defines
# its own log helpers, no dependency on lib/common.sh.
#
# Env vars honored (all optional):
#   DEVX_CONFIG=<dir>   engine root  (default ~/.config/devuan-xfce-setup)
#   DEVX_THEMES=<dir>   palette sources (default $DEVX_CONFIG/themes)
#   DEVX_OUT=<base>     render target base (default ~/.config)
#   DEVX_SKIP_XFCONF=1  never touch a live session (ISO/overlay sync)
#   DEVX_THEME=<id>     default palette for theme_sync's first runs
# =======================================================

# Guard against being sourced twice in the same shell.
[ -n "${_DEVX_THEME_APPLY_LOADED:-}" ] && return 0
_DEVX_THEME_APPLY_LOADED=1

: "${XDG_CONFIG_HOME:=$HOME/.config}"
DEVX_CONFIG="${DEVX_CONFIG:-$XDG_CONFIG_HOME/devuan-xfce-setup}"
DEVX_THEMES="${DEVX_THEMES:-$DEVX_CONFIG/themes}"
DEVX_OUT="${DEVX_OUT:-$XDG_CONFIG_HOME}"
DEVX_HOME="${DEVX_HOME:-$HOME}"        # bin deploy home (ISO sync uses /home/devuan)
DEVX_TEMPLATES="$DEVX_THEMES/_base/tpl"
DEVX_CURRENT_FILE="$DEVX_CONFIG/current"
DEVX_SKIP_XFCONF="${DEVX_SKIP_XFCONF:-}"

# Own log helpers (17-20 chars for alignment with scripts/ output).
_t_log_ok()   { echo -e "\033[1;32m[theme]\033[0m $1"; }
_t_log_warn() { echo -e "\033[1;33m[theme]\033[0m $1"; }
_t_log_err()  { echo -e "\033[1;31m[theme]\033[0m $1"; }
_t_log_info() { echo -e "\033[1;36m[theme]\033[0m $1"; }

_t_has() { command -v "$1" >/dev/null 2>&1; }

# theme_list — print every installed palette id (one per line, sorted).
theme_list() {
    local d
    for d in "$DEVX_THEMES"/*/; do
        [ -d "$d" ] || continue
        local id
        id="$(basename "$d")"
        [ "$id" = "_base" ] && continue
        [ -f "$d/palette.sh" ] || continue
        printf '%s\n' "$id"
    done | sort
}

# theme_current — print the active palette id (or "none").
theme_current() {
    if [ -f "$DEVX_CURRENT_FILE" ]; then
        cat "$DEVX_CURRENT_FILE"
    else
        printf 'none\n'
    fi
}

# _t_render <template> <dest> — render @TOKEN@ placeholders from the
# currently-sourced palette. Values are lowercase hex / alnum / a single
# named color (FASTFETCH_COLOR), so plain sed substitution is safe.
_t_render() {
    local src="$1" dst="$2"
    [ -f "$src" ] || { _t_log_err "template missing: $src"; return 1; }
    mkdir -p "$(dirname "$dst")"
    [ -f "$dst" ] && cp "$dst" "${dst}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
    sed \
        -e "s/@ALACRITTY_BG@/${ALACRITTY_BG:-"/"}/g" \
        -e "s/@ALACRITTY_FG@/${ALACRITTY_FG:-"/"}/g" \
        -e "s/@ALACRITTY_BLACK@/${ALACRITTY_BLACK:-"/"}/g" \
        -e "s/@ALACRITTY_RED@/${ALACRITTY_RED:-"/"}/g" \
        -e "s/@ALACRITTY_GREEN@/${ALACRITTY_GREEN:-"/"}/g" \
        -e "s/@ALACRITTY_YELLOW@/${ALACRITTY_YELLOW:-"/"}/g" \
        -e "s/@ALACRITTY_BLUE@/${ALACRITTY_BLUE:-"/"}/g" \
        -e "s/@ALACRITTY_MAGENTA@/${ALACRITTY_MAGENTA:-"/"}/g" \
        -e "s/@ALACRITTY_CYAN@/${ALACRITTY_CYAN:-"/"}/g" \
        -e "s/@ALACRITTY_WHITE@/${ALACRITTY_WHITE:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_BLACK@/${ALACRITTY_BRIGHT_BLACK:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_RED@/${ALACRITTY_BRIGHT_RED:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_GREEN@/${ALACRITTY_BRIGHT_GREEN:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_YELLOW@/${ALACRITTY_BRIGHT_YELLOW:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_BLUE@/${ALACRITTY_BRIGHT_BLUE:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_MAGENTA@/${ALACRITTY_BRIGHT_MAGENTA:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_CYAN@/${ALACRITTY_BRIGHT_CYAN:-"/"}/g" \
        -e "s/@ALACRITTY_BRIGHT_WHITE@/${ALACRITTY_BRIGHT_WHITE:-"/"}/g" \
        -e "s/@ACCENT_HEX@/#${THEME_ACCENT:-}/g" \
        -e "s/@ACCENT_ALT_HEX@/#${THEME_ACCENT_ALT:-}/g" \
        -e "s/@FASTFETCH_COLOR@/${FASTFETCH_COLOR:-}/g" \
        "$src" > "$dst"
}

# theme_sync <src_themes_dir> — copy the bundled palette library into
# $DEVX_CONFIG/themes (additive; never removes user-added palettes).
theme_sync() {
    local src="${1:-}"
    [ -z "$src" ] && { _t_log_err "theme_sync: missing source dir."; return 1; }
    [ -d "$src" ] || { _t_log_err "theme_sync: no theme library at $src."; return 1; }
    mkdir -p "$DEVX_CONFIG"
    if [ -d "$DEVX_THEMES" ]; then
        # Refresh _base templates + ship any new palettes; leave user
        # palettes (added under ~/.config) untouched.
        cp -rn "$src"/. "$DEVX_THEMES/" 2>/dev/null  # -n: never overwrite user edits
        # Templates, on the other hand, always track the repo.
        mkdir -p "$DEVX_THEMES/_base"
        cp -rf "$src/_base/." "$DEVX_THEMES/_base/" 2>/dev/null
    else
        cp -r "$src" "$DEVX_CONFIG/themes"
    fi
    _t_log_ok "Palette library synced to $DEVX_THEMES"
}

# theme_install_bin <src_bin_dir> — deploy the xfce-theme-{list,set}
# commands to $HOME/.local/bin (idempotent, backs up any existing copy).
theme_install_bin() {
    local src="${1:-}"
    [ -z "$src" ] && { _t_log_err "theme_install_bin: missing source dir."; return 1; }
    local local_bin="${DEVX_HOME}/.local/bin"
    mkdir -p "$local_bin"
    local f dest
    for f in xfce-theme-list xfce-theme-set; do
        dest="$local_bin/$f"
        if [ -f "$src/$f" ]; then
            [ -f "$dest" ] && cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
            cp "$src/$f" "$dest"
            chmod +x "$dest"
        fi
    done
    _t_log_ok "Theme commands deployed to $local_bin (xfce-theme-list / xfce-theme-set)"
}

# theme_seed <repo_root> [palette] — one-call setup: install the engine
# lib + palette library + bin commands, then apply the given palette.
# Used by scripts/21-theme-tokyonight.sh (real HOME) and by the ISO blend
# sync-overlay.sh with DEVX_OUT pointed at the overlay user's home.
theme_seed() {
    local repo="${1:-}"
    local fix="${2:-${DEVX_THEME:-tokyonight}}"
    [ -d "$repo" ] || { _t_log_err "theme_seed: no repo at $repo."; return 1; }
    mkdir -p "$DEVX_CONFIG/lib"
    cp -f "$repo/scripts/lib/theme-apply.sh" "$DEVX_CONFIG/lib/theme-apply.sh"
    theme_sync "$repo/themes"
    theme_install_bin "$repo/configs/bin"
    theme_set "$fix"
}

# theme_set <id> — render the active palette across the app layer.
theme_set() {
    local id="${1:-}"
    [ -z "$id" ] && { _t_log_err "theme_set: need a palette id (see xfce-theme-list)."; return 2; }
    if [ ! -f "$DEVX_THEMES/$id/palette.sh" ]; then
        _t_log_err "Unknown palette: $id"
        _t_log_err "Installed palettes: $(theme_list | tr '\n' ' ')"
        return 2
    fi

    # shellcheck source=/dev/null
    source "$DEVX_THEMES/$id/palette.sh"

    _t_log_info "Applying palette: ${THEME_NAME:-$id}"

    _t_render "$DEVX_TEMPLATES/alacritty.yml" "$DEVX_OUT/alacritty/alacritty.yml" \
        && _t_log_ok "alacritty.yml rendered"
    _t_render "$DEVX_TEMPLATES/gtk-session.css" "$DEVX_OUT/gtk-3.0/gtk.css" \
        && _t_log_ok "gtk.css (panel accent) rendered"
    _t_render "$DEVX_TEMPLATES/fastfetch.jsonc" "$DEVX_OUT/fastfetch/config.jsonc" \
        && _t_log_ok "fastfetch config rendered"

    mkdir -p "$(dirname "$DEVX_CURRENT_FILE")"
    printf '%s\n' "$id" > "$DEVX_CURRENT_FILE"

    # picker.colors — key=value file for Python menu/update-gui widgets
    # (bg0/bg1/bg3/fg0, #-prefixed with the F2 alpha suffix on bg0/bg3,
    # matching the devuan-cinnamon-picker format).
    cat > "$DEVX_CONFIG/picker.colors" << PICKER
bg0=#${THEME_BG}F2
bg1=#${THEME_BG_ALT}
bg3=#${THEME_ACCENT}F2
fg0=#${THEME_FG}
PICKER

    if [ -n "$DEVX_SKIP_XFCONF" ] || [ -z "${DISPLAY:-}" ] || ! _t_has xfconf-query; then
        _t_log_warn "No live session — skipped setting active GTK/xfwm4 themes (applies at login)."
        return 0
    fi

    if [ -n "${GTK_THEME_NAME:-}" ]; then
        xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_THEME_NAME" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
    fi
    if [ -n "${XFWM_THEME_NAME:-}" ]; then
        xfconf-query -c xfwm4 -p /general/theme -s "$XFWM_THEME_NAME" 2>/dev/null || true
    fi
    if _t_has xfce4-panel; then
        xfce4-panel -r 2>/dev/null || true
    fi
    _t_log_ok "Live session updated: GTK theme ${GTK_THEME_NAME:-unchanged}, xfwm4 ${XFWM_THEME_NAME:-unchanged}, panel is refreshing."
    return 0
}