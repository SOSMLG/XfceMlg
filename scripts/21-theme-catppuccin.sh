#!/usr/bin/env bash
# DEBSWAY_DESC: Catppuccin Red/Black GTK/xfwm4/icons + picom + xfce4-terminal
# DEBSWAY_DEFAULT: Y
#  21-theme-catppuccin.sh — the whole ThinkPad-red look, in one pass.
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
#    - Terminal: xfce4-terminal, Catppuccin Red terminalrc, set as THE
#      terminal — Alacritty is removed if present, not kept alongside
#
#  Since choosing to run this script already means "yes, do the
#  theme," most steps below just run — no per-step Y/n barrage.
#  The only prompts left are genuinely optional extras at the end.
#
#  This retires the Chicago95 (Windows 95) theme this toolkit used
#  to offer — see chicagofier.sh's removal in the changelog.
#  Privilege: priv() (doas-first, sudo fallback) (packages only; theme files go in $HOME)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
# NOTE: deliberately not using -e globally — this script talks to
# several upstream GitHub repos, any one of which can have a bad
# day. Every risky step is wrapped in its own check so one failure
# degrades gracefully instead of aborting everything after it.




WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

THEMES_DIR="$HOME/.themes"
ICONS_DIR="$HOME/.local/share/icons"
mkdir -p "$THEMES_DIR" "$ICONS_DIR" "$HOME/.icons" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

# Catppuccin Mocha palette used throughout this script.
CP_TEXT="#cdd6f4" CP_BASE="#1e1e2e" CP_RED="#f38ba8" CP_MAROON="#eba0ac"
CP_SURFACE1="#45475a" CP_SURFACE2="#585b70" CP_CRUST="#11111b"

apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/7  Dependencies"
priv apt-get install -y \
    gtk2-engines-murrine gnome-themes-extra adwaita-icon-theme \
    git curl unzip tar sassc xfce4-panel xfwm4 \
    || log_warn "Some packages failed to install (continuing — the theme may partially apply)."
log_ok "Dependencies installed."

log_head "2/7  Retiring Chicago95 (if it was ever installed here)"
rm -rf "$HOME/.themes/Chicago95" "$HOME/.icons/Chicago95" \
       "$HOME/.Chicago95PlusFiles" "$HOME/.Chicago95Plus" "$HOME/.chicago95plus" \
       "$HOME/.local/share/xfce4/terminal/colorschemes/Chicago95.theme" \
       "$HOME/.local/share/applications/chicago95plus.desktop" \
       "$HOME/.config/autostart/chicago95-startup.desktop" 2>/dev/null
log_ok "Chicago95 remnants cleared (if any existed)."

log_head "3/7  GTK + Window Manager theme (Catppuccin, Red/Black)"
GTK_THEME_NAME=""
rm -rf "$WORK_DIR/Catppuccin-GTK-Theme"
# Upstream pinning: set XFCE_GTK_REF to a tag/branch/SHA for a reproducible
# build (Butterbian pins every theme fetch the same way). Empty = current tip.
GTK_REF="${XFCE_GTK_REF:-}"
log_info "Cloning Fausto-Korpsvart/Catppuccin-GTK-Theme${GTK_REF:+ @ $GTK_REF}..."
if git clone --depth=1 ${GTK_REF:+--branch "$GTK_REF"} https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git \
    "$WORK_DIR/Catppuccin-GTK-Theme" 2>/tmp/catppuccin-gtk-clone.log; then
    mkdir -p "$HOME/.local/state/devuan-xfce-setup" 2>/dev/null || true
    # Record exactly what we built from — bug reports and rebuilds cite this.
    git -C "$WORK_DIR/Catppuccin-GTK-Theme" rev-parse HEAD 2>/dev/null > "$HOME/.local/state/devuan-xfce-setup/gtk-theme.sha" || true

    cd "$WORK_DIR/Catppuccin-GTK-Theme"
    # Installer's actual location has moved upstream before (root ->
    # themes/install.sh). Find it rather than hardcode a path.
    INSTALLER=$(find . -maxdepth 2 -iname "install.sh" 2>/dev/null | sort | head -1)

    if [[ -z "$INSTALLER" ]]; then
        log_err "Couldn't find install.sh in the cloned repo — upstream layout changed again."
        log_err "Browse https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme and install manually."
    else
        chmod +x "$INSTALLER"
        log_info "Building the Red/Black variant via $INSTALLER (a minute or two)..."
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
            log_warn "Neither known install.sh call style worked (upstream CLI may have changed again)."
            log_info "Falling back to a full default install — every flavour/accent gets built, we'll pick Red/Black out of it."
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
                log_ok "Installed as: $GTK_THEME_NAME"
                xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_THEME_NAME" 2>/dev/null || true
                xfconf-query -c xfwm4 -p /general/theme -s "$GTK_THEME_NAME" 2>/dev/null || true
                gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
            else
                log_warn "Theme installed but couldn't auto-detect its folder name under $THEMES_DIR."
                log_warn "Open Settings → Appearance and pick the Catppuccin Red/Dark variant manually."
            fi
        else
            log_err "Catppuccin-GTK-Theme install failed under every known CLI style. Log: /tmp/catppuccin-gtk-install.log"
        fi
    fi
    cd "$WORK_DIR"
