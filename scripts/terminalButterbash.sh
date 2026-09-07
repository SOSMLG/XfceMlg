#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  terminalButterbash.sh — ButterBash + XFCE-specific additions
#  ButterBash is the main bash config (aliases, prompt, fzf/
#  zoxide integration). Its own install.sh backs up and then
#  replaces ~/.bashrc, so this appends an "XFCE additions" block
#  afterward — the genuinely XFCE-specific pieces from your
#  reference .bashrc that ButterBash doesn't already provide
#  (it already has its own extract(), git aliases, system-info
#  aliases, etc. — those aren't duplicated here).
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUTTERBASH_SRC="$SCRIPT_DIR/../butterbash"

echo -e "\n${B}${W}══════ Terminal Setup (ButterBash) ══════${Z}"

# ══════════════════════════════════════════════════════════════
step "1/3  Supporting packages"
# ══════════════════════════════════════════════════════════════
info "Refreshing package lists..."
sudo apt-get update -qq

info "Installing bat, duf, eza, fzf, htop, ncdu, ripgrep, tree, zoxide, unar..."
sudo apt-get install -y bat duf eza fzf htop ncdu ripgrep tree zoxide unar \
    || warn "Some packages failed to install (continuing)."
ok "Supporting packages installed"

if command -v starship &>/dev/null; then
    ok "Starship already installed."
else
    info "Installing Starship (not in Debian's repos — uses its official installer)..."
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT
    if curl -sS https://starship.rs/install.sh -o "$WORK_DIR/starship-install.sh"; then
        chmod +x "$WORK_DIR/starship-install.sh"
        if sudo "$WORK_DIR/starship-install.sh" --yes --bin-dir /usr/local/bin; then
            ok "Starship installed to /usr/local/bin"
        else
            warn "Starship installer failed."
        fi
    else
        warn "Could not download the Starship installer."
    fi
fi

# ══════════════════════════════════════════════════════════════
step "2/3  Install ButterBash"
# ══════════════════════════════════════════════════════════════
if [[ ! -d "$BUTTERBASH_SRC" ]] || [[ ! -f "$BUTTERBASH_SRC/install.sh" ]]; then
    err "Bundled ButterBash not found at $BUTTERBASH_SRC"
fi

info "Installing ButterBash from $BUTTERBASH_SRC ..."
# ButterBash's own install.sh relies on relative paths (./bash,
# ./bashrc.example), so it needs to be run from inside its directory.
# It backs up any existing ~/.bashrc before replacing it.
if ( cd "$BUTTERBASH_SRC" && bash install.sh --yes ); then
    ok "ButterBash installed."
else
    err "ButterBash installation failed."
fi

# ══════════════════════════════════════════════════════════════
step "3/3  XFCE-specific additions"
# ══════════════════════════════════════════════════════════════
# Appended after ButterBash's install so these apply on top of it —
# same "base + additions" pattern as firefoxHarden.sh's Betterfox setup.
MARKER="# BEGIN XFCE ADDITIONS"
if grep -qF "$MARKER" "$HOME/.bashrc" 2>/dev/null; then
    ok "XFCE additions already present in ~/.bashrc, skipping."
else
    cat >> "$HOME/.bashrc" << 'BASHRC_EOF'

# ══════════════════════════════════════════════════════════════
# BEGIN XFCE ADDITIONS — not covered by ButterBash itself
# ══════════════════════════════════════════════════════════════

# zoxide-driven navigation (matches ButterBash's own `z`/`zi` commands,
# just also rebinds plain `cd` to jump by frecency instead of by path)
if command -v zoxide >/dev/null 2>&1; then
    alias cd='z'
    alias ..='z ..'
    alias ...='z ../..'
    alias ....='z ../../..'
    alias -- -='z -'
fi

# XFCE panel
alias restart-panel='xfce4-panel -r && echo "XFCE4 panel restarted"'

# Screenshot
alias screenshot='xfce4-screenshooter -f'

# Terminal / file manager helpers
alias term='alacritty --working-directory "$(pwd)"'
alias thunar-daemon='thunar --daemon'
alias here='thunar "$(pwd)"'

# Display / input toggles (adjust the output name if you have more than
# one monitor — this grabs the first connected output)
alias brightness-up="xrandr --output \$(xrandr | grep ' connected' | cut -d ' ' -f1) --brightness 0.9"
alias brightness-down="xrandr --output \$(xrandr | grep ' connected' | cut -d ' ' -f1) --brightness 0.7"
alias touchpad-toggle="synclient TouchpadOff=\$(synclient -l | grep -q 'TouchpadOff.*1' && echo 0 || echo 1)"

# ══════════════════════════════════════════════════════════════
# END XFCE ADDITIONS
# ══════════════════════════════════════════════════════════════
BASHRC_EOF
    ok "XFCE-specific additions appended to ~/.bashrc"
fi

warn "Run 'source ~/.bashrc' or open a new terminal to use it."
ok "Terminal setup complete."
