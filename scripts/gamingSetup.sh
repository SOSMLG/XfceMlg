#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  gamingSetup.sh — Steam, Heroic, Wine (optional)
#  Based on your own games.sh: Steam via Valve's official .deb
#  (no sources.list editing needed), Heroic via the latest
#  GitHub release .deb (not pinned), Vulkan/gamemode/mangohud.
#  Wine added here for parity with the KDE-side version of this
#  toolkit (your original games.sh didn't include it).
#  Privilege: sudo
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

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then ok "$label already installed."; return 0; fi
    info "$label: installing ${to_install[*]}"
    if sudo apt-get install -y "${to_install[@]}"; then
        return 0
    else
        warn "$label: some packages failed (continuing)."
        return 1
    fi
}

echo -e "\n${B}${W}══════ Gaming Setup ══════${Z}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

I386_DONE=0
ensure_i386() {
    [[ "$I386_DONE" -eq 1 ]] && return 0
    if dpkg --print-foreign-architectures | grep -qx i386; then
        ok "i386 multiarch already enabled."
    else
        info "Enabling i386 multiarch..."
        sudo dpkg --add-architecture i386
    fi
    sudo apt-get update -qq
    I386_DONE=1
}

step "1/4  Core gaming libraries"
if ask "Install core gaming libraries (Vulkan, GameMode, MangoHud)?" "N"; then
    ensure_i386
    install_pkgs "Gaming libraries" \
        libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        mesa-utils gamemode mangohud
fi

step "2/4  Steam"
if ask "Install Steam?" "N"; then
    if is_installed steam-launcher || is_installed steam; then
        ok "Steam already installed."
    else
        ensure_i386
        info "Downloading Steam's official installer package..."
        if curl -fsSL --progress-bar -o "$TMP_DIR/steam.deb" \
                "https://repo.steampowered.com/steam/archive/precise/steam_latest.deb"; then
            if sudo apt-get install -y "$TMP_DIR/steam.deb"; then
                ok "Steam installed. It will self-update on first launch."
            else
                err "Steam .deb install failed — try: sudo apt-get install steam"
            fi
        else
            warn "Direct download failed — trying apt..."
            if sudo apt-get install -y steam 2>/dev/null; then
                ok "Steam installed via apt"
            else
                warn "Steam unavailable — check that contrib/non-free are enabled in your sources."
            fi
        fi
    fi
fi

step "3/4  Heroic Games Launcher"
if ask "Install Heroic Games Launcher (Epic/GOG/Amazon)?" "N"; then
    if is_installed heroic; then
        ok "Heroic already installed."
    else
        info "Fetching latest Heroic release from GitHub..."
        HEROIC_URL=$(curl -fsSL \
            https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest \
            | grep '"browser_download_url"' | grep '\.deb"' | grep -iv 'arm\|aarch' \
            | cut -d'"' -f4 | head -1)

        if [[ -z "$HEROIC_URL" ]]; then
            warn "Could not fetch Heroic URL from GitHub API (rate-limited?). Skipping."
        else
            info "Downloading Heroic..."
            if curl -fsSL --progress-bar -L -o "$TMP_DIR/heroic.deb" "$HEROIC_URL"; then
                if sudo apt-get install -y "$TMP_DIR/heroic.deb"; then
                    ok "Heroic installed."
                else
                    warn "Heroic .deb install failed (dependency issue?). Trying dpkg + fix-broken..."
                    sudo dpkg -i "$TMP_DIR/heroic.deb" || true
                    if sudo apt-get install -f -y; then
                        ok "Heroic installed after dependency fix-up."
                    else
                        err "Heroic install failed."
                    fi
                fi
            else
                warn "Heroic download failed"
            fi
        fi
    fi
fi

step "4/4  Wine"
if ask "Install Wine (run Windows .exe apps directly)?" "N"; then
    if is_installed wine; then
        ok "Wine already installed."
    else
        ensure_i386
        install_pkgs "Wine" wine winetricks
        is_installed wine && ok "Wine installed. Run 'winecfg' once to set up your first Wine prefix."
    fi
fi

ok "Gaming setup complete."
echo -e "  ${C}•${Z} gamemode: prefix commands with ${W}gamemoderun${Z} for better performance"
echo -e "  ${C}•${Z} mangohud: prefix commands with ${W}mangohud${Z} to show the overlay"
