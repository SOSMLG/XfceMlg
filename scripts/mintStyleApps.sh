#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  mintStyleApps.sh — the everyday conveniences Mint ships out of
#  the box, using packages that actually exist in Debian/Devuan's
#  own repos.
#
#  Linux Mint's own equivalents for these jobs (xviewer, xreader,
#  mintstick) are XApps distributed through Mint's own APT repo,
#  which is built against Ubuntu package versions — installing
#  those .debs on a Devuan/Debian box risks dependency conflicts,
#  and building them from source pulls in a heavy meson/gtk-doc/
#  libwebkit2gtk toolchain for what's meant to be a lean apt-only
#  toolkit. So: same job, packages Debian/Devuan actually carry.
#
#    - Ristretto     → image viewer (XFCE's own; installed here to
#                       guarantee it's present, then set as the
#                       default handler for common image types)
#    - Atril         → lightweight PDF/document viewer (MATE's
#                       evince fork — same job, far fewer GNOME
#                       dependencies than pulling in evince itself)
#    - GNOME Disks   → "Restore Disk Image..." on any drive is the
#                       direct equivalent of Mint's USB Image
#                       Writer (mintstick) — write an ISO/IMG to a
#                       USB stick from a GUI, no dd incantation
#
#  Privilege: sudo (package installs only)
# ══════════════════════════════════════════════════════════════
set -uo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; }
fatal() { err "$*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && fatal "Run this script as your normal user, not root."
command -v sudo &>/dev/null || fatal "sudo not found — this script needs it to install packages."

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

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
    if sudo apt-get install -y "${to_install[@]}"; then
        ok "$label installed."
        return 0
    else
        warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

set_default() {
    local desktop_file="$1"; shift
    command -v xdg-mime &>/dev/null || { warn "xdg-mime not found — skipping default-app association."; return; }
    for mime in "$@"; do
        xdg-mime default "$desktop_file" "$mime" 2>/dev/null || true
    done
}

echo -e "\n${B}${W}══════ Mint-style everyday apps (Debian-packaged) ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

# ══════════════════════════════════════════════════════════════
step "1/3  Image viewer (Ristretto)"
# ══════════════════════════════════════════════════════════════
if ask "Install/confirm Ristretto and set it as the default image viewer?"; then
    if install_pkgs "Ristretto" ristretto; then
        set_default org.xfce.ristretto.desktop \
            image/jpeg image/png image/gif image/bmp image/webp image/tiff image/x-icon
        ok "Ristretto set as the default handler for common image types."
    fi
else
    warn "Skipped."
fi

# ══════════════════════════════════════════════════════════════
step "2/3  PDF/document viewer (Atril)"
# ══════════════════════════════════════════════════════════════
if ask "Install Atril (lightweight PDF viewer) and set it as the default?"; then
    if install_pkgs "Atril" atril; then
        set_default atril.desktop application/pdf
        ok "Atril set as the default handler for PDFs."
    fi
else
    warn "Skipped."
fi

# ══════════════════════════════════════════════════════════════
step "3/3  USB/ISO writer (GNOME Disks)"
# ══════════════════════════════════════════════════════════════
if ask "Install GNOME Disks (ISO/IMG-to-USB writer, right-click a drive → Restore Disk Image)?"; then
    install_pkgs "GNOME Disks" gnome-disk-utility
    info "A dedicated 'Disk Image Writer' launcher is installed alongside the full Disks app —"
    info "that's the closest match to Mint's single-purpose USB Image Writer (mintstick)."
    info "Full app usage: open 'Disks', select the target USB drive, then use its menu → 'Restore Disk Image...'"
else
    warn "Skipped."
fi

echo
ok "Mint-style app setup done — all three came from Debian/Devuan's own repos, nothing built from source."