else
    log_err "Clone failed — check your network/DNS and rerun this script. Log: /tmp/catppuccin-gtk-clone.log"
fi

log_head "4/7  Cursor theme (Catppuccin Mocha, Red)"
CURSOR_ZIP="$WORK_DIR/catppuccin-mocha-red-cursors.zip"
# Pinned cursor release (override with XFCE_CURSOR_TAG); falls back to the
# floating latest URL when the pinned asset 404s (upstream renames happen).
CURSOR_TAG="${XFCE_CURSOR_TAG:-v2.0.0}"
CURSOR_URL="https://github.com/catppuccin/cursors/releases/download/${CURSOR_TAG}/catppuccin-mocha-red-cursors.zip"
log_info "Downloading cursors (${CURSOR_TAG})..."
if ! curl -fsSL -o "$CURSOR_ZIP" "$CURSOR_URL"; then
    log_warn "Pinned cursor asset 404d — falling back to releases/latest."
    CURSOR_URL="https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-red-cursors.zip"
    curl -fsSL -o "$CURSOR_ZIP" "$CURSOR_URL" || true
fi
if [[ -s "$CURSOR_ZIP" ]] && unzip -oq "$CURSOR_ZIP" -d "$HOME/.icons"; then
    CURSOR_NAME=$(find "$HOME/.icons" -maxdepth 1 -type d -iname "*mocha*red*cursor*" -printf '%f\n' | head -1)
    CURSOR_NAME=${CURSOR_NAME:-catppuccin-mocha-red-cursors}
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CURSOR_NAME" 2>/dev/null || true
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_NAME" > "$HOME/.icons/default/index.theme"
    log_ok "Cursor theme installed and applied: $CURSOR_NAME"
else
    log_err "Cursor download/extract failed (upstream may have renamed the release asset). Skipping."
fi

log_head "5/7  Icon theme (Catppuccin-SE, full set + lean local variant)"
ICON_BASE="$ICONS_DIR/Catppuccin-SE"
ACTIVE_ICON_THEME="Catppuccin-SE"
log_info "Resolving latest ljmill/catppuccin-icons release..."
ICON_URL=$(curl -fsSL https://api.github.com/repos/ljmill/catppuccin-icons/releases/latest \
    | grep -oP '"browser_download_url":\s*"\K[^"]+Catppuccin-SE\.tar\.bz2' | head -1)
[[ -z "$ICON_URL" ]] && { log_warn "GitHub API lookup failed, using a fallback known-good release URL."; \
    ICON_URL="https://github.com/ljmill/catppuccin-icons/releases/download/v0.2.0/Catppuccin-SE.tar.bz2"; }

