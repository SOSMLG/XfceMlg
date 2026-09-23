#!/usr/bin/env bash
# DEBSWAY_DESC: Darkmatter GTK/xfwm4 theme + Zafiro icons + xfwm4 compositor + panel rice
# DEBSWAY_DEFAULT: Y
#  21-theme.sh — the whole dark look, one pass, no theme engine.
#
#  Applies the bundled Darkmatter theme (near-black #121113 with a red
#  accent #e75353, bundled engine-free under configs/themes/) in one pass:
#    - Deploy Darkmatter (+ hdpi/xhdpi) to /usr/share/themes; remove the
#      old Tokyo Night themes; set GTK2/3 + xfwm4 theme to Darkmatter
#    - Deploy bundled Zafiro icons (dark) to /usr/share/icons
#    - Alacritty as THE terminal + Darkmatter alacritty.toml from
#      configs/alacritty/
#    - Compositor: xfwm4 built-in (use_compositing on — subtle shadows,
#      inactive dim, move/resize fade) — the xfwm4.xml seed handles it
#    - Panel + window-manager seed from configs/xfce4/ (item layout,
#      clock/title fonts, decorations) written to xfconf; panel re-runs
#    - Wallpapers deployed + live backdrop set
#    - picker.colors for the Python menu/update-gui widgets
#    - Optional dunst + rofi configs from the Darkmatter repo
#
#  The old palette engine (themes/ + theme-apply.sh + xfce-theme-set/list)
#  is gone — the look is fixed, not swappable.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root


apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/9  Dependencies"
install_pkgs "Theme deps" \
    gtk2-engines-murrine gnome-themes-extra adwaita-icon-theme \
    alacritty numlockx flameshot \
    xfce4-whiskermenu-plugin xfce4-docklike-plugin \
    xfce4-datetime-plugin \
    acpi lm-sensors gawk
log_ok "Dependencies installed."

log_head "2/9  Deploy bundled Darkmatter themes + remove the old Tokyo Night set"
REPO_THEMES="$SCRIPT_DIR/../configs/themes"
SYS_THEMES="/usr/share/themes"
priv mkdir -p "$SYS_THEMES"
for OLD_THEME in "Tokyonight-Dark-BL" "Tokyo Night - Bordered" "Graphite-dark" "Habiboow" "Aesthetic"; do
    if [[ -d "$SYS_THEMES/$OLD_THEME" ]]; then
        priv rm -rf "$SYS_THEMES/$OLD_THEME" && log_info "Removed old theme: $OLD_THEME"
    fi
done
if [[ -d /usr/share/backgrounds/xfce/devuan-tokyonight ]]; then
    priv rm -rf /usr/share/backgrounds/xfce/devuan-tokyonight && log_info "Removed old Tokyo Night wallpapers."
fi
if [[ -d "$REPO_THEMES" ]]; then
    DEPLOYED=0
    for THEME_DIR in "$REPO_THEMES"/Darkmatter*/; do
        [[ -d "$THEME_DIR" ]] || continue
        THEME_NAME=$(basename "$THEME_DIR")
        SYS_THEME="$SYS_THEMES/$THEME_NAME"
        priv mkdir -p "$SYS_THEME"
        for SUB in gtk-3.0 gtk-4.0 xfwm4; do
            [[ -d "$THEME_DIR/$SUB" ]] && priv cp -r "$THEME_DIR/$SUB" "$SYS_THEME/"
        done
        priv cp -r "$THEME_DIR/assets" "$SYS_THEME/"
        [[ -f "$THEME_DIR/index.theme" ]] && priv cp "$THEME_DIR/index.theme" "$SYS_THEME/"
        DEPLOYED=$((DEPLOYED + 1))
    done
    log_ok "Deployed $DEPLOYED Darkmatter variants to $SYS_THEMES/."
else
    log_warn "No bundled themes found at $REPO_THEMES — theme may be partially applied."
fi

log_head "3/9  Active GTK + xfwm4 theme: Darkmatter"
GTK_THEME="Darkmatter"
xfconf-query -c xsettings -n -p /Net/ThemeName -t string -s "$GTK_THEME" 2>/dev/null \
    || log_warn "Could not set GTK theme via xfconf — re-run inside a desktop session if /Net/ThemeName is missing."
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
GTK2_RC="$HOME/.gtkrc-2.0"
if [[ -f "$GTK2_RC" ]]; then
    cp "$GTK2_RC" "${GTK2_RC}.bak.$(date +%Y%m%d%H%M%S)"
