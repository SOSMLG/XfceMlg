#!/usr/bin/env bash
# DEBSWAY_DESC: Neovim (Debian apt 0.10) + LazyVim v14 pinned config
# DEBSWAY_DEFAULT: N
# =======================================================
# Neovim, the Debian-native edition
# -------------------------------------------------------
# Debian/Devuan stable ships Neovim 0.10.x, while current LazyVim
# needs >= 0.11.2 (and backports has nothing newer). Instead of
# fighting APT with an upstream tarball, this step keeps the Debian
# package and pins the config to what runs on it:
#   1. Installs apt `neovim` (no-op when already present) plus the
#      LazyVim baseline (git, gcc for treesitter, curl, ripgrep,
#      fd-find + an `fd` shim, since Debian names it fdfind).
#   2. Clones the LazyVim starter into ~/.config/nvim — but ONLY when
#      that dir is absent. A stale toolkit stub (the pre-LazyVim
#      dev-essentials bootstrap) is recognized by signature and moved
#      aside with a timestamped backup after asking; any other
#      existing config is NEVER touched.
#   3. Pins LazyVim to the v14 release line (last supporting 0.10)
#      and treesitter to its legacy master branch, via
#      ~/.config/nvim/lua/plugins/xfce-pinned.lua. On Neovim
#      >= 0.11.2 (e.g. you installed upstream yourself) the pin is
#      skipped so you ride the current LazyVim line.
# NvChad is deliberately NOT offered: its starter is v3-only, which
# needs >= 0.11 — there is no clean pinned alternative for 0.10.
# Idempotent — re-runs skip everything already in place.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Neovim (Debian) + LazyVim"

NVIM_MIN_PIN="0.9.0"    # floor for the v14-pinned path
NVIM_MIN_CUR="0.11.2"   # floor for the current LazyVim line
NVIM_DIR="$HOME/.config/nvim"
PIN_FILE="$NVIM_DIR/lua/plugins/xfce-pinned.lua"

# ver_ge <a> <b> — true when version a >= b (sort -V comparison).
ver_ge() { printf '%s\n' "$2" "$1" | sort -V -C 2>/dev/null; }

# current_nvim_ver — first X.Y.Z from `nvim --version`, or empty.
current_nvim_ver() {
    command -v nvim >/dev/null 2>&1 || return 0
    nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# The pre-LazyVim dev-essentials bootstrap is exactly this: a one-line
# init.lua plus a lazy.lua carrying our distinctive example comment.
# (Matched narrowly on purpose — the real LazyVim starter also has an
# init.lua reading `require("config.lazy")`, but it ships lua/plugins/
# and extra config modules, so the negative markers below exclude it.)
is_legacy_stub() {
    local init="$NVIM_DIR/init.lua" lazy="$NVIM_DIR/lua/config/lazy.lua"
    [ -f "$init" ] && [ -f "$lazy" ] \
    && [ "$(cat "$init" 2>/dev/null)" = 'require("config.lazy")' ] \
    && grep -q "Add plugins here\. Example:" "$lazy" 2>/dev/null \
    && [ ! -d "$NVIM_DIR/lua/plugins" ] \
    && [ ! -e "$NVIM_DIR/lazyvim.json" ]
}

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Debian neovim + LazyVim baseline (treesitter compiler + pickers)
# ---------------------------------------------------------------------------
if ask "Install Neovim (Debian apt) + distro deps (git, gcc, curl, ripgrep, fd-find)?"; then
    install_pkgs "Neovim + deps" neovim git gcc curl ripgrep fd-find
    # Debian ships `fdfind`; pickers want `fd`.
    if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        priv ln -sfn /usr/bin/fdfind /usr/local/bin/fd \
            && log_ok "fd shim installed (/usr/local/bin/fd -> fdfind)."
    fi
fi

command -v nvim >/dev/null 2>&1 || { log_err "No nvim on PATH — install failed?"; exit 1; }
HAVE="$(current_nvim_ver)"
if [ -z "$HAVE" ]; then
    log_err "Could not parse nvim version."
    exit 1
fi
log_info "Neovim $HAVE ($(command -v nvim))."

# Retire the /opt tarball install from the earlier revision of this
# script, if present — but ONLY script-managed paths (a symlink into
# /opt/nvim-*), never a hand-built binary.
if [ -L /usr/local/bin/nvim ]; then
    _target="$(readlink /usr/local/bin/nvim)"
    case "$_target" in
        /opt/nvim-*)
            log_info "Removing superseded script-managed install ($_target)..."
            priv rm -f /usr/local/bin/nvim
            for d in /opt/nvim-*/; do
                [ -d "$d" ] || continue
                priv rm -rf "$d" && log_info "Removed stale $d."
            done
            ;;
    esac
    unset _target
