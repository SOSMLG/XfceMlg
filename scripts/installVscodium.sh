#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  installVscodium.sh — VSCodium (optional)
#  Telemetry-free VS Code build, installed via its official APT
#  repo so it updates normally afterward. Geany is this project's
#  default editor (usefulApps.sh) — this is here as an optional
#  extra for anyone who also wants VSCodium available.
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

echo -e "\n${B}${W}══════ VSCodium ══════${Z}"

if is_installed codium; then
    ok "VSCodium (codium) is already installed."
    exit 0
fi

step "1/3  Dependencies"
for dep in wget gpg; do
    if ! command -v "$dep" &>/dev/null; then
        info "Installing dependency: $dep"
        sudo apt-get update -qq
        sudo apt-get install -y "$dep" || { err "Failed to install $dep"; exit 1; }
    fi
done

step "2/3  APT repository"
KEYRING="/usr/share/keyrings/vscodium-archive-keyring.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/vscodium.list"

info "Adding VSCodium's GPG key..."
if wget -qO - "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg" \
        | gpg --dearmor | sudo tee "$KEYRING" > /dev/null; then
    ok "Key installed to $KEYRING"
else
    err "Failed to fetch/install the VSCodium GPG key."; exit 1
fi

info "Adding VSCodium APT repository..."
ARCH="$(dpkg --print-architecture)"
if echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://download.vscodium.com/debs vscodium main" \
        | sudo tee "$SOURCES_FILE" > /dev/null; then
    ok "Repository added at $SOURCES_FILE (scoped to arch=${ARCH})"
else
    err "Failed to write $SOURCES_FILE"; exit 1
fi

step "3/3  Install"
sudo apt-get update -qq || { err "apt-get update failed after adding the VSCodium repo."; exit 1; }
if sudo apt-get install -y codium; then
    ok "VSCodium installed. Launch it with 'codium'."
else
    err "Failed to install codium."; exit 1
fi
