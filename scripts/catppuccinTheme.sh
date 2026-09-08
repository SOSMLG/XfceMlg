#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  catppuccinTheme.sh — the whole ThinkPad-red look, in one pass.
#
#  Catppuccin Mocha, "Black" background + "Red" accent — black
#  chassis, red trackpoint nub. One script now covers everything
#  that used to be three (terminalRedTheme.sh and picomSetup.sh
#  are folded in below):
#    - GTK2/3/4 + xfwm4 theme  (Fausto-Korpsvart/Catppuccin-GTK-Theme)
#    - Cursor theme            (catppuccin/cursors, mocha-red)
#    - Icon theme              (ljmill/catppuccin-icons "Catppuccin-SE")
#      + a lean "Catppuccin-SE-Local" variant: only the app icons
#        you actually have installed, slim Inherits= chain, so
#        XFCE isn't indexing a 100+MB icon set at login
#    - Panel gtk.css override, red/maroon accents
#    - picom — fades only, no shadows/blur, unredirects fullscreen
#      (replaces xfwm4's built-in compositor, doesn't run both)
#    - Terminal: Alacritty, Catppuccin Red config, set as THE
#      terminal — xfce4-terminal is removed, not kept alongside
#
#  Since choosing to run this script already means "yes, do the
#  theme," most steps below just run — no per-step Y/n barrage.
#  The only prompts left are genuinely optional extras at the end.
#
#  This retires the Chicago95 (Windows 95) theme this toolkit used
#  to offer — see chicagofier.sh's removal in the changelog.
#  Privilege: sudo (packages only; theme files go in $HOME)
# ══════════════════════════════════════════════════════════════
set -uo pipefail
# NOTE: deliberately not using -e globally — this script talks to
# several upstream GitHub repos, any one of which can have a bad
# day. Every risky step is wrapped in its own check so one failure
# degrades gracefully instead of aborting everything after it.

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

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

THEMES_DIR="$HOME/.themes"
ICONS_DIR="$HOME/.local/share/icons"
mkdir -p "$THEMES_DIR" "$ICONS_DIR" "$HOME/.icons" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

# Catppuccin Mocha palette used throughout this script.
CP_TEXT="#cdd6f4" CP_BASE="#1e1e2e" CP_RED="#f38ba8" CP_MAROON="#eba0ac"
CP_SURFACE1="#45475a" CP_SURFACE2="#585b70" CP_CRUST="#11111b"

echo -e "\n${B}${W}══════ Catppuccin ThinkRed — GTK + Icons + Cursors + Panel + Terminal ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

# ══════════════════════════════════════════════════════════════
step "1/7  Dependencies"
# ══════════════════════════════════════════════════════════════
sudo apt-get install -y \
    gtk2-engines-murrine gnome-themes-extra adwaita-icon-theme \
    git curl unzip tar sassc xfce4-panel xfwm4 \
    || warn "Some packages failed to install (continuing — the theme may partially apply)."
ok "Dependencies installed."

# ══════════════════════════════════════════════════════════════
step "2/7  Retiring Chicago95 (if it was ever installed here)"
# ══════════════════════════════════════════════════════════════
rm -rf "$HOME/.themes/Chicago95" "$HOME/.icons/Chicago95" \
       "$HOME/.Chicago95PlusFiles" "$HOME/.Chicago95Plus" "$HOME/.chicago95plus" \
       "$HOME/.local/share/xfce4/terminal/colorschemes/Chicago95.theme" \
       "$HOME/.local/share/applications/chicago95plus.desktop" \
       "$HOME/.config/autostart/chicago95-startup.desktop" 2>/dev/null
ok "Chicago95 remnants cleared (if any existed)."

