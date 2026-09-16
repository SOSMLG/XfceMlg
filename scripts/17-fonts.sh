#!/usr/bin/env bash
# DEBSWAY_DESC: Noto, Font Awesome, JetBrainsMono Nerd Font
# DEBSWAY_DEFAULT: Y
#  17-fonts.sh — Devuan/Debian font setup
#  Installs: Noto (Latin + Arabic + Emoji), Font Awesome,
#            JetBrainsMono Nerd Font (latest GitHub release)
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root





WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log_head "1/4  APT packages"
log_info "Updating package lists..."
apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_info "Installing Noto + Font Awesome via apt..."
priv apt-get install -y \
    curl \
    fonts-font-awesome \
    fonts-noto-core \
    fonts-noto-unhinted \
    fonts-noto-color-emoji \
    fonts-noto-mono \
    || { log_err "APT install failed"; exit 1; }
log_ok "APT fonts installed"

log_head "2/4  JetBrainsMono Nerd Font"
NERD_FONT_DIR="${HOME}/.local/share/fonts/NerdFonts"
mkdir -p "$NERD_FONT_DIR"

if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    log_warn "JetBrainsMono Nerd Font already installed — skipping download"
else
    log_info "Fetching latest release URL from GitHub..."
    DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
        | grep -oP '"browser_download_url": "\K[^"]+' \
        | grep -i "JetBrainsMono.*tar\.xz" \
        | head -1)

    if [[ -z "$DOWNLOAD_URL" ]]; then
        log_warn "GitHub API failed, using fallback URL..."
        # Pinned Nerd Fonts release (Butterbian-verified); override with NERD_FONT_TAG=x.y.z
        NERD_FONT_TAG="${NERD_FONT_TAG:-3.4.0}"
        DOWNLOAD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONT_TAG}/JetBrainsMono.tar.xz"
    fi

    FONT_ARCHIVE="${WORK_DIR}/JetBrainsMono.tar.xz"
    log_info "Downloading JetBrainsMono Nerd Font..."
    curl -fsSL --progress-bar -L -o "$FONT_ARCHIVE" "$DOWNLOAD_URL" || { log_err "Download failed: ${DOWNLOAD_URL}"; exit 1; }

    log_info "Extracting fonts..."
    if ! tar -xf "$FONT_ARCHIVE" -C "$NERD_FONT_DIR" --wildcards '*.ttf' 2>/dev/null; then
        log_warn "Falling back to full extraction..."
        tar -xf "$FONT_ARCHIVE" -C "$NERD_FONT_DIR" || { log_err "Failed to extract font archive"; exit 1; }
    fi
    log_ok "JetBrainsMono Nerd Font installed to ${NERD_FONT_DIR}"
fi

log_head "3/4  Fontconfig"
FONTCONF_DIR="${HOME}/.config/fontconfig"
FONTCONF="${FONTCONF_DIR}/fonts.conf"
mkdir -p "$FONTCONF_DIR"

log_info "Writing ${FONTCONF}..."
cat > "$FONTCONF" << 'EOF'
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>

  <!-- Monospace: Prefer JetBrainsMono Nerd Font, fallback to Noto Mono -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font Mono</family>
      <family>Noto Sans Mono</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>

  <!-- Sans-serif: Noto Sans + Arabic -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Sans Arabic</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>

  <!-- Serif: Noto Serif -->
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Serif Arabic</family>
    </prefer>
  </alias>

  <!-- Emoji: Always use color emoji -->
  <match target="pattern">
    <test name="family"><string>emoji</string></test>
    <edit name="family" mode="assign" binding="same">
      <string>Noto Color Emoji</string>
    </edit>
  </match>

  <!-- Rendering: Subpixel hinting for LCD screens -->
  <match target="font">
    <edit name="antialias"  mode="assign"><bool>true</bool></edit>
    <edit name="hinting"    mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle"  mode="assign"><const>hintslight</const></edit>
    <edit name="rgba"       mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter"  mode="assign"><const>lcddefault</const></edit>
  </match>

</fontconfig>
EOF
log_ok "fonts.conf written"

log_head "4/4  Rebuild font cache"
log_info "Rebuilding font cache..."
priv fc-cache -f
fc-cache -f "$NERD_FONT_DIR"
log_ok "Font cache updated"

echo
log_ok "All done!"
echo -e "Verify with:"
echo -e "  fc-match 'JetBrainsMono Nerd Font Mono'"
echo -e "  fc-match 'Noto Sans Arabic'"
echo -e "  fc-match monospace"
