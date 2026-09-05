#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  terminalRedTheme.sh — Catppuccin Mocha (Red) terminal colors
#  Recolors xfce4-terminal to match catppuccinTheme.sh's panel
#  theme, and optionally installs Alacritty and/or Kitty with a
#  matching config if you'd rather have a GPU-accelerated terminal
#  than XFCE's default VTE-based one.
#  Runs independently of terminalButterbash.sh — this is about the
#  terminal's *appearance*, that script is about the shell inside it.
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

# Official Catppuccin Mocha terminal ANSI mapping (used across most
# Catppuccin terminal ports), 16 colors, normal then bright.
CP_FG="#cdd6f4"        # Text
CP_BG="#1e1e2e"        # Base
CP_CURSOR="#f38ba8"    # Red
CP_ANSI="#45475a;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#bac2de;#585b70;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#a6adc8"

FONT_FAMILY="JetBrainsMono Nerd Font Mono"
command -v fc-list &>/dev/null && fc-list | grep -qi "JetBrainsMono Nerd Font" \
    || warn "JetBrainsMono Nerd Font not detected — run installFonts.sh first, or icons/ligatures may be missing."

echo -e "\n${B}${W}══════ Terminal Colors (Catppuccin Mocha, Red) ══════${Z}"

# ══════════════════════════════════════════════════════════════
step "1/4  xfce4-terminal colorscheme"
# ══════════════════════════════════════════════════════════════
if ask "Recolor xfce4-terminal to Catppuccin Mocha (Red cursor/accent)?"; then
    COLORSCHEME_DIR="$HOME/.local/share/xfce4/terminal/colorschemes"
    TERMINALRC_DIR="$HOME/.config/xfce4/terminal"
    mkdir -p "$COLORSCHEME_DIR" "$TERMINALRC_DIR"

    cat > "$COLORSCHEME_DIR/CatppuccinThinkRed.theme" << EOF
[Scheme]
Name=Catppuccin Mocha (ThinkRed)
ColorForeground=${CP_FG}
ColorBackground=${CP_BG}
ColorCursor=${CP_CURSOR}
ColorCursorForeground=${CP_BG}
ColorBold=${CP_CURSOR}
ColorBoldUseDefault=FALSE
TabActivityColor=${CP_CURSOR}
ColorPalette=${CP_ANSI}
EOF
    ok "Colorscheme preset written (selectable later under Preferences → Appearance)."

    TERMINALRC="$TERMINALRC_DIR/terminalrc"
    if [[ -f "$TERMINALRC" ]]; then
        cp "$TERMINALRC" "${TERMINALRC}.bak.$(date +%Y%m%d%H%M%S)"
        info "Backed up existing terminalrc."
    fi
    cat > "$TERMINALRC" << EOF
[Configuration]
FontName=${FONT_FAMILY} 11
ColorForeground=${CP_FG}
ColorBackground=${CP_BG}
ColorCursor=${CP_CURSOR}
ColorCursorForeground=${CP_BG}
ColorBold=${CP_CURSOR}
ColorBoldUseDefault=FALSE
ColorPalette=${CP_ANSI}
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundAlpha=90
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBellUrgent=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=100x28
MiscInheritGeometry=FALSE
MiscMenubarDefault=FALSE
MiscMouseAutohide=FALSE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
MiscMiddleClickOpensUri=FALSE
MiscCopyOnSelect=FALSE
MiscShowRelaunchDialog=TRUE
MiscRewrapOnResize=TRUE
MiscUseShiftArrowsToScroll=FALSE
MiscSlimTabs=FALSE
MiscNewTabAdjacent=FALSE
MiscShowUnsafePasteDialog=TRUE
EOF
    ok "xfce4-terminal recolored (applies to new terminal windows)."
else
    warn "Skipped xfce4-terminal recolor."
fi

# ══════════════════════════════════════════════════════════════
step "2/4  Alacritty (optional GPU-accelerated terminal)"
# ══════════════════════════════════════════════════════════════
ALACRITTY_INSTALLED=0
if ask "Also install Alacritty with a matching Catppuccin Red config?" "N"; then
    sudo apt-get update -qq
    if sudo apt-get install -y alacritty; then
        mkdir -p "$HOME/.config/alacritty"
        cat > "$HOME/.config/alacritty/alacritty.toml" << EOF
[window]
opacity = 0.90
decorations = "full"

[font]
size = 11.0
normal = { family = "${FONT_FAMILY}", style = "Regular" }
bold = { family = "${FONT_FAMILY}", style = "Bold" }

[cursor]
style = { shape = "Block", blinking = "Off" }

