#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  timeshiftSetup.sh — system snapshot/restore
#  Mint's signature safety net. Depends on plain cron, not
#  systemd, so it works fine on Devuan's default init.
#  Deliberately does NOT auto-configure a snapshot device or
#  schedule — that's a one-time choice with real disk-space
#  implications, worth doing deliberately via the setup wizard.
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
    sudo apt-get install -y "${to_install[@]}"
}

echo -e "\n${B}${W}══════ Timeshift ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

# cron is normally already present, but this is defensive — Timeshift
# hard-depends on it, not on systemd.
install_pkgs "cron" cron
install_pkgs "Timeshift" timeshift

if is_installed timeshift; then
    ok "Timeshift installed."
    warn "One-time setup needed: run 'sudo timeshift-launcher' (or find Timeshift in the"
    warn "app menu) to choose rsync vs BTRFS mode, where snapshots are stored, and a"
    warn "schedule. That choice is left to you rather than guessed automatically."
else
    err "Timeshift installation failed."
fi