ICON_TARBALL="$WORK_DIR/Catppuccin-SE.tar.bz2"
if curl -fsSL --progress-bar -o "$ICON_TARBALL" "$ICON_URL"; then
    rm -rf "$ICON_BASE"
    if tar -xjf "$ICON_TARBALL" -C "$ICONS_DIR"; then
        if [[ ! -d "$ICON_BASE" ]]; then
            FOUND=$(find "$ICONS_DIR" -maxdepth 2 -type d -iname "Catppuccin-SE" | head -1)
            [[ -n "$FOUND" && "$FOUND" != "$ICON_BASE" ]] && mv "$FOUND" "$ICON_BASE"
        fi
        log_ok "Catppuccin-SE installed to $ICON_BASE ($(du -sh "$ICON_BASE" 2>/dev/null | cut -f1))"

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
xfce4-terminal
thunar
xfwm4
firefox
firefox-esr
vscodium
codium
vlc
EOF
        sort -u -o "$DESIRED_ICONS" "$DESIRED_ICONS"
        log_info "Matching against $(wc -l < "$DESIRED_ICONS") installed app icon names..."

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

        # Catppuccin-SE ships its folders/sidebar-symbolic icons with a
        # FIXED Lavender/Blue accent baked directly into the SVGs — not
        # user-selectable, and not Red. That's why "places" being copied
        # above doesn't actually make Thunar look themed: the folder
        # icons exist, they're just the wrong color. Verified by
        # downloading the real release and grep'ing every SVG for hex
        # codes rather than guessing: Lavender #b4befe dominates the
        # generic/undifferentiated folder icons (258 hits in one release),
        # a stray #89b4fa Blue shows up on plain folder.svg, and symbolic
        # icons (Thunar's sidebar/bookmarks) are almost entirely #80aaff/
        # #4285f4. Recolor just those four to Red — deliberately leaving
        # Pink/Green/Mauve/Yellow alone, since those are intentionally
        # used to differentiate specific folder types (Pictures, Git
        # repos, etc.) and flattening them to all-Red would be a
        # regression, not an improvement.
        log_info "Recoloring the pack's default Lavender/Blue accent to Red (folders + symbolic icons)..."
        RECOLOR_COUNT=0
        while IFS= read -r -d '' svg; do
            if grep -qE '#(b4befe|89b4fa|80aaff|4285f4)' "$svg" 2>/dev/null; then
                sed -i -E 's/#[bB]4[bB][eE][fF][eE]/#f38ba8/g; s/#89[bB]4[fF][aA]/#f38ba8/g; s/#80[aA][aA][fF][fF]/#f38ba8/g; s/#4285[fF]4/#f38ba8/g' "$svg"
                RECOLOR_COUNT=$((RECOLOR_COUNT + 1))
            fi
        done < <(find "$LOCAL_ICON_DIR" -iname "*.svg" -print0 2>/dev/null)
        log_ok "Recolored $RECOLOR_COUNT icon files (folders, sidebar/status icons) to Red."

        command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -f -t "$LOCAL_ICON_DIR" 2>/dev/null

        log_ok "Catppuccin-SE-Local built: $APPS_COPIED matched app icons."
        log_ok "Size: $(du -sh "$ICON_BASE" 2>/dev/null | cut -f1) (full, kept as fallback) → $(du -sh "$LOCAL_ICON_DIR" 2>/dev/null | cut -f1) (Local, active)."
        log_warn "Anything not in your installed-apps list falls back to Adwaita — rerun this script after installing new apps to refresh it."
        ACTIVE_ICON_THEME="Catppuccin-SE-Local"
    else
        log_err "Extraction failed."
    fi
else
    log_err "Icon download failed. Skipping icon theme."
fi

if [[ -d "$ICONS_DIR/$ACTIVE_ICON_THEME" ]]; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ACTIVE_ICON_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ACTIVE_ICON_THEME" 2>/dev/null || true
    log_ok "Active icon theme: $ACTIVE_ICON_THEME"
fi

log_head "6/7  Panel styling (red/maroon accents, square)"
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"
[[ -f "$GTK3_CSS" ]] && { cp "$GTK3_CSS" "${GTK3_CSS}.bak.$(date +%Y%m%d%H%M%S)"; log_info "Backed up existing gtk.css."; }
cat > "$GTK3_CSS" << EOF
/* XFCE panel override — Catppuccin Mocha, ThinkPad-red accent.
 * Square everywhere (border-radius 0) to match picom corner-radius 0.
 * Loaded on top of the active GTK3 theme (Catppuccin Red/Black).
 * NOTE: panel transparency comes from xfconf background-alpha, NOT CSS
 * opacity (CSS opacity would also fade the text/icons). */