fi

PIN_MODE=1
if ver_ge "$HAVE" "$NVIM_MIN_CUR"; then
    log_ok "Neovim $HAVE >= $NVIM_MIN_CUR — current LazyVim line, no pin needed."
    PIN_MODE=0
elif ver_ge "$HAVE" "$NVIM_MIN_PIN"; then
    log_info "Neovim $HAVE < $NVIM_MIN_CUR — LazyVim will be pinned to v14."
else
    log_err "Neovim $HAVE is older than $NVIM_MIN_PIN — too old even for LazyVim v14."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. LazyVim starter (clone only into an absent dir)
# ---------------------------------------------------------------------------
if [ -d "$NVIM_DIR" ] && [ -n "$(ls -A "$NVIM_DIR" 2>/dev/null)" ]; then
    if is_legacy_stub; then
        if ask "Found the old toolkit nvim stub — move it to a timestamped backup and install the LazyVim starter?"; then
            BACKUP="$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
            mv "$NVIM_DIR" "$BACKUP" && log_ok "Old stub backed up to $BACKUP."
        else
            log_warn "Keeping existing $NVIM_DIR — starter not installed."
            echo -e "${GREEN}Neovim binary setup complete.${NC}"
            exit 0
        fi
    else
        log_warn "$NVIM_DIR already exists and is not the old toolkit stub — refusing to touch it."
        log_warn "To switch starters: back it up (mv ~/.config/nvim ~/.config/nvim.bak), then re-run this script."
        echo -e "${GREEN}Neovim binary setup complete.${NC}"
        exit 0
    fi
fi

if [ ! -d "$NVIM_DIR" ] && ask "Clone the LazyVim starter into $NVIM_DIR?"; then
    if git clone --depth 1 https://github.com/LazyVim/starter "$NVIM_DIR"; then
        rm -rf "$NVIM_DIR/.git"
        log_ok "LazyVim starter installed ($NVIM_DIR)."
    else
        log_err "git clone failed — check network/GitHub reachability, then re-run."
        exit 1
    fi
fi

[ -d "$NVIM_DIR" ] || { log_warn "No $NVIM_DIR — starter not installed."; exit 0; }

# ---------------------------------------------------------------------------
# 3. v14 pin for the 0.10 line (skipped on >= 0.11.2)
# ---------------------------------------------------------------------------
if [ "$PIN_MODE" -eq 1 ]; then
    if [ -f "$PIN_FILE" ] && grep -q "devuan-xfce-setup 46-neovim" "$PIN_FILE" 2>/dev/null; then
        log_ok "v14 pin already present."
    else
        mkdir -p "$NVIM_DIR/lua/plugins"
        cat > "$PIN_FILE" << 'EOF'
-- Written by devuan-xfce-setup 46-neovim.sh — Debian ships Neovim 0.10
-- while current LazyVim needs >= 0.11.2. Stay on the v14 release line
-- (last supporting 0.10) and on the legacy treesitter master branch.
-- Delete this file after upgrading Neovim to ride the current line.
return {
  { "LazyVim/LazyVim", version = "14.*" },
  { "nvim-treesitter/nvim-treesitter", branch = "master" },
  { "nvim-treesitter/nvim-treesitter-textobjects", branch = "master" },
}
EOF
        log_ok "LazyVim pinned to v14 (0.10-compatible)."
    fi
fi

echo
log_ok "Neovim $HAVE + LazyVim ready."
log_info "First launch: run 'nvim' — plugins install themselves on startup."
log_info "Then inside nvim: ':Lazy' shows the pinned v14 versions, ':Mason' adds LSP/formatter binaries, ':checkhealth' verifies."
log_info "Nerd Font icons are covered by 17-fonts.sh (JetBrainsMono Nerd Font)."
