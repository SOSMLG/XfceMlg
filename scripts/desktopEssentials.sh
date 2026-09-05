#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  desktopEssentials.sh — completeness pass
#  XFCE's own task install already ships Synaptic and
#  system-config-printer as recommends, so this focuses on what
#  it doesn't: Flatpak/Flathub, GParted (the GTK/XFCE-native
#  partition tool, same role as KDE's Partition Manager), and
#  GUFW (the GTK firewall front-end — same role as KDE's
#  plasma-firewall, and literally what Linux Mint ships).
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

start_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now "$svc" &>/dev/null || true
    else
        sudo service "$svc" start &>/dev/null || true
    fi
}

REAL_USER="${SUDO_USER:-$USER}"

echo -e "\n${B}${W}══════ Desktop Essentials ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

step "1/4  Flatpak + Flathub"
if ask "Set up Flatpak + Flathub?"; then
    install_pkgs "Flatpak" flatpak gnome-software-plugin-flatpak

    if command -v flatpak &>/dev/null; then
        if sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            ok "Flathub remote added system-wide."
        else
            warn "Could not add the Flathub remote (may already exist)."
        fi
    fi
    warn "This installs the Flatpak runtime + Flathub remote. XFCE has no bundled Flatpak"
    warn "GUI store — use 'flatpak install flathub <app>' from a terminal, or install"
    warn "gnome-software separately if you want a graphical store."
fi

step "2/4  Printing"
if ask "Ensure printing support is installed (CUPS + drivers + network discovery)?"; then
    install_pkgs "Printing" cups cups-browsed printer-driver-all system-config-printer

    if is_installed cups; then
        start_service cups
        ok "CUPS started."
    fi

    if getent group lpadmin &>/dev/null; then
        if id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
            ok "$REAL_USER already in the lpadmin group."
        elif sudo usermod -aG lpadmin "$REAL_USER"; then
            ok "Added $REAL_USER to lpadmin (manage printers without a password prompt each time)."
            warn "Log out and back in for this to take effect."
        fi
    fi
fi

step "3/4  GParted (partition tool)"
if ask "Install GParted?"; then
    install_pkgs "GParted" gparted
fi

step "4/4  GUFW (firewall panel — installed only, NOT enabled)"
if ask "Install GUFW (GTK firewall front-end, not enabled by default)?"; then
    install_pkgs "Firewall" gufw ufw
    warn "Installed only — ufw is NOT enabled. Turning on default-deny-incoming automatically"
    warn "could silently break something you rely on (SSH into this machine, local file"
    warn "sharing). Open GUFW yourself and enable it once you've confirmed it's safe to."
fi

ok "Desktop essentials step complete."