.xfce4-panel {
    font-size: 14px;
    font-family: "JetBrainsMono Nerd Font Mono", "FiraCode Nerd Font", "Hack", monospace;
}
.xfce4-panel#XfcePanelWindow {
    border-radius: 0;
    border-bottom: 1px solid rgba(243, 139, 168, 0.35); /* faint red rim */
}
.xfce4-panel .tasklist .toggle:checked,
.tasklist button:checked {
    border-radius: 0;
    background: ${CP_SURFACE1};
    border-bottom: 3px outset ${CP_RED};
}
.flat, .toggle {
    font-family: "JetBrainsMono Nerd Font Mono", "Hack", monospace;
    font-size: 14px;
    padding: 2px;
    border-radius: 0;
}
.flat:hover, .toggle:hover {
    background: ${CP_SURFACE1};
    color: ${CP_RED};
    border-radius: 0;
}
.flat:checked, .toggle:checked {
    border-radius: 0;
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
log_ok "Panel CSS installed to $GTK3_CSS"

log_head "7/7  Terminal — xfce4-terminal (XFCE-native, Catppuccin Red)"
# xfce4-terminal is X11-native and part of the lean core (10-*), so it
# stays THE terminal. Alacritty (GPU/Rust, Wayland-oriented) is removed
# when found — it buys nothing here that a themed xfce4-terminal lacks.
install_pkgs "xfce4-terminal" xfce4-terminal

TERM_DIR="$HOME/.config/xfce4/terminal"
mkdir -p "$TERM_DIR"
if [[ -f "$TERM_DIR/terminalrc" ]]; then
    cp "$TERM_DIR/terminalrc" "$TERM_DIR/terminalrc.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backed up existing terminalrc."
fi
cat > "$TERM_DIR/terminalrc" << EOF
[Configuration]
FontName=JetBrainsMono Nerd Font Mono 11
ColorBackground=${CP_BASE}
ColorForeground=${CP_TEXT}
ColorCursor=${CP_RED}
ColorPalette=${CP_SURFACE1};${CP_RED};#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#bac2de;${CP_SURFACE2};${CP_RED};#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#a6adc8
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscMenubarDefault=FALSE
MiscToolbarDefault=FALSE
ScrollingBar=TERMINAL_SCROLLBAR_NONE
ScrollingLines=10000
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.92
EOF
log_ok "xfce4-terminal themed Catppuccin Red ($TERM_DIR/terminalrc)."

# Make it THE terminal: x-terminal-emulator alternative + exo's
# helper preference (Thunar's "Open Terminal Here", Whisker Menu,
# keyboard shortcuts all resolve through this).
XTERM_BIN=$(command -v xfce4-terminal)
if [[ -n "$XTERM_BIN" ]] && command -v update-alternatives &>/dev/null; then
    priv update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$XTERM_BIN" 60 2>/dev/null || true
    priv update-alternatives --set x-terminal-emulator "$XTERM_BIN" 2>/dev/null || true
fi
HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
mkdir -p "$HOME/.config/xfce4"
[[ -f "$HELPERS_RC" ]] && grep -v '^TerminalEmulator=' "$HELPERS_RC" > "${HELPERS_RC}.tmp" 2>/dev/null && mv "${HELPERS_RC}.tmp" "$HELPERS_RC"
echo "TerminalEmulator=xfce4-terminal" >> "$HELPERS_RC"
log_ok "xfce4-terminal set as the default terminal (Thunar, Whisker Menu, shortcuts all use it now)."

if is_installed alacritty; then
    priv apt-get purge -y alacritty 2>/dev/null \
        && log_ok "Alacritty removed (xfce4-terminal is the terminal now)." \
        || log_warn "Couldn't remove Alacritty (continuing — xfce4-terminal is still the default)."
fi

log_head "Extras: picom (with animations), Whisker Menu, NumLock, Conky, Plank, panel graphs"
# picom replaces xfwm4's built-in compositor — running both at once
# is the classic cause of flicker/tearing and doubles GPU wake-ups.
xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true

# Honesty check up front: Debian's packaged `picom` is almost always
# mainline yshui/picom, which historically has NO animation support at
# all (open/close/workspace-switch transitions like Hyprland/omarchy) —
# that only exists in forks, or very recent mainline builds (merged to
# the "next" branch, not yet what apt ships). Writing animation config
# keys is harmless either way (an old picom just ignores keys it
# doesn't recognize), but claiming it'll definitely animate would be
# overpromising, so this checks for real support after installing
# rather than assuming.
PICOM_HAS_ANIMATIONS=0
PICOM_READY=0
# Prefer an already-built animated fork (re-runs must not rebuild it).
if [[ -x /usr/local/bin/picom ]] && /usr/local/bin/picom --help 2>&1 | grep -qi "animation"; then
    COMPOSITOR_BIN="/usr/local/bin/picom"
    PICOM_HAS_ANIMATIONS=1
    PICOM_READY=1
    log_ok "Animated picom fork already present (/usr/local/bin/picom) — reusing it, no rebuild."
    priv apt-get install -y picom 2>/dev/null || true
elif priv apt-get install -y picom 2>/dev/null || priv apt-get install -y compton 2>/dev/null; then
    COMPOSITOR_BIN="picom"; command -v picom &>/dev/null || COMPOSITOR_BIN="compton"
    PICOM_READY=1
fi

if [[ $PICOM_READY -eq 0 ]]; then
    log_warn "Couldn't install picom/compton — re-enabling xfwm4's built-in compositor instead of leaving you with none at all."
    xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null || true
else
    if [[ $PICOM_HAS_ANIMATIONS -eq 0 ]]; then
        if "$COMPOSITOR_BIN" --help 2>&1 | grep -qi "animation"; then
            PICOM_HAS_ANIMATIONS=1
            log_ok "This picom build supports animations natively."
        else
            log_warn "This picom build (Debian's packaged mainline) has no animation support —"
            log_warn "the config below includes animation keys anyway; they're just inert until"
            log_warn "you're running a build that understands them (see the fork build below)."
        fi
    fi

    PICOM_CONF="$HOME/.config/picom.conf"
    [[ -f "$PICOM_CONF" ]] && cp "$PICOM_CONF" "${PICOM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    cat > "$PICOM_CONF" << 'EOF'
# Square, subtle, productive: fades + fork animations, no shadows/blur
# (shadows/blur are what actually costs battery — fades/opacity don't).
# Square corners throughout to match the panel theme (corner-radius 0).
backend = "glx";
vsync = true;
fading = true;
fade-in-step = 0.04;
fade-out-step = 0.04;
fade-delta = 8;
fade-exclude = [ "class_g = 'firefox' && window_type = 'fullscreen'" ];
no-fading-openclose = false;
no-fading-destroyed-argb = true;
shadow = false;
blur-method = "none";
# --- Square: no rounded corners anywhere ---
corner-radius = 0;
round-borders = 0;
round-borders-exclude = [ "window_type = 'dock'", "window_type = 'desktop'" ];
# --- Lightweight focus cue: inactive windows slightly transparent ---
active-opacity = 1.0;
inactive-opacity = 0.95;
frame-opacity = 1.0;
inactive-opacity-override = false;
opacity-rule = [
  "100:class_g = 'firefox' && window_type = 'fullscreen'",
  "100:class_g = 'vlc' && window_type = 'fullscreen'",
  "95:class_g = 'Xfce4-terminal'"
];
opacity-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'firefox' && window_type = 'fullscreen'"
];
unredir-if-possible = true;
unredir-if-possible-exclude = [ "window_type = 'dock'" ];
detect-transient = true;
detect-client-opacity = true;
use-damage = true;
xrender-sync-fence = true;

