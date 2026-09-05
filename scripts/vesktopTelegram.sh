#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  vesktopTelegram.sh — Vesktop (Discord client) / Telegram
#  Vesktop: latest GitHub release .deb (not pinned). Telegram:
#  official tar.xz extracted to ~/.local/opt/Telegram — entirely
#  user-space, no privileges needed for that half at all.
#  Privilege: sudo (only for Vesktop's apt install)
# ══════════════════════════════════════════════════════════════
set -uo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && { err "Run this script as your normal user, not root."; exit 1; }

command -v sudo &>/dev/null || { err "sudo not found — this script needs it to install packages."; exit 1; }

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo -e "\n${B}${W}══════ Vesktop & Telegram ══════${Z}"

install_vesktop() {
    if is_installed vesktop; then ok "Vesktop already installed."; return 0; fi
    info "Looking up the latest Vesktop release..."
    local api_json deb_url tmp_deb
    api_json=$(curl -fsSL "https://api.github.com/repos/Vencord/Vesktop/releases/latest" 2>/dev/null)
    if [[ -z "$api_json" ]]; then err "Could not reach GitHub API."; return 1; fi

    deb_url=$(echo "$api_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
candidates = [a['browser_download_url'] for a in assets if a['name'].lower().endswith('.deb')]
amd64 = [u for u in candidates if 'amd64' in u.lower() or 'x86_64' in u.lower()]
print((amd64 or candidates or [''])[0])
" 2>/dev/null)

    if [[ -z "$deb_url" ]]; then err "Could not find a .deb asset in the latest Vesktop release."; return 1; fi

    info "Downloading: $deb_url"
    tmp_deb="$(mktemp --suffix=.deb)"
    curl -fL -o "$tmp_deb" "$deb_url" || { err "Download failed."; rm -f "$tmp_deb"; return 1; }

    info "Installing Vesktop..."
    if sudo apt-get install -y "$tmp_deb"; then
        ok "Vesktop installed."
    else
        warn "Vesktop install failed (dependency issue?). Trying dpkg + fix-broken..."
        sudo dpkg -i "$tmp_deb" || true
        if sudo apt-get install -f -y; then
            ok "Vesktop installed after dependency fix-up."
        else
            rm -f "$tmp_deb"
            return 1
        fi
    fi
    rm -f "$tmp_deb"
}

install_telegram() {
    if [[ -x "$HOME/.local/opt/Telegram/Telegram" ]]; then
        ok "Telegram already installed at $HOME/.local/opt/Telegram."
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    info "Downloading Telegram Desktop..."
    wget -q -O "$tmp_dir/telegram.tar.xz" "https://telegram.org/dl/desktop/linux" \
        || { err "Failed to download Telegram."; return 1; }

    mkdir -p "$HOME/.local/opt"
    [[ -d "$HOME/.local/opt/Telegram" ]] && rm -rf "$HOME/.local/opt/Telegram"

    info "Extracting Telegram..."
    tar -xf "$tmp_dir/telegram.tar.xz" -C "$HOME/.local/opt" || { err "Failed to extract Telegram."; return 1; }
    chmod +x "$HOME/.local/opt/Telegram/Telegram"

    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
    ln -sf "$HOME/.local/opt/Telegram/Telegram" "$HOME/.local/bin/telegram"

    cat > "$HOME/.local/share/applications/telegram.desktop" << EOF
[Desktop Entry]
Name=Telegram
Comment=Fast and secure messaging app
Exec=$HOME/.local/bin/telegram
Icon=telegram
Type=Application
Categories=Network;InstantMessaging;
Terminal=false
EOF

    ok "Telegram installed at $HOME/.local/opt/Telegram (launcher: telegram)."
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
        warn "$HOME/.local/bin is not in your PATH. Add: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

step "1/2  Vesktop"
ask "Install Vesktop (Discord client)?" && install_vesktop

step "2/2  Telegram"
ask "Install Telegram Desktop?" && install_telegram

ok "Vesktop/Telegram step complete."