fi
cat > "$GTK2_RC" << GTK2EOF
gtk-theme-name = "$GTK_THEME"
gtk-icon-theme-name = "Zafiro-icons-Dark"
gtk-font-name = "JetBrainsMono Nerd Font 10"
GTK2EOF
log_ok "GTK2/3 theme set to $GTK_THEME."
XFWM_THEME="Darkmatter"
if [[ -d "$SYS_THEMES/$XFWM_THEME/xfwm4" ]]; then
    xfconf-query -c xfwm4 -n -p /general/theme -t string -s "$XFWM_THEME" 2>/dev/null \
        || log_warn "Could not set xfwm4 theme via xfconf — re-run inside a desktop session if /general/theme is missing."
    log_ok "xfwm4 theme set to $XFWM_THEME."
else
    log_warn "xfwm4 theme dir missing for $XFWM_THEME — window decorations may be unthemed."
fi

log_head "4/9  Icons — bundled Zafiro (dark)"
ICONS_SRC="$SCRIPT_DIR/../configs/icons"
SYS_ICONS="/usr/share/icons"
ICON_THEME="Zafiro-icons-Dark"
if [[ -d "$ICONS_SRC/$ICON_THEME" ]]; then
    priv mkdir -p "$SYS_ICONS"
    if [[ ! -d "$SYS_ICONS/$ICON_THEME" ]]; then
        priv cp -r "$ICONS_SRC/$ICON_THEME" "$SYS_ICONS/"
        log_ok "Deployed $ICON_THEME to $SYS_ICONS/."
    else
        log_ok "$ICON_THEME already present — reusing."
    fi
    xfconf-query -c xsettings -n -p /Net/IconThemeName -t string -s "$ICON_THEME" 2>/dev/null \
        || log_warn "Could not set icon theme via xfconf — re-run inside a desktop session if /Net/IconThemeName is missing."
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" 2>/dev/null || true
    log_ok "Active icon theme: $ICON_THEME"
else
    log_warn "Bundled icons missing at $ICONS_SRC/$ICON_THEME — falling back to Papirus-Dark."
    priv apt-get install -y papirus-icon-theme 2>/dev/null || true
    xfconf-query -c xsettings -n -p /Net/IconThemeName -t string -s "Papirus-Dark" 2>/dev/null \
        || log_warn "Could not set fallback icon theme via xfconf."
fi

CURSOR_NAME=""
if [[ -d "$HOME/.icons/breeze_cursors" ]]; then
    CURSOR_NAME="breeze_cursors"
elif [[ -d "$HOME/.icons/Breeze_Dark" ]]; then
    CURSOR_NAME="Breeze_Dark"
else
    priv apt-get install -y breeze-cursor-theme 2>/dev/null && CURSOR_NAME="breeze_cursors" || true
fi
if [[ -n "$CURSOR_NAME" && -d "$HOME/.icons/$CURSOR_NAME" ]]; then
    xfconf-query -c xsettings -n -p /Gtk/CursorThemeName -t string -s "$CURSOR_NAME" 2>/dev/null \
        || log_warn "Could not set cursor theme via xfconf — re-run inside a desktop session if /Gtk/CursorThemeName is missing."
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_NAME" > "$HOME/.icons/default/index.theme"
    log_ok "Cursor theme: $CURSOR_NAME"
fi

log_head "5/9  Drop the old palette engine + per-user session CSS"
DEVX_ENGINE="$HOME/.config/devuan-xfce-setup"
for leftover in "$DEVX_ENGINE/lib" "$DEVX_ENGINE/themes" "$DEVX_ENGINE/bin" "$DEVX_ENGINE/current"; do
    rm -rf "$leftover" 2>/dev/null && log_info "Removed engine leftover: $leftover"
done
rm -f "$HOME/.local/bin/xfce-theme-list" "$HOME/.local/bin/xfce-theme-set" 2>/dev/null || true
rm -f "$HOME/.config/gtk-3.0/gtk.css" 2>/dev/null && log_info "Removed legacy per-user session gtk.css."
mkdir -p "$DEVX_ENGINE"
cat > "$DEVX_ENGINE/picker.colors" << PICKEREOF
# Darkmatter palette for the Python menu/update-gui widgets (21-theme.sh).
bg0=#121113F2
bg1=#1c1b1d
bg3=#e75353F2
fg0=#ffffff
PICKEREOF
log_ok "picker.colors written (Darkmatter) for xfce-menu / xfce-update-gui."

