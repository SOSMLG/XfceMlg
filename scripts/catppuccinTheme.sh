#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  catppuccinTheme.sh — Chicago95's replacement: a modern,
#  ThinkPad-flavoured look for XFCE.
#
#  Catppuccin Mocha palette, "Black" variant + "Red" accent —
#  black chassis, red trackpoint nub. Installs/configures:
#    - GTK2/3 + xfwm4 theme  (Fausto-Korpsvart/Catppuccin-GTK-Theme)
#    - Cursor theme          (catppuccin/cursors, mocha-red)
#    - Icon theme            (ljmill/catppuccin-icons, "Catppuccin-SE")
#      + a lean "Catppuccin-SE-Local" variant containing only the
#        app icons you actually have installed (same trick as the
#        Papirus "Catppuccin-SE-Local" memory optimization: a slim
#        Inherits= chain so XFCE isn't indexing a 100+MB icon set)
#    - Panel gtk.css override with red/maroon accents
#    - (optional) Whisker Menu, compositor/shadows, numlock-on-boot
#
#  This retires the Chicago95 (Windows 95) theme this toolkit used
#  to offer — see chicagofier.sh's removal in the changelog.
#  Privilege: sudo (packages only; all theme files go in $HOME)
# ══════════════════════════════════════════════════════════════
set -uo pipefail
# NOTE: deliberately not using -e globally — this script talks to
# three separate upstream GitHub repos, any one of which can have a
# bad day. Every risky step below is wrapped in its own check so one
# failure degrades gracefully instead of aborting everything after it.

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

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

THEMES_DIR="$HOME/.themes"
ICONS_DIR="$HOME/.local/share/icons"
mkdir -p "$THEMES_DIR" "$ICONS_DIR" "$HOME/.icons" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

echo -e "\n${B}${W}══════ Catppuccin ThinkRed Theme (GTK + Icons + Cursors + Panel) ══════${Z}"

# ══════════════════════════════════════════════════════════════
step "1/8  Dependencies"
# ══════════════════════════════════════════════════════════════
info "Refreshing package lists..."
sudo apt-get update -qq

info "Installing theme-engine + fetch/extract tooling..."
sudo apt-get install -y \
    gtk2-engines-murrine gnome-themes-extra adwaita-icon-theme \
    git curl unzip tar sassc \
    xfce4-panel xfwm4 \
    || warn "Some packages failed to install (continuing — the theme may partially apply)."
ok "Dependencies installed."

# ══════════════════════════════════════════════════════════════
step "2/8  Retiring Chicago95 (if it was ever installed here)"
# ══════════════════════════════════════════════════════════════
# Best-effort cleanup so old Windows-95 leftovers don't fight the
# new theme. Safe no-ops if Chicago95 was never installed.
rm -rf "$HOME/.themes/Chicago95" "$HOME/.icons/Chicago95" \
       "$HOME/.Chicago95PlusFiles" "$HOME/.Chicago95Plus" "$HOME/.chicago95plus" \
       "$HOME/.local/share/xfce4/terminal/colorschemes/Chicago95.theme" \
       "$HOME/.local/share/applications/chicago95plus.desktop" \
       "$HOME/.config/autostart/chicago95-startup.desktop" 2>/dev/null
ok "Chicago95 remnants cleared (if any existed)."