[colors.primary]
background = "${CP_BG}"
foreground = "${CP_FG}"

[colors.cursor]
text = "${CP_BG}"
cursor = "${CP_CURSOR}"

[colors.normal]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"

[colors.bright]
black = "#585b70"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#a6adc8"
EOF
        ok "Alacritty installed and configured (~/.config/alacritty/alacritty.toml)."
        ALACRITTY_INSTALLED=1
    else
        warn "Alacritty isn't in this system's apt repos — skipping. (It's usually available via cargo/rustup if you need it.)"
    fi
else
    warn "Skipped Alacritty."
fi

# ══════════════════════════════════════════════════════════════
step "3/4  Kitty (optional GPU-accelerated terminal)"
# ══════════════════════════════════════════════════════════════
KITTY_INSTALLED=0
if ask "Also install Kitty with a matching Catppuccin Red config?" "N"; then
    sudo apt-get update -qq
    if sudo apt-get install -y kitty; then
        mkdir -p "$HOME/.config/kitty"
        cat > "$HOME/.config/kitty/catppuccin-thinkred.conf" << EOF
foreground              ${CP_FG}
background              ${CP_BG}
cursor                   ${CP_CURSOR}
cursor_text_color       ${CP_BG}
selection_foreground    ${CP_BG}
selection_background    ${CP_FG}

color0  #45475a
color8  #585b70
color1  #f38ba8
color9  #f38ba8
color2  #a6e3a1
color10 #a6e3a1
color3  #f9e2af
color11 #f9e2af
color4  #89b4fa
color12 #89b4fa
color5  #f5c2e7
color13 #f5c2e7
color6  #94e2d5
color14 #94e2d5
color7  #bac2de
color15 #a6adc8
EOF
        cat > "$HOME/.config/kitty/kitty.conf" << EOF
include catppuccin-thinkred.conf
font_family      ${FONT_FAMILY}
font_size        11.0
cursor_shape     block
cursor_blink_interval 0
background_opacity 0.90
confirm_os_window_close 0
EOF
        ok "Kitty installed and configured (~/.config/kitty/kitty.conf)."
        KITTY_INSTALLED=1
    else
        warn "Kitty isn't in this system's apt repos — skipping."
    fi
else
    warn "Skipped Kitty."
fi

# ══════════════════════════════════════════════════════════════
step "4/4  Default terminal emulator"
# ══════════════════════════════════════════════════════════════
if [[ $ALACRITTY_INSTALLED -eq 1 || $KITTY_INSTALLED -eq 1 ]]; then
    echo -e "${Y}Which terminal should Thunar's \"Open Terminal Here\", keyboard shortcuts,"
    echo -e "and \"x-terminal-emulator\" point at?${Z}"
    OPTIONS=("xfce4-terminal")
    [[ $ALACRITTY_INSTALLED -eq 1 ]] && OPTIONS+=("alacritty")
    [[ $KITTY_INSTALLED -eq 1 ]] && OPTIONS+=("kitty")

    PS3="$(echo -e "${Y}Pick a number (default 1 — keeps xfce4-terminal): ${Z}")"
    select CHOICE in "${OPTIONS[@]}"; do
        [[ -n "$CHOICE" ]] || CHOICE="xfce4-terminal"
        break
    done

    if [[ "$CHOICE" != "xfce4-terminal" ]]; then
        BIN_PATH=$(command -v "$CHOICE" || true)
        if [[ -n "$BIN_PATH" ]]; then
            if command -v update-alternatives &>/dev/null; then
                sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$BIN_PATH" 50 2>/dev/null || true
                sudo update-alternatives --set x-terminal-emulator "$BIN_PATH" 2>/dev/null || true
            fi
            HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
            mkdir -p "$HOME/.config/xfce4"
            if [[ -f "$HELPERS_RC" ]]; then
                grep -v '^TerminalEmulator=' "$HELPERS_RC" > "${HELPERS_RC}.tmp" 2>/dev/null && mv "${HELPERS_RC}.tmp" "$HELPERS_RC"
            fi
            echo "TerminalEmulator=$CHOICE" >> "$HELPERS_RC"
            ok "Default terminal set to $CHOICE. xfce4-terminal stays installed as a fallback."
        else
            warn "Couldn't find $CHOICE on PATH — leaving xfce4-terminal as default."
        fi
    else
        ok "Keeping xfce4-terminal as the default."
    fi
else
    ok "Only xfce4-terminal is set up — nothing to switch."
fi

echo
ok "Terminal theming done. Open a new terminal window to see the colors."