# --- Animation keys (fork-only — see PICOM_HAS_ANIMATIONS check above) ---
# Hyprland/omarchy-style: windows zoom in on open, slide out on close,
# and the whole screen slides when you switch workspaces.
animations = true;
animation-stiffness = 300;
animation-dampening = 26;
animation-clamping = true;
animation-mass = 1;
animation-for-open-window = "zoom";
animation-for-unmap-window = "zoom";
animation-for-transient-window = "slide-down";
animation-for-workspace-switch-in = "slide-right";
animation-for-workspace-switch-out = "slide-left";

wintypes:
{
  tooltip = { fade = true; shadow = false; };
  dock = { shadow = false; };
  dnd = { shadow = false; };
  popup_menu = { fade = true; shadow = false; };
  dropdown_menu = { fade = true; shadow = false; };
};
EOF
    # Re-resolve the binary at write time so re-runs heal a stale
    # compton-vs-picom or apt-vs-/usr/local fork mismatch.
    if [[ -x /usr/local/bin/picom ]]; then
        COMPOSITOR_BIN="/usr/local/bin/picom"
    elif command -v picom &>/dev/null; then
        COMPOSITOR_BIN="picom"
    else
        COMPOSITOR_BIN="compton"
    fi
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/picom.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Picom Compositor
Comment=Square fades + animations, unredirects fullscreen windows to save battery
Exec=${COMPOSITOR_BIN} --config $PICOM_CONF
StartupNotify=false
Terminal=false
X-GNOME-Autostart-enabled=true
OnlyShowIn=XFCE;
NoDisplay=true
EOF
    # pkill matches the process name, never a full path.
    pkill -x picom 2>/dev/null; pkill -x compton 2>/dev/null; sleep 0.3
    ("$COMPOSITOR_BIN" --config "$PICOM_CONF" &>/dev/null & disown) || true
    log_ok "picom running ($COMPOSITOR_BIN)."

    # Requested: animations on. Stock apt picom ignores the animation
    # keys above, so build the fork when needed. Under --full this
    # auto-runs (ask() forces Yes); re-runs skip when the fork exists.
    if [[ $PICOM_HAS_ANIMATIONS -eq 0 ]] && ask "Build a picom fork WITH real animation support from source (takes a few minutes)?" "N"; then
        log_info "Installing build dependencies (this is the slow part)..."
        priv apt-get install -y meson ninja-build git cmake \
            libconfig-dev libdbus-1-dev libegl-dev libev-dev libgl-dev libepoxy-dev \
            libpcre2-dev libpixman-1-dev libx11-xcb-dev libxcb1-dev libxcb-composite0-dev \
            libxcb-damage0-dev libxcb-glx0-dev libxcb-image0-dev libxcb-present-dev \
            libxcb-randr0-dev libxcb-render0-dev libxcb-render-util0-dev libxcb-shape0-dev \
            libxcb-util-dev libxcb-xfixes0-dev libxext-dev uthash-dev \
            || log_warn "Some build deps failed — the build below may fail too, that's expected if so."

        PICOM_BUILD_DIR="$WORK_DIR/picom-animations"
        if git clone --depth=1 --recursive https://github.com/ornfelt/picom-animations.git "$PICOM_BUILD_DIR" 2>/tmp/picom-fork-clone.log; then
            (
                cd "$PICOM_BUILD_DIR" \
                    && meson setup --buildtype=release build \
                    && ninja -C build
            ) > /tmp/picom-fork-build.log 2>&1
            if [[ -f "$PICOM_BUILD_DIR/build/src/picom" ]]; then
                priv install -Dm755 "$PICOM_BUILD_DIR/build/src/picom" /usr/local/bin/picom
                pkill -x picom 2>/dev/null; pkill -x compton 2>/dev/null; sleep 0.3
                COMPOSITOR_BIN="/usr/local/bin/picom"
                sed -i "s|Exec=.*|Exec=${COMPOSITOR_BIN} --config $PICOM_CONF|" "$HOME/.config/autostart/picom.desktop"
                ("$COMPOSITOR_BIN" --config "$PICOM_CONF" &>/dev/null & disown) || true
                log_ok "Animated picom built and running (/usr/local/bin/picom — apt's plain picom is untouched,"
                log_ok "this just takes priority via PATH order / the autostart entry pointing at it directly)."
            else
                log_err "Build failed — check /tmp/picom-fork-build.log. Falling back to the plain picom already running above."
            fi
        else
            log_err "Clone failed — check your network/DNS. Log: /tmp/picom-fork-clone.log. Falling back to plain picom."
        fi
    fi
