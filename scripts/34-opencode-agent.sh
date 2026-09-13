#!/usr/bin/env bash
# DEBSWAY_DESC: OpenCode AI agent + Super+A hotkey + skill file
# DEBSWAY_DEFAULT: Y
# =======================================================
# AI: OpenCode
# -------------------------------------------------------
# Installs OpenCode (https://opencode.ai) — an open-source, terminal-based
# AI coding agent that works with Claude, GPT, Gemini, and other providers
# (bring your own API key, or use its free tier). This is the one piece
# cherry-picked wholesale from ohmydebn (https://github.com/dougburks/ohmydebn,
# MIT licensed) rather than reimplemented — same tool, same idea (a
# Super+A hotkey that installs-then-launches on first press), adapted
# here to run under sway — a `bindsym $mod+a exec debsway agent` (debsway
# CLI from scripts/21-debsway-cli.sh, running OpenCode in a foot terminal)
# instead of kglobalaccel.
#
# XFCE edition: the hotkey is an xfconf keyboard shortcut
# (/commands/custom/<Super>a -> xfce4-terminal -e opencode) instead of
# a sway bindsym line, and the terminal is xfce4-terminal (foot is
# Wayland-only and absent here).
#
# Also drops a small "skill" file describing this system, in the format
# OpenCode (and Claude Code, if you use it too) can read for repo/system
# context — same concept as ohmydebn's own AI skill file.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "AI: OpenCode"

if command_exists opencode; then
    log_ok "OpenCode already installed ($(opencode --version 2>/dev/null || echo 'version unknown'))."
else
    echo -e "${CYAN}OpenCode can be installed two ways:${NC}"
    echo "  1) Official script: curl -fsSL https://opencode.ai/install | bash"
    echo "     (downloads a prebuilt binary straight from opencode.ai — fastest, but"
    echo "      piping curl to bash means trusting that script sight-unseen)"
    echo "  2) npm: npm install -g opencode-ai"
    echo "     (goes through the npm registry instead — needs Node.js/npm installed first)"
    echo
    METHOD=""
    if [ -n "${DEBSWAY_ASSUME_YES:-}" ]; then
        METHOD="1"
    else
        read -rp "$(echo -e "${YELLOW}Install via [1] official script, [2] npm, or [N] skip? (1/2/N): ${NC}")" METHOD
    fi

    case "$METHOD" in
        1)
            log_info "Running the official OpenCode installer..."
            if curl -fsSL https://opencode.ai/install | bash; then
                log_ok "OpenCode installed."
            else
                log_err "OpenCode installation failed."
            fi
            ;;
        2)
            if ! command_exists npm; then
                log_info "npm not found — installing Node.js LTS + npm first."
                install_pkgs "Node.js + npm" nodejs npm
            fi
            if command_exists npm; then
                log_info "Installing opencode-ai via npm..."
                if priv npm install -g opencode-ai; then
                    log_ok "OpenCode installed via npm."
                else
                    log_err "npm install failed."
                fi
            else
                log_err "npm still not available — skipping."
            fi
            ;;
        *)
            log_warn "Skipped OpenCode installation."
            ;;
    esac
fi

# Make sure ~/.opencode/bin (the official installer's default location) or
# $HOME/bin is on PATH for future shells, without duplicating the line.
for CANDIDATE in "$HOME/.opencode/bin" "$HOME/bin"; do
    if [ -d "$CANDIDATE" ] && ! grep -qF "$CANDIDATE" "$HOME/.bashrc" 2>/dev/null; then
        echo "export PATH=\"$CANDIDATE:\$PATH\"" >> "$HOME/.bashrc"
        log_ok "Added $CANDIDATE to PATH in ~/.bashrc"
    fi
done

# ---------------------------------------------------------------------------
# Hotkey: Super+A -> open OpenCode in xfce4-terminal.
#
# On XFCE, keyboard shortcuts are xfconf properties
# (/commands/custom/<keysym> in the xfce4-keyboard-shortcuts channel),
# not bindsym lines. We create the property (idempotently) rather than
# writing a .desktop/global-shortcut registry like KDE's kglobalaccel.
# ---------------------------------------------------------------------------
if command -v xfconf-query &>/dev/null && ask "Bind Super+A to launch OpenCode in a terminal?"; then
    HOTKEY_PROP="/commands/custom/<Super>a"
    HOTKEY_CMD="xfce4-terminal -e opencode"
    current="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$HOTKEY_PROP" 2>/dev/null || true)"
    if [ "$current" = "$HOTKEY_CMD" ]; then
        log_ok "Super+A binding already present ($HOTKEY_CMD)."
    elif [ -n "$current" ]; then
        log_warn "Super+A is already bound to: $current"
        log_warn "Not overwriting — change it in Settings → Keyboard → Application Shortcuts if you want the agent there."
    else
        if xfconf-query -c xfce4-keyboard-shortcuts -p "$HOTKEY_PROP" -n -t string -s "$HOTKEY_CMD" 2>/dev/null; then
            log_ok "Super+A now launches OpenCode ($HOTKEY_CMD). Takes effect immediately."
        else
            log_warn "Could not create the shortcut (xfconf not responding?) — add it manually:"
            log_info "  Settings → Keyboard → Application Shortcuts → $HOTKEY_CMD on Super+A"
        fi
    fi
else
    log_info "Skipped the hotkey — add it manually in Settings → Keyboard → Application Shortcuts:"
    log_info "  xfce4-terminal -e opencode  on  Super+A"
fi

# ---------------------------------------------------------------------------
# System skill file — same idea as ohmydebn's own "skill that all these AI
# tools can use to understand the underlying platform." OpenCode and
# Claude Code both look for AGENTS.md / CLAUDE.md / a skills directory
# depending on version; this drops a plain, tool-agnostic markdown file
# in both common locations so whichever one you use picks it up.
# ---------------------------------------------------------------------------
if ask "Install a system 'skill' file so AI tools know this is a Devuan/XFCE box?"; then
    SKILL_SRC="$SCRIPT_DIR/skills/xfce-setup-SKILL.md"
    if [ -f "$SKILL_SRC" ]; then
        mkdir -p "$HOME/.config/opencode"
        cp "$SKILL_SRC" "$HOME/.config/opencode/AGENTS.md" 2>/dev/null \
            && log_ok "Installed to ~/.config/opencode/AGENTS.md"
        if [ ! -f "$HOME/AGENTS.md" ]; then
            cp "$SKILL_SRC" "$HOME/AGENTS.md" 2>/dev/null \
                && log_ok "Also installed to ~/AGENTS.md (picked up by most terminal AI agents run from \$HOME)."
        fi
    else
        log_warn "Skill file not found at $SKILL_SRC — skipping."
    fi
fi

echo -e "${GREEN}AI (OpenCode) step complete.${NC}"
log_info "Run 'opencode auth login' once to connect a provider (or use its free tier), then just 'opencode' to start."