# ══════════════════════════════════════════════════════════════
step "3/8  GTK + Window Manager theme (Catppuccin, Black/Red)"
# ══════════════════════════════════════════════════════════════
GTK_THEME_NAME=""
if ask "Install the Catppuccin GTK/xfwm4 theme (black background, red accent)?"; then
    if [[ -d "$WORK_DIR/Catppuccin-GTK-Theme" ]]; then
        rm -rf "$WORK_DIR/Catppuccin-GTK-Theme"
    fi
    info "Cloning Fausto-Korpsvart/Catppuccin-GTK-Theme..."
    if git clone --depth=1 https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git \
        "$WORK_DIR/Catppuccin-GTK-Theme" 2>/tmp/catppuccin-gtk-clone.log; then

        cd "$WORK_DIR/Catppuccin-GTK-Theme"

        # Upstream has moved install.sh before (it used to sit at the repo
        # root; as of the "installer orchestrator" rewrite it lives under
        # themes/install.sh instead). Find it wherever it actually is
        # rather than hardcoding a path — that hardcoded path is exactly
        # what broke this step previously ("No such file or directory").
        INSTALLER=$(find . -maxdepth 2 -iname "install.sh" 2>/dev/null | sort | head -1)

        if [[ -z "$INSTALLER" ]]; then
            err "Couldn't find install.sh anywhere in the cloned repo — upstream layout changed again."
            err "Browse https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme and install manually."
        else
            chmod +x "$INSTALLER"
            info "Building the Red accent / black background variant via $INSTALLER (this can take a minute)..."
            INSTALL_OK=0
            # Expected folder name under the CURRENT upstream naming scheme:
            # ${name}${accent}${mode}${size}${tweaks} -> Catppuccin-Red-Dark-Compact-BK
            EXPECTED_NAME="Catppuccin-Red-Dark-Compact-BK"

            # BATCH_MODE=true is load-bearing, not cosmetic: the current
            # installer ends its run with an interactive "Do you want to
            # apply Vague?" arrow-key menu (interactive_menu()). With no
            # TTY attached (piped into a log file, as we do here) that
            # menu blocks forever instead of failing — the script would
            # just hang. BATCH_MODE=true skips it; we apply the theme
            # ourselves via xfconf-query/gsettings below regardless, so
            # skipping the installer's own "apply now" step costs nothing.

            # 1) Current upstream CLI: accent/mode/tweaks-based flags.
            if BATCH_MODE=true timeout 300 "$INSTALLER" -d "$THEMES_DIR" -n Catppuccin -a red -m dark -s compact --tweaks black \
                >/tmp/catppuccin-gtk-install.log 2>&1; then
                INSTALL_OK=1
            # 2) Older upstream CLI this script originally targeted.
            elif BATCH_MODE=true timeout 300 "$INSTALLER" -t red -c black -s compact -d "$THEMES_DIR" -n Catppuccin \
                >>/tmp/catppuccin-gtk-install.log 2>&1; then
                INSTALL_OK=1
            else
                warn "Neither known install.sh call style worked (upstream CLI may have changed again since this script was written)."
                info "Falling back to a full default install — every flavour/accent gets built, we'll pick Red/Black out of it."
                if BATCH_MODE=true timeout 600 "$INSTALLER" -d "$THEMES_DIR" -n Catppuccin >>/tmp/catppuccin-gtk-install.log 2>&1 \
                    || BATCH_MODE=true timeout 600 "$INSTALLER" >>/tmp/catppuccin-gtk-install.log 2>&1; then
                    INSTALL_OK=1
                fi
            fi

            if [[ $INSTALL_OK -eq 1 ]]; then
                # Discover whatever the installer actually named the
                # Red/Black folder — check the exact expected name first,
                # then fall back to progressively looser pattern matches.
                if [[ -d "$THEMES_DIR/$EXPECTED_NAME" ]]; then
                    GTK_THEME_NAME="$EXPECTED_NAME"
                fi
                [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$THEMES_DIR" -maxdepth 1 -type d \
                    \( -iname "*red*dark*" -o -iname "*dark*red*" \) -printf '%f\n' 2>/dev/null | sort | head -1)
                [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$THEMES_DIR" -maxdepth 1 -type d \
                    \( -iname "*black*red*" -o -iname "*red*black*" \) -printf '%f\n' 2>/dev/null | head -1)
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
        err "Clone failed — check your network/DNS and rerun this step. Log: /tmp/catppuccin-gtk-clone.log"
    fi
else
    warn "Skipped GTK/WM theme install."
fi

# ══════════════════════════════════════════════════════════════
step "4/8  Cursor theme (Catppuccin Mocha, Red)"
# ══════════════════════════════════════════════════════════════
if ask "Install the Catppuccin cursor theme (Mocha flavour, Red accent)?"; then
    CURSOR_ZIP="$WORK_DIR/catppuccin-mocha-red-cursors.zip"
    CURSOR_URL="https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-red-cursors.zip"
    info "Downloading cursors..."
    if curl -fsSL -o "$CURSOR_ZIP" "$CURSOR_URL"; then
        if unzip -oq "$CURSOR_ZIP" -d "$HOME/.icons"; then
            CURSOR_NAME=$(find "$HOME/.icons" -maxdepth 1 -type d -iname "*mocha*red*cursor*" -printf '%f\n' | head -1)
            CURSOR_NAME=${CURSOR_NAME:-catppuccin-mocha-red-cursors}
            xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CURSOR_NAME" 2>/dev/null || true
            mkdir -p "$HOME/.icons/default"
            printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_NAME" > "$HOME/.icons/default/index.theme"
            ok "Cursor theme installed and applied: $CURSOR_NAME"
        else
            err "Couldn't unzip the cursor archive."
        fi
    else
        err "Cursor download failed (upstream may have renamed the release asset). Skipping."
    fi
else
    warn "Skipped cursor theme."
fi

# ══════════════════════════════════════════════════════════════
step "5/8  Icon theme (Catppuccin-SE, full set)"
# ══════════════════════════════════════════════════════════════
ICON_BASE="$ICONS_DIR/Catppuccin-SE"
if ask "Install the Catppuccin-SE icon set (ljmill/catppuccin-icons)?"; then
    info "Resolving latest release..."
    ICON_URL=$(curl -fsSL https://api.github.com/repos/ljmill/catppuccin-icons/releases/latest \
        | grep -oP '"browser_download_url":\s*"\K[^"]+Catppuccin-SE\.tar\.bz2' | head -1)
    if [[ -z "$ICON_URL" ]]; then
        warn "GitHub API lookup failed, using a fallback known-good release URL."
        ICON_URL="https://github.com/ljmill/catppuccin-icons/releases/download/v0.2.0/Catppuccin-SE.tar.bz2"
    fi
    ICON_TARBALL="$WORK_DIR/Catppuccin-SE.tar.bz2"
    if curl -fsSL --progress-bar -o "$ICON_TARBALL" "$ICON_URL"; then
        rm -rf "$ICON_BASE"
        mkdir -p "$ICONS_DIR"
        if tar -xjf "$ICON_TARBALL" -C "$ICONS_DIR"; then
            # Archive may extract as Catppuccin-SE/ already, or nest one level —
            # normalize either layout.
            if [[ ! -d "$ICON_BASE" ]]; then
                FOUND=$(find "$ICONS_DIR" -maxdepth 2 -type d -iname "Catppuccin-SE" | head -1)
                [[ -n "$FOUND" && "$FOUND" != "$ICON_BASE" ]] && mv "$FOUND" "$ICON_BASE"
            fi
            ok "Catppuccin-SE installed to $ICON_BASE ($(du -sh "$ICON_BASE" 2>/dev/null | cut -f1))"
        else
            err "Extraction failed."
        fi
    else
        err "Icon download failed. Skipping icon theme entirely."
    fi
else
    warn "Skipped icon theme install."
fi

# ══════════════════════════════════════════════════════════════
step "6/8  Lean local icon theme (Catppuccin-SE-Local)"
# ══════════════════════════════════════════════════════════════
# Same trick described in the brief: keep the small "UI chrome"
# categories (places/status/actions/categories/devices/mimetypes)
# wholesale, but only pull in *apps* icons for software you actually
# have installed, then trim Inherits= down to Adwaita+hicolor so
# XFCE isn't loading the full upstream icon index into memory.
ACTIVE_ICON_THEME="Catppuccin-SE"
if [[ -d "$ICON_BASE" ]] && ask "Build & use a lean 'Catppuccin-SE-Local' (smaller, faster to index)?"; then
    LOCAL_ICON_DIR="$ICONS_DIR/Catppuccin-SE-Local"
    rm -rf "$LOCAL_ICON_DIR"
    mkdir -p "$LOCAL_ICON_DIR"

    DESIRED_ICONS="$WORK_DIR/desired-icons.txt"
    grep -h '^Icon=' /usr/share/applications/*.desktop "$HOME/.local/share/applications"/*.desktop 2>/dev/null \
        | sed 's/^Icon=//' | sort -u > "$DESIRED_ICONS"
    # A handful of names XFCE itself wants regardless of what shows up
    # in the .desktop scan (panel plugins, Thunar, generic fallbacks).
    cat >> "$DESIRED_ICONS" << 'EOF'
xfce4-panel
xfce4-settings
xfce4-terminal
org.xfce.terminal
thunar
xfwm4
firefox
firefox-esr
geany
vlc
EOF
    sort -u -o "$DESIRED_ICONS" "$DESIRED_ICONS"
    WANTED_COUNT=$(wc -l < "$DESIRED_ICONS")
    info "Matching against $WANTED_COUNT installed app icon names..."

    KEEP_CATS=(places status actions categories devices mimetypes emblems panel preferences)
    APPS_COPIED=0
    for size_dir in "$ICON_BASE"/*/; do
        [[ -d "$size_dir" ]] || continue
        size_name=$(basename "$size_dir")
        [[ "$size_name" == "cursors" ]] && continue

        for cat in "${KEEP_CATS[@]}"; do
            if [[ -d "${size_dir}${cat}" ]]; then
                mkdir -p "$LOCAL_ICON_DIR/$size_name"
                cp -r "${size_dir}${cat}" "$LOCAL_ICON_DIR/$size_name/" 2>/dev/null
            fi
        done

        if [[ -d "${size_dir}apps" ]]; then
            mkdir -p "$LOCAL_ICON_DIR/$size_name/apps"
            while IFS= read -r -d '' f; do
                base="$(basename "$f")"
                name="${base%.*}"
                if grep -qxF "$name" "$DESIRED_ICONS"; then
                    cp "$f" "$LOCAL_ICON_DIR/$size_name/apps/" 2>/dev/null
                    APPS_COPIED=$((APPS_COPIED + 1))
                fi
            done < <(find "${size_dir}apps" -maxdepth 1 -type f -print0 2>/dev/null)
        fi
    done

    if [[ -f "$ICON_BASE/index.theme" ]]; then
        cp "$ICON_BASE/index.theme" "$LOCAL_ICON_DIR/index.theme"
        # This is the actual memory win: stop this theme from pulling
        # in the *entire* upstream inheritance chain (which is what
        # forces XFCE to index the full 100+MB parent theme too).
        sed -i 's/^Inherits=.*/Inherits=Adwaita,hicolor/' "$LOCAL_ICON_DIR/index.theme"
        sed -i "s/^Name=.*/Name=Catppuccin-SE-Local/" "$LOCAL_ICON_DIR/index.theme"
    fi

    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$LOCAL_ICON_DIR" 2>/dev/null || true
    fi

    OLD_SIZE=$(du -sh "$ICON_BASE" 2>/dev/null | cut -f1)
    NEW_SIZE=$(du -sh "$LOCAL_ICON_DIR" 2>/dev/null | cut -f1)
    ok "Catppuccin-SE-Local built: $APPS_COPIED matched app icons copied."
    ok "Size: $OLD_SIZE (full Catppuccin-SE, kept on disk as a fallback) → $NEW_SIZE (Local, active)."
    warn "Anything not in your installed-apps list falls back to Adwaita, not Catppuccin — install a new"
    warn "app later and it may look slightly out of place until you rerun this step."
    ACTIVE_ICON_THEME="Catppuccin-SE-Local"
fi

if [[ -d "$ICONS_DIR/$ACTIVE_ICON_THEME" ]]; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ACTIVE_ICON_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ACTIVE_ICON_THEME" 2>/dev/null || true
    ok "Active icon theme: $ACTIVE_ICON_THEME"
fi

# ══════════════════════════════════════════════════════════════
step "7/8  Panel styling (red/maroon accents, rounded corners)"
# ══════════════════════════════════════════════════════════════
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"
if ask "Install the red-accented xfce4-panel CSS override?"; then
    if [[ -f "$GTK3_CSS" ]]; then
        cp "$GTK3_CSS" "${GTK3_CSS}.bak.$(date +%Y%m%d%H%M%S)"
        info "Backed up existing gtk.css."
    fi
    cat > "$GTK3_CSS" << 'EOF'
/* ══════════════════════════════════════════════════════════════
 * XFCE panel override — Catppuccin Mocha, ThinkPad-red accent.
 * Generated by catppuccinTheme.sh. Loaded on top of whatever GTK3
 * theme is active (Catppuccin Black/Red), so it only needs to
 * carry the panel-specific tweaks, not a full theme.
 * Palette reference: Red #f38ba8, Maroon #eba0ac, Surface1 #45475a,
 * Crust #11111b, Green #a6e3a1, Yellow #f9e2af, Pink #f5c2e7,
 * Mauve #cba6f7.
 * ══════════════════════════════════════════════════════════════ */

.xfce4-panel {
    font-size: 14px;
    font-family: "JetBrainsMono Nerd Font Mono", "FiraCode Nerd Font", "Hack", monospace;
}

.xfce4-panel#XfcePanelWindow {
    border-radius: 16px;
    opacity: 0.85;
    border-bottom: 1px solid rgba(243, 139, 168, 0.35); /* faint red rim */
}

/* Active window in the tasklist — the "trackpoint" indicator */
.xfce4-panel .tasklist .toggle:checked,
.tasklist button:checked {
    border-radius: 5px;
    background: #313244;
    border-bottom: 3px outset #f38ba8; /* Red */
}

.flat,
.toggle {
    font-family: "JetBrainsMono Nerd Font Mono", "Hack", monospace;
    font-size: 14px;
    padding: 2px;
}

.flat:hover,
.toggle:hover {
    background: #45475a;
    color: #f38ba8; /* Red */
    border-bottom-left-radius: 4px;
    border-bottom-right-radius: 4px;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
}

.flat:checked,
.toggle:checked {
    border-radius: 5px;
    border-bottom: 3px outset #eba0ac; /* Maroon */
    padding: 2px;
}

/* Notifications */
#xfce4-notification-plugin {
    color: #f5c2e7; /* Pink */
    padding: 2px;
}