fi

# --- Curated single-panel helpers (idempotent, no duplicates) ---
# Every xfce4-panel --add used to append a duplicate on each re-run.
# panel_has_plugin checks xfconf first; ensure_panel_plugin only adds
# when missing. Curated set: whiskermenu (productive launcher) is part
# of the single-panel layout; conky/plank/graphs stay manual opt-in.
panel_has_plugin() {  # panel_has_plugin <type> — e.g. whiskermenu, clipman
    local want="$1" prop val
    command -v xfconf-query &>/dev/null || return 1
    while IFS= read -r prop; do
        [[ "$prop" =~ /plugins/plugin-[0-9]+$ ]] || continue
        val="$(xfconf-query -c xfce4-panel -p "$prop" 2>/dev/null || true)"
        [[ "$val" == "$want" ]] && return 0
    done < <(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null)
    return 1
}

ensure_panel_plugin() {  # ensure_panel_plugin <apt-pkg> <add-name> <type>
    local pkg="$1" add="$2" type="$3"
    install_pkgs "$pkg" "$pkg" || log_warn "Could not install $pkg (continuing)."
    if panel_has_plugin "$type"; then
        log_ok "$type already on the panel — skipping add (no duplicate)."
        return 0
    fi
    if command -v xfce4-panel &>/dev/null && xfce4-panel --add="$add" 2>/dev/null; then
        log_ok "$type added to the panel."
    else
        log_warn "Couldn't auto-add $type — add it manually via Panel → Add New Items."
    fi
}

