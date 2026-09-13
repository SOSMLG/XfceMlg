#!/usr/bin/env bash
# DEBSWAY_DESC: (optional) Steam / Heroic / Wine
# DEBSWAY_DEFAULT: N
#  44-gaming.sh — Steam, Heroic, Wine (optional)
#  Based on your own games.sh: Steam via Valve's official .deb
#  (no sources.list editing needed), Heroic via the latest
#  GitHub release .deb (not pinned), Vulkan/gamemode/mangohud.
#  Wine added here for parity with the KDE-side version of this
#  toolkit (your original games.sh didn't include it).
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root








TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

I386_DONE=0
ensure_i386() {
    [[ "$I386_DONE" -eq 1 ]] && return 0
    if dpkg --print-foreign-architectures | grep -qx i386; then
        log_ok "i386 multiarch already enabled."
    else
        log_info "Enabling i386 multiarch..."
        priv dpkg --add-architecture i386
    fi
    apt_update || log_warn "apt-get update failed (continuing with cached lists)."
    I386_DONE=1
}

log_head "1/4  Core gaming libraries"
if ask "Install core gaming libraries (Vulkan, GameMode, MangoHud)?" "N"; then
    ensure_i386
    install_pkgs "Gaming libraries" \
        libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        mesa-utils gamemode mangohud
fi

log_head "2/4  Steam"
if ask "Install Steam?" "N"; then
    if is_installed steam-launcher || is_installed steam; then
        log_ok "Steam already installed."
    else
        ensure_i386
        log_info "Downloading Steam's official installer package..."
        if curl -fsSL --progress-bar -o "$TMP_DIR/steam.deb" \
                "https://repo.steampowered.com/steam/archive/precise/steam_latest.deb"; then
            if priv apt-get install -y "$TMP_DIR/steam.deb"; then
                log_ok "Steam installed. It will self-update on first launch."
            else
                log_err "Steam .deb install failed — try: doas apt-get install steam"
            fi
        else
            log_warn "Direct download failed — trying apt..."
            if priv apt-get install -y steam 2>/dev/null; then
                log_ok "Steam installed via apt"
            else
                log_warn "Steam unavailable — check that contrib/non-free are enabled in your sources."
            fi
        fi
    fi
fi

log_head "3/4  Heroic Games Launcher"
if ask "Install Heroic Games Launcher (Epic/GOG/Amazon)?" "N"; then
    if is_installed heroic; then
        log_ok "Heroic already installed."
    else
        log_info "Fetching latest Heroic release from GitHub..."
        HEROIC_URL=$(curl -fsSL \
            https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest \
            | grep '"browser_download_url"' | grep '\.deb"' | grep -iv 'arm\|aarch' \
            | cut -d'"' -f4 | head -1)

        if [[ -z "$HEROIC_URL" ]]; then
            log_warn "Could not fetch Heroic URL from GitHub API (rate-limited?). Skipping."
        else
            log_info "Downloading Heroic..."
            if curl -fsSL --progress-bar -L -o "$TMP_DIR/heroic.deb" "$HEROIC_URL"; then
                if priv apt-get install -y "$TMP_DIR/heroic.deb"; then
                    log_ok "Heroic installed."
                else
                    log_warn "Heroic .deb install failed (dependency issue?). Trying dpkg + fix-broken..."
                    priv dpkg -i "$TMP_DIR/heroic.deb" || true
                    if priv apt-get install -f -y; then
                        log_ok "Heroic installed after dependency fix-up."
                    else
                        log_err "Heroic install failed."
                    fi
                fi
            else
                log_warn "Heroic download failed"
            fi
        fi
    fi
fi

log_head "4/4  Wine"
if ask "Install Wine (run Windows .exe apps directly)?" "N"; then
    if is_installed wine; then
        log_ok "Wine already installed."
    else
        ensure_i386
        install_pkgs "Wine" wine winetricks
        is_installed wine && log_ok "Wine installed. Run 'winecfg' once to set up your first Wine prefix."
    fi
fi

log_ok "Gaming setup complete."
echo -e "  • gamemode: prefix commands with gamemoderun for better performance"
echo -e "  • mangohud: prefix commands with mangohud to show the overlay"
