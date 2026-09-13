#!/usr/bin/env bash
# DEBSWAY_DESC: fastfetch presets + optional Catppuccin btop
# DEBSWAY_DEFAULT: Y
#  19-fastfetch.sh — system info on terminal open
#  Pulls the curated fastfetch presets from your own butterscripts
#  repo (codeberg.org/justaguylinux/butterscripts), same source
#  your Butterbian-XFCE ISO's own hook uses — just targeting your
#  actual $HOME instead of /etc/skel, since this runs against an
#  existing user, not a new-account template. Also offers btop
#  (system monitor), themed with Catppuccin's own official colors —
#  same "terminal tells you about the system" family as fastfetch.
#  Privilege: priv() (doas-first, sudo fallback) (fastfetch/btop package installs)
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

log_head "2/3  Config presets"
if ask "Pull your curated fastfetch presets (config/minimal/fancy/neon/debian-red/justaguy/server)?"; then
    FF_DIR="$HOME/.config/fastfetch"
    mkdir -p "$FF_DIR"
    BASE_URL="https://codeberg.org/justaguylinux/butterscripts/raw/branch/main/fastfetch"

    for f in config.jsonc minimal.jsonc fancy.jsonc neon.jsonc debian-red.jsonc justaguy.jsonc server.jsonc; do
        if wget -q "$BASE_URL/$f" -O "$FF_DIR/$f"; then
            log_info "  fetched $f"
        else
            log_warn "  failed to fetch $f (continuing)"
        fi
    done

    for img in debian_swirl.png justaguylinux.png; do
        wget -q "$BASE_URL/$img" -O "$FF_DIR/$img" || log_warn "  failed to fetch $img (continuing)"
    done

    # neon as the default, matching your own ISO's choice — switch any time
    # with: cp ~/.config/fastfetch/<preset>.jsonc ~/.config/fastfetch/config.jsonc
    if [[ -f "$FF_DIR/neon.jsonc" ]]; then
        cp "$FF_DIR/neon.jsonc" "$FF_DIR/config.jsonc"
        log_ok "Presets installed to $FF_DIR (neon set as default)"
    else
        log_warn "neon.jsonc didn't download — default config.jsonc from the loop above is used instead."
    fi
fi

log_ok "fastfetch setup complete. Try it: fastfetch"

log_head "3/3  btop (system monitor) — Catppuccin theming"
if ask "Theme btop with Catppuccin (Mocha, matches the Red/Black GTK theme)?"; then
    priv apt-get install -y btop || { log_err "btop failed to install."; exit 1; }
    if is_installed btop; then
        BTOP_VERSION=$(btop --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        mkdir -p "$HOME/.config/btop/themes"
        BASE_URL="https://raw.githubusercontent.com/catppuccin/btop/main/themes"
        FETCHED=0
        for flavor in mocha macchiato frappe latte; do
            curl -fsSL "${BASE_URL}/catppuccin_${flavor}.theme" \
                -o "$HOME/.config/btop/themes/catppuccin_${flavor}.theme" \
                && FETCHED=$((FETCHED + 1)) \
                || log_warn "Couldn't fetch the ${flavor} flavor — skipping it."
        done

        if [[ $FETCHED -gt 0 ]]; then
            log_ok "Fetched $FETCHED/4 Catppuccin flavors into ~/.config/btop/themes/"
            BTOP_CONF="$HOME/.config/btop/btop.conf"
            if [[ -f "$HOME/.config/btop/themes/catppuccin_mocha.theme" ]]; then
                if [[ -f "$BTOP_CONF" ]]; then
                    cp "$BTOP_CONF" "${BTOP_CONF}.bak.$(date +%Y%m%d%H%M%S)"
                    grep -q '^color_theme' "$BTOP_CONF" \
                        && sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONF" \
                        || echo 'color_theme = "catppuccin_mocha"' >> "$BTOP_CONF"
                else
                    mkdir -p "$HOME/.config/btop"
                    echo 'color_theme = "catppuccin_mocha"' > "$BTOP_CONF"
                fi
                log_ok "btop.conf set to catppuccin_mocha (switch flavors any time: Esc → Options → color_theme)."
            fi
            # SIGUSR2 hot-reload only exists from btop 1.3.1 onward — on
            # older builds it has no handler and the default POSIX action
            # is to terminate, which would kill a running btop instead of
            # re-theming it. Version-gate it rather than assume.
            if [[ -n "$BTOP_VERSION" ]] && printf '%s\n' "1.3.1" "$BTOP_VERSION" | sort -C -V 2>/dev/null; then
                pkill -SIGUSR2 btop 2>/dev/null && log_info "Hot-reloaded the theme into your running btop."
            fi
        else
            log_err "Couldn't fetch any Catppuccin theme files — check your network and rerun this log_head."; exit 1
        fi
    fi
fi