curate_panel_geometry() {
    # Single top-bar look: 30px tall, full width, solid background with
    # 85/255 alpha (transparency without fading text), locked. All
    # best-effort (headless re-runs just warn) and never fatal.
    command -v xfconf-query &>/dev/null || return 0
    local panel_prop="/panels/panel-1"
    xfconf-query -c xfce4-panel -p "$panel_prop/size" -n -t int -s 30 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "$panel_prop/length" -n -t uint -s 100 2>/dev/null \
        || xfconf-query -c xfce4-panel -p "$panel_prop/length" -n -t int -s 100 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "$panel_prop/length-adjust" -n -t bool -s false 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "$panel_prop/background-style" -n -t uint -s 1 2>/dev/null \
        || xfconf-query -c xfce4-panel -p "$panel_prop/background-style" -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "$panel_prop/background-alpha" -n -t uint -s 85 2>/dev/null \
        || xfconf-query -c xfce4-panel -p "$panel_prop/background-alpha" -n -t int -s 85 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "$panel_prop/position-locked" -n -t bool -s true 2>/dev/null || true
    # Tasklist: flat square buttons with labels (productive window list).
    local prop pid
    while IFS= read -r prop; do
        [[ "$prop" =~ /plugins/plugin-([0-9]+)$ ]] || continue
        pid="${BASH_REMATCH[1]}"
        [[ "$(xfconf-query -c xfce4-panel -p "$prop" 2>/dev/null || true)" == "tasklist" ]] || continue
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid/show-labels" -n -t bool -s true 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid/flat-buttons" -n -t bool -s true 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid/grouping" -n -t uint -s 1 2>/dev/null \
            || xfconf-query -c xfce4-panel -p "/plugins/plugin-$pid/grouping" -n -t int -s 1 2>/dev/null || true
    done < <(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null)
}

if ask "Install Whisker Menu (productive app launcher, part of the curated single-panel layout)?"; then
    ensure_panel_plugin "xfce4-whiskermenu-plugin" "whiskermenu" "whiskermenu"
    log_info "Whisker sits alongside your current menu — right-click the panel to remove the old Applications Menu if you don't want both."
    curate_panel_geometry
fi

if ask "Enable NumLock on login?"; then
    priv apt-get install -y numlockx && mkdir -p "$HOME/.config/autostart" && cat > "$HOME/.config/autostart/numlockx.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=NumLockX
Exec=numlockx on
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    log_ok "NumLock-on-login enabled."
fi

# --- Community-favorite additions (r/unixporn / r/xfce staples) ---
# Manual opt-in only: excluded from --full auto-Yes (single-panel +
# lightweight direction — extra dock/widget/polling processes stay off
# unless explicitly chosen). ask_no_full honors the default N even on FULL.
if ask_no_full "Install Conky (Catppuccin Red-themed system-info widget on the desktop)?" "N"; then
    priv apt-get install -y conky-all || log_warn "Conky failed to install."
    if is_installed conky-all || command -v conky &>/dev/null; then
        mkdir -p "$HOME/.config/conky"
        CONKY_CONF="$HOME/.config/conky/conky.conf"
        [[ -f "$CONKY_CONF" ]] && cp "$CONKY_CONF" "${CONKY_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        cat > "$CONKY_CONF" << 'EOF'
conky.config = {
    alignment = 'top_right',
    background = false,
    border_width = 0,
    cpu_avg_samples = 2,
    net_avg_samples = 2,
    default_color = 'cdd6f4',
    use_xft = true,
    font = 'JetBrainsMono Nerd Font Mono:size=10',
    gap_x = 24,
    gap_y = 48,
    minimum_width = 230,
    no_buffers = true,
    own_window = true,
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 170,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    update_interval = 2.0,
    double_buffer = true,
};

conky.text = [[
${color f38ba8}${font JetBrainsMono Nerd Font Mono:bold:size=12}${nodename}${font}${color}
${color bac2de}${hr 1}${color}
${color bac2de}Uptime:${color} $uptime
${color bac2de}Kernel:${color} $kernel
${color bac2de}${hr 1}${color}
${color f38ba8}CPU${color} ${cpu cpu0}% ${cpubar cpu0 8,140}
${color f38ba8}RAM${color} $mem / $memmax ${membar 8,140}
${color f38ba8}Disk /${color} ${fs_used /} / ${fs_size /} ${fs_bar 8,140 /}
${color bac2de}${hr 1}${color}
${color bac2de}Down:${color} ${downspeed} ${color bac2de}Up:${color} ${upspeed}
]];
EOF
        mkdir -p "$HOME/.config/autostart"
        cat > "$HOME/.config/autostart/conky.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Conky
