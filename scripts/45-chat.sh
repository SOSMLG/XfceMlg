#!/usr/bin/env bash
# DEBSWAY_DESC: (optional) Vesktop / Telegram
# DEBSWAY_DEFAULT: Y
#  45-chat.sh — Vesktop (Discord client) / Telegram
#  Vesktop: latest GitHub release .deb (not pinned). Telegram:
#  official tar.xz extracted to ~/.local/opt/Telegram — entirely
#  user-space, no privileges needed for that half at all.
#  Privilege: priv() (doas-first, sudo fallback) (only for Vesktop's apt install)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root







install_vesktop() {
    if is_installed vesktop; then log_ok "Vesktop already installed."; return 0; fi
    log_info "Looking up the latest Vesktop release..."
    local api_json deb_url tmp_deb
    api_json=$(curl -fsSL "https://api.github.com/repos/Vencord/Vesktop/releases/latest" 2>/dev/null)
    if [[ -z "$api_json" ]]; then log_err "Could not reach GitHub API."; return 1; fi

    deb_url=$(echo "$api_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
candidates = [a['browser_download_url'] for a in assets if a['name'].lower().endswith('.deb')]
amd64 = [u for u in candidates if 'amd64' in u.lower() or 'x86_64' in u.lower()]
print((amd64 or candidates or [''])[0])
" 2>/dev/null)

    if [[ -z "$deb_url" ]]; then log_err "Could not find a .deb asset in the latest Vesktop release."; return 1; fi

    log_info "Downloading: $deb_url"
    tmp_deb="$(mktemp --suffix=.deb)"
    curl -fL -o "$tmp_deb" "$deb_url" || { log_err "Download failed."; rm -f "$tmp_deb"; return 1; }

    log_info "Installing Vesktop..."
    if priv apt-get install -y "$tmp_deb"; then
        log_ok "Vesktop installed."
    else
        log_warn "Vesktop install failed (dependency issue?). Trying dpkg + fix-broken..."
        priv dpkg -i "$tmp_deb" || true
        if priv apt-get install -f -y; then
            log_ok "Vesktop installed after dependency fix-up."
        else
            rm -f "$tmp_deb"
            return 1
        fi
    fi
    rm -f "$tmp_deb"
}

install_telegram() {
    if [[ -x "$HOME/.local/opt/Telegram/Telegram" ]]; then
        log_ok "Telegram already installed at $HOME/.local/opt/Telegram."
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    log_info "Downloading Telegram Desktop..."
    wget -q -O "$tmp_dir/telegram.tar.xz" "https://telegram.org/dl/desktop/linux" \
        || { log_err "Failed to download Telegram."; return 1; }

    mkdir -p "$HOME/.local/opt"
    [[ -d "$HOME/.local/opt/Telegram" ]] && rm -rf "$HOME/.local/opt/Telegram"

    log_info "Extracting Telegram..."
    tar -xf "$tmp_dir/telegram.tar.xz" -C "$HOME/.local/opt" || { log_err "Failed to extract Telegram."; return 1; }
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

    log_ok "Telegram installed at $HOME/.local/opt/Telegram (launcher: telegram)."
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
        log_warn "$HOME/.local/bin is not in your PATH. Add: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

log_head "1/2  Vesktop"
ask "Install Vesktop (Discord client)?" && install_vesktop

log_head "2/2  Telegram"
ask "Install Telegram Desktop?" && install_telegram

log_ok "Vesktop/Telegram log_head complete."
