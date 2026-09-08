#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  fastfetchConfig.sh — system info on terminal open
#  Pulls the curated fastfetch presets from your own butterscripts
#  repo (codeberg.org/justaguylinux/butterscripts), same source
#  your Butterbian-XFCE ISO's own hook uses — just targeting your
#  actual $HOME instead of /etc/skel, since this runs against an
#  existing user, not a new-account template. Also offers btop
#  (system monitor), themed with Catppuccin's own official colors —
#  same "terminal tells you about the system" family as fastfetch.
#  Privilege: sudo (fastfetch/btop package installs)
# ══════════════════════════════════════════════════════════════
set -euo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && err "Run this script as your normal user, not root."
command -v sudo &>/dev/null || err "sudo not found."

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo -e "\n${B}${W}══════ fastfetch ══════${Z}"

step "1/3  Install fastfetch"
if is_installed fastfetch; then
    ok "fastfetch already installed."
else
    sudo apt-get update -qq
    sudo apt-get install -y fastfetch || err "Failed to install fastfetch."
    ok "fastfetch installed."
fi

step "2/3  Config presets"
if ask "Pull your curated fastfetch presets (config/minimal/fancy/neon/debian-red/justaguy/server)?"; then
    FF_DIR="$HOME/.config/fastfetch"
    mkdir -p "$FF_DIR"
    BASE_URL="https://codeberg.org/justaguylinux/butterscripts/raw/branch/main/fastfetch"

    for f in config.jsonc minimal.jsonc fancy.jsonc neon.jsonc debian-red.jsonc justaguy.jsonc server.jsonc; do
        if wget -q "$BASE_URL/$f" -O "$FF_DIR/$f"; then
            info "  fetched $f"
        else
            warn "  failed to fetch $f (continuing)"
        fi
    done

    for img in debian_swirl.png justaguylinux.png; do
        wget -q "$BASE_URL/$img" -O "$FF_DIR/$img" || warn "  failed to fetch $img (continuing)"
    done

    # neon as the default, matching your own ISO's choice — switch any time
    # with: cp ~/.config/fastfetch/<preset>.jsonc ~/.config/fastfetch/config.jsonc
    if [[ -f "$FF_DIR/neon.jsonc" ]]; then
        cp "$FF_DIR/neon.jsonc" "$FF_DIR/config.jsonc"
        ok "Presets installed to $FF_DIR (neon set as default)"
    else
        warn "neon.jsonc didn't download — default config.jsonc from the loop above is used instead."
    fi
fi

ok "fastfetch setup complete. Try it: fastfetch"

step "3/3  btop (system monitor) — Catppuccin theming"
if ask "Install btop and theme it with Catppuccin (Mocha, matches the Red/Black GTK theme)?" "N"; then
    sudo apt-get install -y btop || err "btop failed to install."
    if is_installed btop; then
        BTOP_VERSION=$(btop --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        mkdir -p "$HOME/.config/btop/themes"
        BASE_URL="https://raw.githubusercontent.com/catppuccin/btop/main/themes"
        FETCHED=0
        for flavor in mocha macchiato frappe latte; do
            curl -fsSL "${BASE_URL}/catppuccin_${flavor}.theme" \
                -o "$HOME/.config/btop/themes/catppuccin_${flavor}.theme" \
                && FETCHED=$((FETCHED + 1)) \
                || warn "Couldn't fetch the ${flavor} flavor — skipping it."
        done

        if [[ $FETCHED -gt 0 ]]; then
            ok "Fetched $FETCHED/4 Catppuccin flavors into ~/.config/btop/themes/"
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
                ok "btop.conf set to catppuccin_mocha (switch flavors any time: Esc → Options → color_theme)."
            fi
            # SIGUSR2 hot-reload only exists from btop 1.3.1 onward — on
            # older builds it has no handler and the default POSIX action
            # is to terminate, which would kill a running btop instead of
            # re-theming it. Version-gate it rather than assume.
            if [[ -n "$BTOP_VERSION" ]] && printf '%s\n' "1.3.1" "$BTOP_VERSION" | sort -C -V 2>/dev/null; then
                pkill -SIGUSR2 btop 2>/dev/null && info "Hot-reloaded the theme into your running btop."
            fi
        else
            err "Couldn't fetch any Catppuccin theme files — check your network and rerun this step."
        fi
    fi
fi
