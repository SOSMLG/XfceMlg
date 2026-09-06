#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  btopSetup.sh — btop (system monitor) themed to match the rest
#  of this setup, inspired by dougburks/ohmydebn's theme-carousel
#  approach but sourced from Catppuccin's own official repo
#  instead of reverse-engineering colors out of a template.
#
#  Installs all four official Catppuccin flavors so switching is
#  a one-line edit later, and defaults to Mocha (the dark flavor
#  that matches the Catppuccin Black/Red GTK theme installed
#  earlier in this toolkit).
#
#  Privilege: sudo (package install only; theme files + config
#  are $HOME-only)
# ══════════════════════════════════════════════════════════════
set -uo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; }
fatal() { err "$*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && fatal "Run this script as your normal user, not root."
command -v sudo &>/dev/null || fatal "sudo not found — this script needs it to install packages."

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo -e "\n${B}${W}══════ btop (system monitor) — Catppuccin theming ══════${Z}"

if ! ask "Install btop and theme it with Catppuccin (Mocha by default)?"; then
    warn "Skipped btop setup."
    exit 0
fi

# ══════════════════════════════════════════════════════════════
step "1/3  Install btop"
# ══════════════════════════════════════════════════════════════
info "Refreshing package lists..."
sudo apt-get update -qq
if ! sudo apt-get install -y btop; then
    err "btop failed to install."
    exit 1
fi
ok "btop installed."

BTOP_VERSION=$(btop --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
info "Detected btop $BTOP_VERSION."

# ══════════════════════════════════════════════════════════════
step "2/3  Fetch the official Catppuccin theme files"
# ══════════════════════════════════════════════════════════════
# Pulled directly from catppuccin/btop's own repo — not reverse-
# engineered from a template — so the colors are exactly what
# upstream ships and stay correct if Catppuccin ever tweaks them.
mkdir -p "$HOME/.config/btop/themes"
BASE_URL="https://raw.githubusercontent.com/catppuccin/btop/main/themes"
FLAVORS=(mocha macchiato frappe latte)
FETCHED=0
for flavor in "${FLAVORS[@]}"; do
    if curl -fsSL "${BASE_URL}/catppuccin_${flavor}.theme" \
        -o "$HOME/.config/btop/themes/catppuccin_${flavor}.theme"; then
        FETCHED=$((FETCHED + 1))
    else
        warn "Couldn't fetch the ${flavor} flavor (network issue?) — skipping it."
    fi
done

if [[ $FETCHED -eq 0 ]]; then
    err "Couldn't fetch any Catppuccin theme files — check your network and rerun this script."
    exit 1
fi
ok "Fetched $FETCHED/${#FLAVORS[@]} Catppuccin flavors into ~/.config/btop/themes/"

# ══════════════════════════════════════════════════════════════
step "3/3  Set Mocha as the active theme"
# ══════════════════════════════════════════════════════════════
BTOP_CONF="$HOME/.config/btop/btop.conf"
if [[ -f "$HOME/.config/btop/themes/catppuccin_mocha.theme" ]]; then
    if [[ -f "$BTOP_CONF" ]]; then
        cp "$BTOP_CONF" "${BTOP_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        if grep -q '^color_theme' "$BTOP_CONF"; then
            sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONF"
        else
            echo 'color_theme = "catppuccin_mocha"' >> "$BTOP_CONF"
        fi
    else
        mkdir -p "$HOME/.config/btop"
        echo 'color_theme = "catppuccin_mocha"' > "$BTOP_CONF"
    fi
    ok "btop.conf set to catppuccin_mocha."
else
    warn "Mocha theme file wasn't fetched — leaving btop.conf on its default theme."
fi

# Hot-reload a running btop if there is one. SIGUSR2 hot-reload
# was only added in btop 1.3.1 (per btop's own changelog) — on
# anything older it has no handler for that signal and the
# default POSIX action is to terminate the process, which would
# silently kill someone's running btop instead of re-theming it.
# Version-gating this the way ohmydebn does is what avoids that.
if [[ -n "$BTOP_VERSION" ]] && printf '%s\n' "1.3.1" "$BTOP_VERSION" | sort -C -V 2>/dev/null; then
    pkill -SIGUSR2 btop 2>/dev/null && info "Hot-reloaded the theme into your running btop." || true
else
    info "btop $BTOP_VERSION predates 1.3.1's hot-reload support — restart btop by hand to see the new theme (its window won't be closed for you)."
fi

echo
ok "Done. Run 'btop', press Esc → Options → color_theme to switch flavors (mocha/macchiato/frappe/latte) any time."
