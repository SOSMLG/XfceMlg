#!/usr/bin/env bash
# DEBSWAY_DESC: fastfetch config + btop (catppuccin_mocha theme)
# DEBSWAY_DEFAULT: Y
#  19-fastfetch.sh — system info on terminal open
#  Writes one minimal, fancy fastfetch config locally (Darkmatter red
#  accent, custom anime ASCII art, essential modules only — no network
#  needed beyond the fastfetch package itself). Also offers btop
#  (system monitor) with the Catppuccin Mocha flavor — a dark palette
#  that fits the Darkmatter desktop.
#  Privilege: priv() (doas-first, sudo fallback) (fastfetch/btop installs)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root


log_head "1/3  Install fastfetch"
if is_installed fastfetch; then
    log_ok "fastfetch already installed."
else
    apt_update || log_warn "apt-get update failed (continuing with cached lists)."
    priv apt-get install -y fastfetch || { log_err "Failed to install fastfetch."; exit 1; }
    log_ok "fastfetch installed."
fi

log_head "2/3  Config (minimal, fancy — written locally, no downloads)"
if ask "Write the minimal fancy fastfetch config (Darkmatter palette, custom logo)?"; then
    FF_DIR="$HOME/.config/fastfetch"
    mkdir -p "$FF_DIR"
    FF_CONF="$FF_DIR/config.jsonc"
    [[ -f "$FF_CONF" ]] && cp "$FF_CONF" "${FF_CONF}.bak.$(date +%Y%m%d%H%M%S)"

    # Deploy the bundled ASCII art
    ASCII_SRC="$SCRIPT_DIR/../configs/fastfetch/ascii_art_anime.txt"
    if [[ -f "$ASCII_SRC" ]]; then
        cp "$ASCII_SRC" "$FF_DIR/ascii_art_anime.txt"
    fi

    cat > "$FF_CONF" << 'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "source": "~/.config/fastfetch/ascii_art_anime.txt",
        "type": "file",
        "padding": { "top": 1 }
    },
    "display": {
        "color": { "keys": "blue", "title": "blue" },
        "separator": "  "
    },
    "general": {
        "showElapsed": false,
        "statSeparatorType": "hidden"
    },
    "modules": [
        "title",
        "separator",
        "os",
        "kernel",
        "uptime",
        "shell",
        "display",
        "de",
        "terminal",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "separator",
        "colors"
    ]
}
EOF
    log_ok "Minimal fancy config written to $FF_CONF (try it: fastfetch)."
fi

log_head "3/3  btop (system monitor)"
if ask "Install btop with the Catppuccin Mocha theme (matches the dark desktop)?"; then
    install_pkgs "btop + fetcher" btop curl || true
    if ! is_installed btop; then
        log_warn "btop not installed — skipping theme (re-run this script later)."
    elif ! command -v curl &>/dev/null; then
        log_warn "curl missing — skipping theme fetch (re-run this script later)."
    else
        mkdir -p "$HOME/.config/btop/themes"
        if curl -fsSL "https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme" \
                -o "$HOME/.config/btop/themes/catppuccin_mocha.theme"; then
            log_ok "Fetched catppuccin_mocha into ~/.config/btop/themes/"
            BTOP_CONF="$HOME/.config/btop/btop.conf"
            BTOP_VERSION=$(btop --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            if [[ -f "$BTOP_CONF" ]]; then
                cp "$BTOP_CONF" "${BTOP_CONF}.bak.$(date +%Y%m%d%H%M%S)"
                grep -q '^color_theme' "$BTOP_CONF" \
                    && sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONF" \
                    || echo 'color_theme = "catppuccin_mocha"' >> "$BTOP_CONF"
            else
                mkdir -p "$HOME/.config/btop"
                echo 'color_theme = "catppuccin_mocha"' > "$BTOP_CONF"
            fi
            log_ok "btop.conf set to catppuccin_mocha."
            if [[ -n "$BTOP_VERSION" ]] && printf '%s\n' "1.3.1" "$BTOP_VERSION" | sort -C -V 2>/dev/null; then
                pkill -SIGUSR2 btop 2>/dev/null && log_info "Hot-reloaded the theme into your running btop."
            fi
        else
            log_warn "Couldn't fetch the Mocha theme — btop still installed, just unthemed. Re-run this script later."
        fi
    fi
fi

log_ok "fastfetch setup complete. Try it: fastfetch"
