#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  fastfetchConfig.sh — system info on terminal open
#  Pulls the curated fastfetch presets from your own butterscripts
#  repo (codeberg.org/justaguylinux/butterscripts), same source
#  your Butterbian-XFCE ISO's own hook uses — just targeting your
#  actual $HOME instead of /etc/skel, since this runs against an
#  existing user, not a new-account template.
#  Privilege: sudo (only to install the fastfetch package itself)
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

step "1/2  Install fastfetch"
if is_installed fastfetch; then
    ok "fastfetch already installed."
else
    sudo apt-get update -qq
    sudo apt-get install -y fastfetch || err "Failed to install fastfetch."
    ok "fastfetch installed."
fi

step "2/2  Config presets"
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