log_head "6/9  Terminal — Alacritty as THE terminal (Darkmatter toml)"
HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
mkdir -p "$HOME/.config/xfce4"
if [[ -f "$HELPERS_RC" ]]; then
    cp -a "$HELPERS_RC" "${HELPERS_RC}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i '/^TerminalEmulator=/d' "$HELPERS_RC"
else
    touch "$HELPERS_RC"
fi
echo "TerminalEmulator=alacritty" >> "$HELPERS_RC"
log_ok "Alacritty set as default terminal (helpers.rc)."

ALACRITTY_BIN=$(command -v alacritty || true)
if [[ -n "$ALACRITTY_BIN" ]] && command -v update-alternatives &>/dev/null; then
    priv update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$ALACRITTY_BIN" 60 2>/dev/null || true
    priv update-alternatives --set x-terminal-emulator "$ALACRITTY_BIN" 2>/dev/null || true
    log_ok "update-alternatives: x-terminal-emulator = alacritty"
fi

ALACRITTY_DIR="$HOME/.config/alacritty"
ALACRITTY_SEED="$SCRIPT_DIR/../configs/alacritty/alacritty.toml"
mkdir -p "$ALACRITTY_DIR"
rm -f "$ALACRITTY_DIR/alacritty.yml" 2>/dev/null || true
if [[ -f "$ALACRITTY_SEED" ]]; then
    if [[ -f "$ALACRITTY_DIR/alacritty.toml" ]]; then
        cp "$ALACRITTY_DIR/alacritty.toml" "${ALACRITTY_DIR}/alacritty.toml.bak.$(date +%Y%m%d%H%M%S)"
        log_info "Backed up existing alacritty.toml."
    fi
    cp "$ALACRITTY_SEED" "$ALACRITTY_DIR/alacritty.toml"
    log_ok "Darkmatter alacritty.toml deployed (0.13+ TOML format)."
else
    log_warn "Alacritty seed missing at $ALACRITTY_SEED."
fi

log_head "7/9  Compositor — xfwm4 built-in (picom removed)"
# picom is gone: xfwm4's own compositing (seeded in xfwm4.xml below) does
# shadows, inactive dim and move/resize fade with zero extra daemon. Clean
# up any picom a previous run left behind so the two can't fight over the
# screen.
if is_installed picom; then
    priv apt-get purge -y picom 2>/dev/null || log_warn "picom purge failed (continuing)."
fi
rm -f "$HOME/.config/autostart/picom.desktop" 2>/dev/null || true
rm -rf "$HOME/.config/picom" 2>/dev/null || true
if [[ -n "${DISPLAY:-}" ]]; then
    pkill -x picom 2>/dev/null || true
fi
log_ok "picom removed — xfwm4 built-in compositor takes over (seed below)."

log_head "8/9  Panel + window manager seed (items, decorations, fonts)"
XFCE_CONF="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
XFCE_SEED="$SCRIPT_DIR/../configs/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCE_CONF"
for CH in xfce4-panel xfwm4 xfce4-power-manager xsettings; do
    SRC="$XFCE_SEED/$CH.xml"
    DEST="$XFCE_CONF/$CH.xml"
    if [[ ! -f "$SRC" ]]; then
        log_warn "Seed missing: $SRC — leaving $CH unchanged."
        continue
    fi
    if [[ -f "$DEST" ]]; then
        cp "$DEST" "${DEST}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "Backed up existing $CH.xml."
    fi
    cp "$SRC" "$DEST"
    log_ok "Deployed $CH.xml (panel items + launchers / WM decorations + title font / power manager / GTK theme)."
done

