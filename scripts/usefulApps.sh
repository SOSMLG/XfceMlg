#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  usefulApps.sh — daily-use essentials
#  Base tools, Python/data-science stack, Geany (this project's
#  editor of choice, replacing Mousepad), and VLC.
#  Privilege: sudo
# ══════════════════════════════════════════════════════════════
set -euo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && err "Run this script as your normal user, not root."

command -v sudo &>/dev/null || err "sudo not found — this script needs it to install packages."

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        ok "$label already installed."
        return 0
    fi
    info "$label: installing ${to_install[*]}"
    sudo apt-get install -y "${to_install[@]}" || warn "$label: some packages failed to install (continuing)."
}

echo -e "\n${B}${W}══════ Useful Apps ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

step "1/4  Base tools"
if ask "Install base tools (git, curl, wget, rsync, wine, xdg-user-dirs, zram-tools)?"; then
    install_pkgs "Base tools" \
        bash-completion ca-certificates curl git gnupg lsb-release \
        rsync wget wine xdg-user-dirs zram-tools
fi

step "2/4  Python & dev tools"
if ask "Install Python + data-science stack (numpy/pandas/scipy/matplotlib)?"; then
    install_pkgs "Python/dev tools" \
        build-essential python3 python3-dev python3-pip python3-venv \
        python3-numpy python3-pandas python3-scipy python3-matplotlib
fi

step "3/4  Geany (text editor)"
if ask "Install Geany + plugins?"; then
    install_pkgs "Geany" \
        geany geany-plugin-addons geany-plugin-git-changebar \
        geany-plugin-markdown geany-plugin-overview \
        geany-plugin-spellcheck geany-plugin-treebrowser geany-plugin-vimode
fi

step "4/4  VLC"
if ask "Install VLC (media player)?"; then
    install_pkgs "VLC" vlc

    # xfceDebloat.sh may have removed Parole/QuodLibet earlier in this
    # toolkit's flow. If so, without this, common video/audio MIME types
    # can be left pointing at a now-uninstalled app instead of falling
    # over to VLC automatically.
    if is_installed vlc && command -v xdg-mime &>/dev/null; then
        info "Setting VLC as the default player for common video/audio types..."
        if xdg-mime default vlc.desktop \
            video/mp4 video/x-matroska video/webm video/x-msvideo video/quicktime video/mpeg \
            audio/mpeg audio/mp4 audio/flac audio/x-wav audio/ogg 2>/dev/null; then
            ok "VLC set as default for common video/audio types."
        else
            warn "Could not set MIME defaults (non-fatal — set manually via right-click > Open With if needed)."
        fi
    fi
fi

ok "Useful apps step complete."
