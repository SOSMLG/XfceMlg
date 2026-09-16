#!/usr/bin/env bash
# DEBSWAY_DESC: Base tools, Python stack, Ristretto, Atril, Disks
# DEBSWAY_DEFAULT: Y
#  33-useful-apps.sh — daily-use essentials
#  Base tools, Python/data-science stack (VSCodium in 40-* is this
#  project's editor of choice, replacing Mousepad), VLC, plus the Mint-style
#  everyday apps (Ristretto/Atril/GNOME Disks) — same job Mint's
#  own xviewer/xreader/mintstick do, using packages Debian/Devuan
#  actually carry instead of Mint's Ubuntu-built .debs.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root







set_default() {
    local desktop_file="$1"; shift
    command -v xdg-mime &>/dev/null || { log_warn "xdg-mime not found — skipping default-app association."; return; }
    for mime in "$@"; do
        xdg-mime default "$desktop_file" "$mime" 2>/dev/null || true
    done
}

apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/6  Base tools"
if ask "Install base tools (git, curl, wget, rsync, xdg-user-dirs, zram-tools)?"; then
    install_pkgs "Base tools" \
        bash-completion ca-certificates curl galculator gnupg lsb-release \
        baobab rsync wget xdg-user-dirs zram-tools brightnessctl
fi

log_head "2/6  Python & dev tools"
if ask "Install Python + data-science stack (numpy/pandas/scipy/matplotlib)?"; then
    install_pkgs "Python/dev tools" \
        build-essential python3 python3-dev python3-pip python3-venv \
        python3-numpy python3-pandas python3-scipy python3-matplotlib
fi

log_head "3/6  VLC"
if ask "Install VLC (media player)?"; then
    install_pkgs "VLC" vlc

    # 20-xfce-debloat.sh may have removed Parole/QuodLibet earlier in this
    # toolkit's flow. If so, without this, common video/audio MIME types
    # can be left pointing at a now-uninstalled app instead of falling
    # over to VLC automatically.
    if is_installed vlc && command -v xdg-mime &>/dev/null; then
        log_info "Setting VLC as the default player for common video/audio types..."
        if xdg-mime default vlc.desktop \
            video/mp4 video/x-matroska video/webm video/x-msvideo video/quicktime video/mpeg \
            audio/mpeg audio/mp4 audio/flac audio/x-wav audio/ogg 2>/dev/null; then
            log_ok "VLC set as default for common video/audio types."
        else
            log_warn "Could not set MIME defaults (non-fatal — set manually via right-click > Open With if needed)."
        fi
    fi
fi

log_head "4/6  Image viewer (Ristretto — Mint-style everyday app)"
if ask "Install/confirm Ristretto and set it as the default image viewer?"; then
    if install_pkgs "Ristretto" ristretto; then
        set_default org.xfce.ristretto.desktop \
            image/jpeg image/png image/gif image/bmp image/webp image/tiff image/x-icon
        log_ok "Ristretto set as the default handler for common image types."
    fi
fi

log_head "5/6  PDF/document viewer (Atril)"
if ask "Install Atril (lightweight PDF viewer) and set it as the default?"; then
    if install_pkgs "Atril" atril; then
        set_default atril.desktop application/pdf
        log_ok "Atril set as the default handler for PDFs."
    fi
fi

log_head "6/6  USB/ISO writer (GNOME Disks)"
if ask "Install GNOME Disks (ISO/IMG-to-USB writer, right-click a drive → Restore Disk Image)?"; then
    install_pkgs "GNOME Disks" gnome-disk-utility
    log_info "Open 'Disks', select the target USB drive, then use its menu → 'Restore Disk Image...' —"
    log_info "the closest match to Mint's single-purpose USB Image Writer (mintstick)."
fi

log_ok "Useful apps step complete."
