#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  xfceDebloat.sh — trim the default task-xfce-desktop app set
#  XFCE's default install is already lean compared to KDE's
#  kde-standard (no bundled games/PIM/education suite), so this
#  is mostly about swapping defaults for the tools this project
#  actually installs elsewhere (Geany instead of Mousepad, VLC
#  instead of Parole), not a big bloat purge.
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

purge_if_installed() {
    local label="$1"; shift
    local to_purge=()
    for pkg in "$@"; do
        is_installed "$pkg" && to_purge+=("$pkg")
    done
    if [[ ${#to_purge[@]} -eq 0 ]]; then
        info "$label: nothing installed, skipping."
        return 0
    fi
    info "$label: purging ${to_purge[*]}"
    sudo apt-get purge -y "${to_purge[@]}" || warn "$label: some packages failed to purge (continuing)."
}

echo -e "\n${B}${W}══════ XFCE Debloat ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

step "1/3  Mousepad → replaced by Geany"
if ask "Remove Mousepad (Geany is installed instead by usefulApps.sh)?"; then
    purge_if_installed "Mousepad" mousepad
fi

step "2/3  Parole/QuodLibet → replaced by VLC"
if ask "Remove Parole and QuodLibet (VLC is installed instead by usefulApps.sh)?"; then
    purge_if_installed "Parole/QuodLibet" parole quodlibet
fi

step "3/3  Unused optical-disc tooling"
if ask "Remove Xfburn (CD/DVD burner — skip if you actually use an optical drive)?" "N"; then
    purge_if_installed "Xfburn" xfburn
fi

info "Cleaning up orphaned dependencies..."
sudo apt-get autoremove --purge -y || warn "autoremove reported issues (non-fatal)."
sudo apt-get clean || true

ok "XFCE debloat complete."