/* System tray */
#sn-button {
    color: #bac2de;
    border-bottom: 3px outset #cba6f7; /* Mauve */
    padding: 2px;
    margin-left: 3px;
    margin-right: 3px;
}
#sn-button:hover {
    background-image: -gtk-gradient
        (linear, left top, left bottom,
         from (#cba6f7),
         color-stop (0.5, darker (#f38ba8)),
         to (#11111b));
    color: #11111b;
    border-bottom: none;
}

/* Power/logout — the flagship red button */
#actions-button {
    color: #f38ba8; /* Red */
    border-bottom: 3px solid #f38ba8;
    padding: 2px;
    margin-left: 3px;
    margin-right: 3px;
}
#actions-button:hover {
    background-image: -gtk-gradient
        (linear, left top, left bottom,
         from (#f38ba8),
         color-stop (0.7, darker (#eba0ac)),
         to (#11111b));
    color: #11111b;
    border-bottom: none;
}

/* Volume */
#pulseaudio-button {
    color: #f9e2af; /* Yellow */
    padding: 2px;
    border-bottom: 3px solid #f9e2af;
    margin-left: 3px;
    margin-right: 3px;
}
#pulseaudio-button:hover {
    background-image: -gtk-gradient
        (linear, left top, left bottom,
         from (#f9e2af),
         color-stop (0.6, darker (#fab387)),
         to (#11111b));
    color: #11111b;
    border-bottom: none;
}

/* Battery */
#xfce4-power-manager-plugin {
    color: #a6e3a1; /* Green */
    padding: 2px;
    border-bottom: 3px solid #a6e3a1;
    margin-left: 3px;
    margin-right: 3px;
}
#xfce4-power-manager-plugin:hover {
    background-image: -gtk-gradient
        (linear, left top, left bottom,
         from (#a6e3a1),
         color-stop (0.6, darker (#94e2d5)),
         to (#11111b));
    color: #11111b;
    border-bottom: none;
}
EOF
    ok "Panel CSS installed to $GTK3_CSS"
else
    warn "Skipped panel CSS."
fi

# ══════════════════════════════════════════════════════════════
step "8/8  Optional Mint-style laptop touches"
# ══════════════════════════════════════════════════════════════
if ask "Enable the compositor (shadows, transparency, smoother workspace switching)?"; then
    xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/show_frame_shadow -s true 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/show_popup_shadow -s true 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/frame_opacity -s 95 2>/dev/null || true
    ok "Compositor enabled."
else
    warn "Compositor left as-is."
fi

if ask "Install Whisker Menu (Mint-style application menu, added alongside your current menu)?" "N"; then
    sudo apt-get install -y xfce4-whiskermenu-plugin \
        && xfce4-panel --add=whiskermenu 2>/dev/null \
        && ok "Whisker Menu installed and added to the panel — right-click it to reposition, and remove the old Applications Menu button if you don't want both." \
        || warn "Whisker Menu install/add failed — you can add it manually via Panel → Add New Items."
else
    warn "Skipped Whisker Menu."
fi

if ask "Enable NumLock on login (common laptop default)?" "N"; then
    sudo apt-get install -y numlockx \
        && mkdir -p "$HOME/.config/autostart" \
        && cat > "$HOME/.config/autostart/numlockx.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=NumLockX
Exec=numlockx on
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    ok "NumLock-on-login enabled."
else
    warn "Skipped NumLock autostart."
fi

# ══════════════════════════════════════════════════════════════
step "Applying changes live"
# ══════════════════════════════════════════════════════════════
if command -v xfce4-panel &>/dev/null; then
    xfce4-panel -r 2>/dev/null || true
fi
if command -v xfwm4 &>/dev/null; then
    (xfwm4 --replace &>/dev/null &) || true
fi
if command -v xfsettingsd &>/dev/null; then
    xfsettingsd --replace &>/dev/null &
    disown
fi

echo
ok "Catppuccin ThinkRed theme applied."
echo -e "${C}If anything looks half-applied, a full logout/login always settles it.${Z}"
echo -e "${C}Re-run this script any time (e.g. after installing new apps) to refresh Catppuccin-SE-Local.${Z}"