Exec=conky -c $CONKY_CONF
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        pkill -x conky 2>/dev/null; sleep 0.3
        (conky -c "$CONKY_CONF" &>/dev/null & disown) || true
        log_ok "Conky running (Catppuccin Red). Config: $CONKY_CONF — edit and re-run 'conky -c' to tweak it live."
    fi
fi

if ask_no_full "Install Plank (elegant macOS-style dock, a common pairing with a slimmer panel)?" "N"; then
    priv apt-get install -y plank || log_warn "Plank failed to install."
    if command -v plank &>/dev/null; then
        mkdir -p "$HOME/.config/autostart"
        cat > "$HOME/.config/autostart/plank.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Exec=plank
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        pkill -x plank 2>/dev/null; sleep 0.3
        (plank &>/dev/null & disown) || true
        log_ok "Plank running with its defaults — right-click it, or run 'plank --preferences', to theme/resize it."
        log_warn "Plank and the panel's own taskbar will both show running apps unless you trim one — that's"
        log_warn "a matter of taste, so nothing here removes the panel taskbar for you."
    fi
fi

# Polling graph plugins cost wake-ups; manual opt-in only (not --full).
if ask_no_full "Add CPU + network graph plugins to the panel (cpugraph, netload)?" "N"; then
    install_pkgs "Panel graphs" xfce4-cpugraph-plugin xfce4-netload-plugin || true
    ensure_panel_plugin "xfce4-cpugraph-plugin" "cpugraph" "cpugraph"
    ensure_panel_plugin "xfce4-netload-plugin" "netload" "netload"
    log_ok "cpugraph + netload ensured on the panel — right-click either to reposition or restyle."
fi

log_head "System-wide GTK defaults (/etc, for root apps + greeter fallback)"
# Butterbian technique: per-user xfconf theming leaves root apps (Thunar-as-root,
# gparted) and any session without our xsettings on stock Adwaita. System-wide
# defaults close that seam. Package-owned files are never touched — these two
# paths are the documented admin-override locations.
if [[ -n "$GTK_THEME_NAME" ]]; then
    priv mkdir -p /etc/gtk-3.0 /etc/gtk-2.0
    {
        echo "[Settings]"
        echo "gtk-theme-name=$GTK_THEME_NAME"
        echo "gtk-icon-theme-name=$ACTIVE_ICON_THEME"
        echo "gtk-font-name=Sans 10"
        echo "gtk-cursor-theme-name=${CURSOR_NAME:-Adwaita}"
        echo "gtk-xft-antialias=1"
        echo "gtk-xft-hinting=1"
        echo "gtk-xft-hintstyle=hintslight"
    } | priv tee /etc/gtk-3.0/settings.ini > /dev/null
    {
        echo "gtk-theme-name=\"$GTK_THEME_NAME\""
        echo "gtk-icon-theme-name=\"$ACTIVE_ICON_THEME\""
        echo "gtk-font-name=\"Sans 10\""
        echo "gtk-cursor-theme-name=\"${CURSOR_NAME:-Adwaita}\""
    } | priv tee /etc/gtk-2.0/gtkrc > /dev/null
    log_ok "System-wide GTK defaults point at $GTK_THEME_NAME / $ACTIVE_ICON_THEME."
else
    log_warn "No resolved GTK theme name — skipping system-wide defaults."
fi

log_head "Applying changes live"
command -v xfce4-panel &>/dev/null && xfce4-panel -r 2>/dev/null
command -v xfwm4 &>/dev/null && (xfwm4 --replace &>/dev/null &)
command -v xfsettingsd &>/dev/null && { xfsettingsd --replace &>/dev/null & disown; }

echo
log_ok "Catppuccin ThinkRed theme applied — GTK/WM, cursors, icons, panel, picom, and xfce4-terminal."
echo -e "If anything looks half-applied, a full logout/login always settles it."
echo -e "Re-run this script any time (e.g. after installing new apps) to refresh Catppuccin-SE-Local."
