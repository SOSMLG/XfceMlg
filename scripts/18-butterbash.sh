#!/usr/bin/env bash
# DEBSWAY_DESC: ButterBash + XFCE shell additions + xfce4-terminal default
# DEBSWAY_DEFAULT: Y
#  18-butterbash.sh — ButterBash + XFCE-specific additions
#  ButterBash is the main bash config (aliases, prompt, fzf/
#  zoxide integration). Its own install.sh backs up and then
#  replaces ~/.bashrc, so this appends an "XFCE additions" block
#  afterward — the genuinely XFCE-specific pieces from your
#  reference .bashrc that ButterBash doesn't already provide
#  (it already has its own extract(), git aliases, system-info
#  aliases, etc. — those aren't duplicated here).
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root



BUTTERBASH_SRC="$SCRIPT_DIR/../butterbash"


log_head "1/3  Supporting packages"
apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_info "Installing bat, duf, eza, fzf, btop, ncdu, ripgrep, tree, zoxide, unar..."
priv apt-get install -y bat duf eza fzf btop ncdu ripgrep tree zoxide unar \
    || log_warn "Some packages failed to install (continuing)."
log_ok "Supporting packages installed"

if command -v starship &>/dev/null; then
    log_ok "Starship already installed."
else
    log_info "Installing Starship (not in Debian's repos — uses its official installer)..."
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT
    if curl -sS https://starship.rs/install.sh -o "$WORK_DIR/starship-install.sh"; then
        chmod +x "$WORK_DIR/starship-install.sh"
        if priv "$WORK_DIR/starship-install.sh" --yes --bin-dir /usr/local/bin; then
            log_ok "Starship installed to /usr/local/bin"
        else
            log_warn "Starship installer failed."
        fi
    else
        log_warn "Could not download the Starship installer."
    fi
fi

log_head "2/3  Install ButterBash"
if [[ ! -d "$BUTTERBASH_SRC" ]] || [[ ! -f "$BUTTERBASH_SRC/install.sh" ]]; then
    log_err "Bundled ButterBash not found at $BUTTERBASH_SRC"; exit 1
fi

log_info "Installing ButterBash from $BUTTERBASH_SRC ..."
# ButterBash's own install.sh relies on relative paths (./bash,
# ./bashrc.example), so it needs to be run from inside its directory.
# It backs up any existing ~/.bashrc before replacing it.
if ( cd "$BUTTERBASH_SRC" && bash install.sh --yes ); then
    log_ok "ButterBash installed."
else
    log_err "ButterBash installation failed."; exit 1
fi

log_head "3/3  XFCE-specific additions"
# Appended after ButterBash's install so these apply on top of it —
# same "base + additions" pattern as 16-firefox.sh's Betterfox setup.
MARKER="# BEGIN XFCE ADDITIONS"
if grep -qF "$MARKER" "$HOME/.bashrc" 2>/dev/null; then
    log_ok "XFCE additions already present in ~/.bashrc, skipping."
else
    cat >> "$HOME/.bashrc" << 'BASHRC_EOF'

# BEGIN XFCE ADDITIONS — not covered by ButterBash itself

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
alias term='xfce4-terminal --working-directory="$(pwd)"'
alias thunar-daemon='thunar --daemon'
alias here='thunar "$(pwd)"'

# Display / input toggles (adjust the output name if you have more than
# one monitor — this grabs the first connected output)
alias brightness-up="xrandr --output \$(xrandr | grep ' connected' | cut -d ' ' -f1) --brightness 0.9"
alias brightness-down="xrandr --output \$(xrandr | grep ' connected' | cut -d ' ' -f1) --brightness 0.7"
alias touchpad-toggle="synclient TouchpadOff=\$(synclient -l | grep -q 'TouchpadOff.*1' && echo 0 || echo 1)"

# END XFCE ADDITIONS
BASHRC_EOF
    log_ok "XFCE-specific additions appended to ~/.bashrc"
fi

log_warn "Run 'source ~/.bashrc' or open a new terminal to use it."
log_ok "Terminal setup complete."