# Launcher plugin payloads (items referenced by xfce4-panel.xml live next to the
# panel config, under ~/.config/xfce4/panel/launcher-*). The seed carries @USER_HOME@
# where a machine-specific home path would otherwise leak in — stamp with the real
# $HOME so launchers keep working for whoever the fresh install actually runs as.
PANEL_SEED="$SCRIPT_DIR/../configs/xfce4/panel"
PANEL_CONF="$HOME/.config/xfce4/panel"
if [[ -d "$PANEL_SEED" ]]; then
    while IFS= read -r -d '' SRC_LAUNCH; do
        REL="${SRC_LAUNCH#"$PANEL_SEED"/}"
        DEST_LAUNCH="$PANEL_CONF/$REL"
        if [[ -f "$DEST_LAUNCH" ]]; then
            cp "$DEST_LAUNCH" "${DEST_LAUNCH}.bak.$(date +%Y%m%d%H%M%S)"
            log_info "Backed up existing panel launcher $REL."
        fi
        mkdir -p "$(dirname "$DEST_LAUNCH")"
        sed "s|@USER_HOME@|$HOME|g" "$SRC_LAUNCH" > "$DEST_LAUNCH"
        log_ok "Deployed panel launcher $REL."
    done < <(find "$PANEL_SEED" -type f -name '*.desktop' -print0)
else
    log_warn "Panel launcher seed missing at $PANEL_SEED — skipping launcher payloads."
fi

if [[ -n "${DISPLAY:-}" ]]; then
    if command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r 2>/dev/null || true
        log_ok "xfce4-panel restarted."
    fi
    if command -v xfwm4 &>/dev/null; then
        xfwm4 --replace >/dev/null 2>&1 &
        log_ok "xfwm4 reloaded (decorations, title font)."
    fi
else
    log_warn "No graphical session detected — panel/WM seed applies on next login."
fi

log_head "9/9  Wallpapers"
WALLPAPER_DEST="/usr/share/backgrounds/xfce/devuan-darkmatter"
priv mkdir -p "$WALLPAPER_DEST"
for f in "$SCRIPT_DIR/../configs/wallpapers/darkmatter/"*; do
    [[ -f "$f" ]] || continue
    BASENAME=$(basename "$f")
    if [[ ! -f "$WALLPAPER_DEST/$BASENAME" ]]; then
        priv cp "$f" "$WALLPAPER_DEST/"
    fi
done
log_ok "Darkmatter wallpapers deployed to $WALLPAPER_DEST."

FIRST_WALLPAPER="$WALLPAPER_DEST/black-leaves.jpg"
if [[ -f "$FIRST_WALLPAPER" && -n "${DISPLAY:-}" ]] && command -v xfconf-query &>/dev/null; then
    MONITORS=$(xrandr --query 2>/dev/null | grep ' connected' | awk '{print $1}' || true)
    if [[ -z "$MONITORS" ]]; then
        MONITORS="default"
    fi
    SCREEN_IDX=0
    for MON in $MONITORS; do
        BASE="/backdrop/screen${SCREEN_IDX}/monitor${MON}"
        xfconf-query -c xfce4-desktop -p "$BASE/image-path" -s "$FIRST_WALLPAPER" 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "$BASE/last-image" -s "$FIRST_WALLPAPER" 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "$BASE/workspace0/last-image" -s "$FIRST_WALLPAPER" 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "$BASE/image-show" -s true 2>/dev/null || true
        SCREEN_IDX=$((SCREEN_IDX + 1))
    done
    log_ok "Live backdrop set to $FIRST_WALLPAPER"
else
    log_warn "No graphical session or no wallpapers found — apply after first login."
fi

log_head "Bonus  Dunst + Rofi configs (opt-in, only if present)"
if [[ -f "$SCRIPT_DIR/../configs/dunst/dunstrc" ]] && command -v dunst &>/dev/null; then
    mkdir -p "$HOME/.config/dunst"
    cp "$SCRIPT_DIR/../configs/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
    log_ok "Darkmatter dunstrc deployed (active if you later swap to Dunst)."
fi
if [[ -f "$SCRIPT_DIR/../configs/rofi/darkmatter.rasi" ]] && command -v rofi &>/dev/null; then
    mkdir -p "$HOME/.config/rofi"
    cp "$SCRIPT_DIR/../configs/rofi/darkmatter.rasi" "$HOME/.config/rofi/darkmatter.rasi"
    log_ok "Darkmatter rofi theme deployed."
fi

echo
log_ok "Theme applied — Darkmatter (GTK/xfwm4), Zafiro icons, xfwm4 compositor, panel, alacritty, wallpapers."
echo -e "If anything looks half-applied, a full logout/login always settles it."
echo -e "Re-run this script any time to refresh icons after installing new apps."