# ══════════════════════════════════════════════════════════════
step "3/7  GTK + Window Manager theme (Catppuccin, Red/Black)"
# ══════════════════════════════════════════════════════════════
GTK_THEME_NAME=""
rm -rf "$WORK_DIR/Catppuccin-GTK-Theme"
info "Cloning Fausto-Korpsvart/Catppuccin-GTK-Theme..."
if git clone --depth=1 https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git \
    "$WORK_DIR/Catppuccin-GTK-Theme" 2>/tmp/catppuccin-gtk-clone.log; then

    cd "$WORK_DIR/Catppuccin-GTK-Theme"
    # Installer's actual location has moved upstream before (root ->
    # themes/install.sh). Find it rather than hardcode a path.
    INSTALLER=$(find . -maxdepth 2 -iname "install.sh" 2>/dev/null | sort | head -1)

    if [[ -z "$INSTALLER" ]]; then
        err "Couldn't find install.sh in the cloned repo — upstream layout changed again."
        err "Browse https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme and install manually."
    else
        chmod +x "$INSTALLER"
        info "Building the Red/Black variant via $INSTALLER (a minute or two)..."
        INSTALL_OK=0
        EXPECTED_NAME="Catppuccin-Red-Dark-Compact-BK"

        # BATCH_MODE=true is load-bearing: the installer ends with an
        # interactive "apply now?" arrow-key menu. With no TTY (piped
        # to a log, as here) that read blocks/errors instead of just
        # failing softly. BATCH_MODE=true skips it — we apply the
        # theme ourselves via xfconf-query below either way.
        if BATCH_MODE=true timeout 300 "$INSTALLER" -d "$THEMES_DIR" -n Catppuccin -a red -m dark -s compact --tweaks black \
            >/tmp/catppuccin-gtk-install.log 2>&1; then
            INSTALL_OK=1
        elif BATCH_MODE=true timeout 300 "$INSTALLER" -t red -c black -s compact -d "$THEMES_DIR" -n Catppuccin \
            >>/tmp/catppuccin-gtk-install.log 2>&1; then
            INSTALL_OK=1
        else
            warn "Neither known install.sh call style worked (upstream CLI may have changed again)."
            info "Falling back to a full default install — every flavour/accent gets built, we'll pick Red/Black out of it."
            if BATCH_MODE=true timeout 600 "$INSTALLER" -d "$THEMES_DIR" -n Catppuccin >>/tmp/catppuccin-gtk-install.log 2>&1 \
                || BATCH_MODE=true timeout 600 "$INSTALLER" >>/tmp/catppuccin-gtk-install.log 2>&1; then
                INSTALL_OK=1
            fi
        fi

        if [[ $INSTALL_OK -eq 1 ]]; then
            [[ -d "$THEMES_DIR/$EXPECTED_NAME" ]] && GTK_THEME_NAME="$EXPECTED_NAME"
            [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$THEMES_DIR" -maxdepth 1 -type d \
                \( -iname "*red*dark*" -o -iname "*dark*red*" \) -printf '%f\n' 2>/dev/null | sort | head -1)
            [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$THEMES_DIR" -maxdepth 1 -type d \
                -iname "*catppuccin*red*" -printf '%f\n' 2>/dev/null | head -1)
            [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$THEMES_DIR" -maxdepth 1 -type d \
                -iname "*catppuccin*" -printf '%f\n' 2>/dev/null | head -1)

            if [[ -n "$GTK_THEME_NAME" ]]; then
                ok "Installed as: $GTK_THEME_NAME"
                xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_THEME_NAME" 2>/dev/null || true
                xfconf-query -c xfwm4 -p /general/theme -s "$GTK_THEME_NAME" 2>/dev/null || true
                gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
            else
                warn "Theme installed but couldn't auto-detect its folder name under $THEMES_DIR."
                warn "Open Settings → Appearance and pick the Catppuccin Red/Dark variant manually."
            fi
        else
            err "Catppuccin-GTK-Theme install failed under every known CLI style. Log: /tmp/catppuccin-gtk-install.log"
        fi
    fi
    cd "$WORK_DIR"
else
    err "Clone failed — check your network/DNS and rerun this script. Log: /tmp/catppuccin-gtk-clone.log"
fi

# ══════════════════════════════════════════════════════════════
step "4/7  Cursor theme (Catppuccin Mocha, Red)"
# ══════════════════════════════════════════════════════════════
CURSOR_ZIP="$WORK_DIR/catppuccin-mocha-red-cursors.zip"
CURSOR_URL="https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-red-cursors.zip"
info "Downloading cursors..."
if curl -fsSL -o "$CURSOR_ZIP" "$CURSOR_URL" && unzip -oq "$CURSOR_ZIP" -d "$HOME/.icons"; then
    CURSOR_NAME=$(find "$HOME/.icons" -maxdepth 1 -type d -iname "*mocha*red*cursor*" -printf '%f\n' | head -1)
    CURSOR_NAME=${CURSOR_NAME:-catppuccin-mocha-red-cursors}
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CURSOR_NAME" 2>/dev/null || true
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_NAME" > "$HOME/.icons/default/index.theme"
    ok "Cursor theme installed and applied: $CURSOR_NAME"
else
    err "Cursor download/extract failed (upstream may have renamed the release asset). Skipping."
fi

# ══════════════════════════════════════════════════════════════
step "5/7  Icon theme (Catppuccin-SE, full set + lean local variant)"
# ══════════════════════════════════════════════════════════════
ICON_BASE="$ICONS_DIR/Catppuccin-SE"
ACTIVE_ICON_THEME="Catppuccin-SE"
info "Resolving latest ljmill/catppuccin-icons release..."
ICON_URL=$(curl -fsSL https://api.github.com/repos/ljmill/catppuccin-icons/releases/latest \
    | grep -oP '"browser_download_url":\s*"\K[^"]+Catppuccin-SE\.tar\.bz2' | head -1)
[[ -z "$ICON_URL" ]] && { warn "GitHub API lookup failed, using a fallback known-good release URL."; \
    ICON_URL="https://github.com/ljmill/catppuccin-icons/releases/download/v0.2.0/Catppuccin-SE.tar.bz2"; }

ICON_TARBALL="$WORK_DIR/Catppuccin-SE.tar.bz2"
if curl -fsSL --progress-bar -o "$ICON_TARBALL" "$ICON_URL"; then
    rm -rf "$ICON_BASE"
    if tar -xjf "$ICON_TARBALL" -C "$ICONS_DIR"; then
        if [[ ! -d "$ICON_BASE" ]]; then
            FOUND=$(find "$ICONS_DIR" -maxdepth 2 -type d -iname "Catppuccin-SE" | head -1)
            [[ -n "$FOUND" && "$FOUND" != "$ICON_BASE" ]] && mv "$FOUND" "$ICON_BASE"
        fi
        ok "Catppuccin-SE installed to $ICON_BASE ($(du -sh "$ICON_BASE" 2>/dev/null | cut -f1))"

        # Lean local variant: keep the small "UI chrome" categories
        # wholesale, but only pull app icons for software you actually
        # have installed, then trim Inherits= so XFCE isn't indexing
        # the full upstream set. Full Catppuccin-SE stays on disk as
        # a manual fallback; this is what's actually active.
        LOCAL_ICON_DIR="$ICONS_DIR/Catppuccin-SE-Local"
        rm -rf "$LOCAL_ICON_DIR"
        mkdir -p "$LOCAL_ICON_DIR"

        DESIRED_ICONS="$WORK_DIR/desired-icons.txt"
        grep -h '^Icon=' /usr/share/applications/*.desktop "$HOME/.local/share/applications"/*.desktop 2>/dev/null \
            | sed 's/^Icon=//' | sort -u > "$DESIRED_ICONS"
        cat >> "$DESIRED_ICONS" << 'EOF'
xfce4-panel
xfce4-settings
Alacritty
alacritty
thunar
xfwm4
firefox
firefox-esr
geany
vlc
EOF
        sort -u -o "$DESIRED_ICONS" "$DESIRED_ICONS"
        info "Matching against $(wc -l < "$DESIRED_ICONS") installed app icon names..."

        KEEP_CATS=(places status actions categories devices mimetypes emblems panel preferences)
        APPS_COPIED=0
        for size_dir in "$ICON_BASE"/*/; do
            [[ -d "$size_dir" ]] || continue
            size_name=$(basename "$size_dir")
            [[ "$size_name" == "cursors" ]] && continue
            for cat in "${KEEP_CATS[@]}"; do
                [[ -d "${size_dir}${cat}" ]] && { mkdir -p "$LOCAL_ICON_DIR/$size_name"; cp -r "${size_dir}${cat}" "$LOCAL_ICON_DIR/$size_name/" 2>/dev/null; }
            done
            if [[ -d "${size_dir}apps" ]]; then
                mkdir -p "$LOCAL_ICON_DIR/$size_name/apps"
                while IFS= read -r -d '' f; do
                    base="$(basename "$f")"; name="${base%.*}"
                    if grep -qxF "$name" "$DESIRED_ICONS"; then
                        cp "$f" "$LOCAL_ICON_DIR/$size_name/apps/" 2>/dev/null
                        APPS_COPIED=$((APPS_COPIED + 1))
                    fi
                done < <(find "${size_dir}apps" -maxdepth 1 -type f -print0 2>/dev/null)
            fi
        done

        if [[ -f "$ICON_BASE/index.theme" ]]; then
            cp "$ICON_BASE/index.theme" "$LOCAL_ICON_DIR/index.theme"
            sed -i 's/^Inherits=.*/Inherits=Adwaita,hicolor/' "$LOCAL_ICON_DIR/index.theme"
            sed -i "s/^Name=.*/Name=Catppuccin-SE-Local/" "$LOCAL_ICON_DIR/index.theme"
        fi
        command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -f -t "$LOCAL_ICON_DIR" 2>/dev/null

        ok "Catppuccin-SE-Local built: $APPS_COPIED matched app icons."
        ok "Size: $(du -sh "$ICON_BASE" 2>/dev/null | cut -f1) (full, kept as fallback) → $(du -sh "$LOCAL_ICON_DIR" 2>/dev/null | cut -f1) (Local, active)."
        warn "Anything not in your installed-apps list falls back to Adwaita — rerun this script after installing new apps to refresh it."
        ACTIVE_ICON_THEME="Catppuccin-SE-Local"
    else
        err "Extraction failed."
    fi
else
    err "Icon download failed. Skipping icon theme."
fi

if [[ -d "$ICONS_DIR/$ACTIVE_ICON_THEME" ]]; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ACTIVE_ICON_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ACTIVE_ICON_THEME" 2>/dev/null || true
    ok "Active icon theme: $ACTIVE_ICON_THEME"
fi

# ══════════════════════════════════════════════════════════════
step "6/7  Panel styling (red/maroon accents, rounded corners)"
# ══════════════════════════════════════════════════════════════
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"
[[ -f "$GTK3_CSS" ]] && { cp "$GTK3_CSS" "${GTK3_CSS}.bak.$(date +%Y%m%d%H%M%S)"; info "Backed up existing gtk.css."; }
cat > "$GTK3_CSS" << EOF
/* XFCE panel override — Catppuccin Mocha, ThinkPad-red accent.
 * Loaded on top of the active GTK3 theme (Catppuccin Red/Black). */
.xfce4-panel {
    font-size: 14px;
    font-family: "JetBrainsMono Nerd Font Mono", "FiraCode Nerd Font", "Hack", monospace;
}
.xfce4-panel#XfcePanelWindow {
    border-radius: 16px;
    opacity: 0.85;
    border-bottom: 1px solid rgba(243, 139, 168, 0.35); /* faint red rim */
}
.xfce4-panel .tasklist .toggle:checked,
.tasklist button:checked {
    border-radius: 5px;
    background: ${CP_SURFACE1};
    border-bottom: 3px outset ${CP_RED};
}
.flat, .toggle {
    font-family: "JetBrainsMono Nerd Font Mono", "Hack", monospace;
    font-size: 14px;
    padding: 2px;
}
.flat:hover, .toggle:hover {
    background: ${CP_SURFACE1};
    color: ${CP_RED};
    border-radius: 4px;
}
.flat:checked, .toggle:checked {
    border-radius: 5px;
    border-bottom: 3px outset ${CP_MAROON};
    padding: 2px;
}
#xfce4-notification-plugin { color: #f5c2e7; padding: 2px; }
#sn-button {
    color: #bac2de;
    border-bottom: 3px outset #cba6f7;
    padding: 2px; margin-left: 3px; margin-right: 3px;
}
#sn-button:hover {
    background-image: -gtk-gradient(linear, left top, left bottom, from(#cba6f7), color-stop(0.5, darker(${CP_RED})), to(${CP_CRUST}));
    color: ${CP_CRUST}; border-bottom: none;
}
#actions-button {
    color: ${CP_RED};
    border-bottom: 3px solid ${CP_RED};
    padding: 2px; margin-left: 3px; margin-right: 3px;
}
#actions-button:hover {
    background-image: -gtk-gradient(linear, left top, left bottom, from(${CP_RED}), color-stop(0.7, darker(${CP_MAROON})), to(${CP_CRUST}));
    color: ${CP_CRUST}; border-bottom: none;
}
#pulseaudio-button {
    color: #f9e2af;
    border-bottom: 3px solid #f9e2af;
    padding: 2px; margin-left: 3px; margin-right: 3px;
}
#pulseaudio-button:hover {
    background-image: -gtk-gradient(linear, left top, left bottom, from(#f9e2af), color-stop(0.6, darker(#fab387)), to(${CP_CRUST}));
    color: ${CP_CRUST}; border-bottom: none;
}
#xfce4-power-manager-plugin {
    color: #a6e3a1;
    border-bottom: 3px solid #a6e3a1;
    padding: 2px; margin-left: 3px; margin-right: 3px;
}
#xfce4-power-manager-plugin:hover {
    background-image: -gtk-gradient(linear, left top, left bottom, from(#a6e3a1), color-stop(0.6, darker(#94e2d5)), to(${CP_CRUST}));
    color: ${CP_CRUST}; border-bottom: none;
}
EOF
ok "Panel CSS installed to $GTK3_CSS"

# ══════════════════════════════════════════════════════════════
step "7/7  Terminal — Alacritty (replaces xfce4-terminal)"
# ══════════════════════════════════════════════════════════════
# xfce4-terminal is removed outright, not kept as a fallback —
# Alacritty is THE terminal from here on.
sudo apt-get install -y alacritty || warn "Alacritty failed to install — xfce4-terminal will stay in place."

if command -v alacritty &>/dev/null; then
    mkdir -p "$HOME/.config/alacritty"

    # Alacritty's "what shell to launch" config key changed at 0.14:
    # [terminal].shell (0.14+) vs [shell] program (older). Detect
    # which this install actually understands instead of guessing.
    ALACRITTY_VERSION=$(dpkg-query -W -f='${Version}' alacritty 2>/dev/null || echo "0")
    SHELL_BLOCK="[terminal]
shell = \"/bin/bash\""
    if dpkg --compare-versions "$ALACRITTY_VERSION" lt "0.14.0" 2>/dev/null; then
        SHELL_BLOCK="[shell]
program = \"/bin/bash\""
    fi

    cat > "$HOME/.config/alacritty/alacritty.toml" << EOF
${SHELL_BLOCK}

[window]
opacity = 0.90
decorations = "full"

[font]
size = 11.0
normal = { family = "JetBrainsMono Nerd Font Mono", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font Mono", style = "Bold" }

[cursor]
style = { shape = "Block", blinking = "Off" }

[colors.primary]
background = "${CP_BASE}"
foreground = "${CP_TEXT}"

[colors.cursor]
text = "${CP_BASE}"
cursor = "${CP_RED}"

[colors.normal]
black = "${CP_SURFACE1}"
red = "${CP_RED}"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"

[colors.bright]
black = "${CP_SURFACE2}"
red = "${CP_RED}"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#a6adc8"
EOF
    ok "Alacritty configured (~/.config/alacritty/alacritty.toml)."

    # Make it THE terminal: x-terminal-emulator alternative + exo's
    # helper preference (Thunar's "Open Terminal Here", Whisker Menu,
    # keyboard shortcuts all resolve through this).
    ALACRITTY_BIN=$(command -v alacritty)
    if command -v update-alternatives &>/dev/null; then
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$ALACRITTY_BIN" 60 2>/dev/null || true
        sudo update-alternatives --set x-terminal-emulator "$ALACRITTY_BIN" 2>/dev/null || true
    fi
    HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
    mkdir -p "$HOME/.config/xfce4"
    [[ -f "$HELPERS_RC" ]] && grep -v '^TerminalEmulator=' "$HELPERS_RC" > "${HELPERS_RC}.tmp" 2>/dev/null && mv "${HELPERS_RC}.tmp" "$HELPERS_RC"
    echo "TerminalEmulator=alacritty" >> "$HELPERS_RC"
    ok "Alacritty set as the default terminal (Thunar, Whisker Menu, shortcuts all use it now)."

    if is_installed xfce4-terminal; then
        sudo apt-get purge -y xfce4-terminal 2>/dev/null \
            && ok "xfce4-terminal removed." \
            || warn "Couldn't remove xfce4-terminal (continuing — Alacritty is still the default)."
    fi
else
    warn "Alacritty isn't installed — leaving xfce4-terminal in place so you aren't left without a terminal."
fi

# ══════════════════════════════════════════════════════════════
step "Extras: picom, Whisker Menu, NumLock"
# ══════════════════════════════════════════════════════════════
# picom replaces xfwm4's built-in compositor — running both at once
# is the classic cause of flicker/tearing and doubles GPU wake-ups.
xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
if sudo apt-get install -y picom 2>/dev/null || sudo apt-get install -y compton 2>/dev/null; then
    COMPOSITOR_BIN="picom"; command -v picom &>/dev/null || COMPOSITOR_BIN="compton"
    PICOM_CONF="$HOME/.config/picom.conf"
    [[ -f "$PICOM_CONF" ]] && cp "$PICOM_CONF" "${PICOM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    cat > "$PICOM_CONF" << 'EOF'
# Deliberately minimal: fades only. No shadows/blur (that's what
# actually costs battery on a compositor, not fades).
backend = "xrender";
vsync = true;
fading = true;
fade-in-step = 0.05;
fade-out-step = 0.05;
fade-delta = 6;
no-fading-openclose = false;
no-fading-destroyed-argb = true;
shadow = false;
blur-method = "none";
corner-radius = 0;
unredir-if-possible = true;
detect-transient = true;
detect-client-opacity = true;
use-damage = true;
wintypes:
{
  tooltip = { fade = true; shadow = false; };
  dock = { shadow = false; };
  dnd = { shadow = false; };
  popup_menu = { fade = true; shadow = false; };
  dropdown_menu = { fade = true; shadow = false; };
};
EOF
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/picom.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Picom Compositor
Comment=Lightweight compositor — fades only, unredirects fullscreen windows to save battery
Exec=${COMPOSITOR_BIN} --config $PICOM_CONF
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
    pkill -x "$COMPOSITOR_BIN" 2>/dev/null; sleep 0.3
    ("$COMPOSITOR_BIN" --config "$PICOM_CONF" &>/dev/null & disown) || true
    ok "picom running (fades only, unredirects fullscreen for battery)."
else
    warn "Couldn't install picom/compton — re-enabling xfwm4's built-in compositor instead of leaving you with none at all."
    xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null || true
fi

if ask "Install Whisker Menu (Mint-style application menu, added alongside your current menu)?" "N"; then
    sudo apt-get install -y xfce4-whiskermenu-plugin \
        && xfce4-panel --add=whiskermenu 2>/dev/null \
        && ok "Whisker Menu added — right-click to reposition, remove the old Applications Menu if you don't want both." \
        || warn "Whisker Menu install/add failed — add it manually via Panel → Add New Items."
fi

if ask "Enable NumLock on login?" "N"; then
    sudo apt-get install -y numlockx && mkdir -p "$HOME/.config/autostart" && cat > "$HOME/.config/autostart/numlockx.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=NumLockX
Exec=numlockx on
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    ok "NumLock-on-login enabled."
fi

# ══════════════════════════════════════════════════════════════
step "Applying changes live"
# ══════════════════════════════════════════════════════════════
command -v xfce4-panel &>/dev/null && xfce4-panel -r 2>/dev/null
command -v xfwm4 &>/dev/null && (xfwm4 --replace &>/dev/null &)
command -v xfsettingsd &>/dev/null && { xfsettingsd --replace &>/dev/null & disown; }

echo
ok "Catppuccin ThinkRed theme applied — GTK/WM, cursors, icons, panel, picom, and Alacritty as the terminal."
echo -e "${C}If anything looks half-applied, a full logout/login always settles it.${Z}"
echo -e "${C}Re-run this script any time (e.g. after installing new apps) to refresh Catppuccin-SE-Local.${Z}"
