#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  installFonts.sh — Devuan/Debian font setup
#  Installs: Noto (Latin + Arabic + Emoji), Font Awesome,
#            JetBrainsMono Nerd Font (latest GitHub release)
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

echo -e "\n${B}${W}══════ Font Installer (Devuan/Debian) ══════${Z}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ══════════════════════════════════════════════════════════════
step "1/4  APT packages"
# ══════════════════════════════════════════════════════════════
info "Updating package lists..."
sudo apt-get update -qq

info "Installing Noto + Font Awesome via apt..."
sudo apt-get install -y \
    curl \
    fonts-font-awesome \
    fonts-noto-core \
    fonts-noto-unhinted \
    fonts-noto-color-emoji \
    fonts-noto-mono \
    || err "APT install failed"
ok "APT fonts installed"

# ══════════════════════════════════════════════════════════════
step "2/4  JetBrainsMono Nerd Font"
# ══════════════════════════════════════════════════════════════
NERD_FONT_DIR="${HOME}/.local/share/fonts/NerdFonts"
mkdir -p "$NERD_FONT_DIR"

if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    warn "JetBrainsMono Nerd Font already installed — skipping download"
else
    info "Fetching latest release URL from GitHub..."
    DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
        | grep -oP '"browser_download_url": "\K[^"]+' \
        | grep -i "JetBrainsMono.*tar\.xz" \
        | head -1)

    if [[ -z "$DOWNLOAD_URL" ]]; then
        warn "GitHub API failed, using fallback URL..."
        DOWNLOAD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz"
    fi

    FONT_ARCHIVE="${WORK_DIR}/JetBrainsMono.tar.xz"
    info "Downloading JetBrainsMono Nerd Font..."
    curl -fsSL --progress-bar -L -o "$FONT_ARCHIVE" "$DOWNLOAD_URL" || err "Download failed: ${DOWNLOAD_URL}"

    info "Extracting fonts..."
    if ! tar -xf "$FONT_ARCHIVE" -C "$NERD_FONT_DIR" --wildcards '*.ttf' 2>/dev/null; then
        warn "Falling back to full extraction..."
        tar -xf "$FONT_ARCHIVE" -C "$NERD_FONT_DIR" || err "Failed to extract font archive"
    fi
    ok "JetBrainsMono Nerd Font installed to ${NERD_FONT_DIR}"
fi

# ══════════════════════════════════════════════════════════════
step "3/4  Fontconfig"
# ══════════════════════════════════════════════════════════════
FONTCONF_DIR="${HOME}/.config/fontconfig"
FONTCONF="${FONTCONF_DIR}/fonts.conf"
mkdir -p "$FONTCONF_DIR"

info "Writing ${FONTCONF}..."
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
ok "fonts.conf written"

# ══════════════════════════════════════════════════════════════
step "4/4  Rebuild font cache"
# ══════════════════════════════════════════════════════════════
info "Rebuilding font cache..."
sudo fc-cache -f
fc-cache -f "$NERD_FONT_DIR"
ok "Font cache updated"

echo
ok "All done!"
echo -e "${C}Verify with:${Z}"
echo -e "  fc-match 'JetBrainsMono Nerd Font Mono'"
echo -e "  fc-match 'Noto Sans Arabic'"
echo -e "  fc-match monospace"
