#!/usr/bin/env bash
# DEBSWAY_DESC: Tokyo Night GTK/xfwm4/icons + alacritty + panel rice
# DEBSWAY_DEFAULT: Y
#  21-theme-tokyonight.sh — the whole Tokyo Night look, in one pass.
#
#  Tokyo Night palette, dark translucent single bottom panel with
#  rounded corners, subtle accent color, alacritty as terminal.
#    - GTK2/3/4 + xfwm4 theme  (bundled Tokyonight-Dark-BL)
#    - Cursor theme            (xcursor-breeze, dark fallback)
#    - Icon theme              (papirus-icon-theme, dark neutral)
#    - Panel gtk.css override  (subtle dark, rounded corners)
#    - Terminal: alacritty, Tokyo Night colors, set as THE terminal
#    - Panel rice: single bottom panel with whiskermenu, docklike,
#      pager, genmon cluster (cpu/mem/net/disk/bat/datetime), clock
#    - Wallpaper deployment
#
#  Since choosing to run this script already means "yes, do the
#  theme," most steps below just run — no per-step Y/n barrage.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root


apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/9  Dependencies"
priv apt-get install -y \
    gtk2-engines-murrine gnome-themes-extra adwaita-icon-theme \
    git curl tar alacritty numlockx \
    xfce4-whiskermenu-plugin xfce4-docklike-plugin xfce4-genmon-plugin \
    xfce4-pager xfce4-datetime-plugin \
    acpi lm-sensors gawk \
    || log_warn "Some packages failed to install (continuing — the theme may partially apply)."
log_ok "Dependencies installed."

log_head "2/9  Deploy bundled themes to system roots"
REPO_THEMES="$SCRIPT_DIR/../configs/themes"
if [[ -d "$REPO_THEMES" ]]; then
    DEPLOYED=0
    for THEME_DIR in "$REPO_THEMES"/*/; do
        [[ -d "$THEME_DIR" ]] || continue
        THEME_NAME=$(basename "$THEME_DIR")
        SYS_THEME="/usr/share/themes/$THEME_NAME"
        priv mkdir -p "$SYS_THEME"
        for SUB in gtk-2.0 gtk-3.0 gtk-4.0 xfwm4; do
            [[ -d "$THEME_DIR/$SUB" ]] && priv cp -r "$THEME_DIR/$SUB" "$SYS_THEME/"
        done
        [[ -f "$THEME_DIR/index.theme" ]] && priv cp "$THEME_DIR/index.theme" "$SYS_THEME/"
        DEPLOYED=$((DEPLOYED + 1))
    done
    log_ok "Deployed $DEPLOYED bundled themes to /usr/share/themes/."
else
    log_warn "No bundled themes found at $REPO_THEMES — theme may be partially applied."
fi

log_head "3/9  Set active GTK + xfwm4 themes"
GTK_THEME_NAME="Tokyonight-Dark-BL"
XFWM_THEME_NAME="Tokyo Night - Bordered"
xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_THEME_NAME" 2>/dev/null || true
xfconf-query -c xfwm4 -p /general/theme -s "$XFWM_THEME_NAME" 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
log_ok "GTK theme: $GTK_THEME_NAME, xfwm4 theme: $XFWM_THEME_NAME"

log_head "4/9  Icons + cursors"
ICONS_DIR="$HOME/.local/share/icons"
mkdir -p "$ICONS_DIR" "$HOME/.icons"

# Tela Circle (dark) is a clean, quiet fit for Tokyo Night. Clone its default
# dark build; a failed clone/install degrades to papirus-dark without fuss.
# Wrap the clone in timeout so a slow network can't hang the whole script.
ICON_THEME_NAME=""
if [[ -d "$ICONS_DIR/Tela-circle-dark" ]]; then
    ICON_THEME_NAME="Tela-circle-dark"
    log_ok "Tela Circle Dark icons already present — reusing."
else
    log_info "Cloning vinceliuice/Tela-circle-icon-theme (dark build)..."
    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT
    if timeout 90 git clone --depth=1 https://github.com/vinceliuice/Tela-circle-icon-theme.git "$WORK_DIR/Tela-circle" 2>/tmp/tela-clone.log; then
        if "$WORK_DIR/Tela-circle/install.sh" --dest "$ICONS_DIR" 2>/tmp/tela-install.log; then
            if [[ -d "$ICONS_DIR/Tela-circle-dark" ]]; then
                ICON_THEME_NAME="Tela-circle-dark"
                log_ok "Tela Circle Dark icons installed."
            fi
        fi
    fi
    rm -rf "$WORK_DIR"
    trap - EXIT
fi

if [[ -z "$ICON_THEME_NAME" ]]; then
    log_warn "Tela Circle clone/install failed — falling back to papirus-icon-theme."
    priv apt-get install -y papirus-icon-theme 2>/dev/null || true
    ICON_THEME_NAME="Papirus-Dark"
    log_ok "Fallback icon theme: Papirus-Dark."
fi

if [[ -d "$ICONS_DIR/$ICON_THEME_NAME" ]]; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICON_THEME_NAME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_NAME" 2>/dev/null || true
    log_ok "Active icon theme: $ICON_THEME_NAME"
fi

CURSOR_NAME=""
if [[ -d "$HOME/.icons/breeze_cursors" ]]; then
    CURSOR_NAME="breeze_cursors"
elif [[ -d "$HOME/.icons/Breeze_Dark" ]]; then
    CURSOR_NAME="Breeze_Dark"
else
    priv apt-get install -y xcursor-breeze 2>/dev/null && CURSOR_NAME="breeze_cursors" || true
fi
if [[ -n "$CURSOR_NAME" && -d "$HOME/.icons/$CURSOR_NAME" ]]; then
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CURSOR_NAME" 2>/dev/null || true
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_NAME" > "$HOME/.icons/default/index.theme"
    log_ok "Cursor theme: $CURSOR_NAME"
fi

log_head "5/9  Session GTK CSS (subtle dark panel, rounded corners)"
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"
mkdir -p "$HOME/.config/gtk-3.0"
[[ -f "$GTK3_CSS" ]] && { cp "$GTK3_CSS" "${GTK3_CSS}.bak.$(date +%Y%m%d%H%M%S)"; log_info "Backed up existing gtk.css."; }
cp "$SCRIPT_DIR/../configs/gtk-session.css" "$GTK3_CSS"
log_ok "Session GTK CSS deployed to $GTK3_CSS"

log_head "6/9  Terminal — Alacritty"
ALACRITTY_DIR="$HOME/.config/alacritty"
mkdir -p "$ALACRITTY_DIR"
ALACRITTY_CONF="$ALACRITTY_DIR/alacritty.yml"
[[ -f "$ALACRITTY_CONF" ]] && cp "$ALACRITTY_CONF" "${ALACRITTY_CONF}.bak.$(date +%Y%m%d%H%M%S)"
cp "$SCRIPT_DIR/../configs/alacritty/alacritty.yml" "$ALACRITTY_CONF"
log_ok "Alacritty config deployed to $ALACRITTY_CONF"

HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
mkdir -p "$HOME/.config/xfce4"
# Merge, never clobber: keep any existing WebBrowser/MailReader/FileManager
# lines, replace only the TerminalEmulator one.
if [[ -f "$HELPERS_RC" ]]; then
    grep -v '^TerminalEmulator=' "$HELPERS_RC" > "${HELPERS_RC}.tmp" 2>/dev/null || true
    mv -f "${HELPERS_RC}.tmp" "$HELPERS_RC"
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

log_head "7/9  Genmon + icons deployment"
GENMON_DEST="$HOME/.config/xfce4/genmon"
mkdir -p "$GENMON_DEST/icons"
cp "$SCRIPT_DIR/../configs/genmon/"*.sh "$GENMON_DEST/"
chmod 700 "$GENMON_DEST/"*.sh
cp -r "$SCRIPT_DIR/../configs/genmon/icons/"* "$GENMON_DEST/icons/" 2>/dev/null || true
log_ok "Genmon scripts + icons deployed to $GENMON_DEST"

log_head "8/9  Panel seed (single bottom panel, dark translucent)"
PANEL_XML="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
mkdir -p "$(dirname "$PANEL_XML")"
if [[ -f "$PANEL_XML" ]]; then
    cp "$PANEL_XML" "${PANEL_XML}.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backed up existing xfce4-panel.xml."
fi

cat > "$PANEL_XML" << PANELEOF
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
  </property>
  <property name="panel-1" type="uint" value="1">
    <property name="position" type="string" value="p=8;x=0;y=0"/>
    <property name="length" type="uint" value="100"/>
    <property name="position-locked" type="bool" value="true"/>
    <property name="size" type="uint" value="44"/>
    <property name="background-style" type="uint" value="1"/>
    <property name="background-alpha" type="uint" value="85"/>
    <property name="plugin-ids" type="array">
      <value type="int" value="1"/>
      <value type="int" value="2"/>
      <value type="int" value="3"/>
      <value type="int" value="4"/>
      <value type="int" value="5"/>
      <value type="int" value="6"/>
      <value type="int" value="7"/>
      <value type="int" value="8"/>
      <value type="int" value="9"/>
      <value type="int" value="10"/>
      <value type="int" value="11"/>
      <value type="int" value="12"/>
      <value type="int" value="13"/>
      <value type="int" value="14"/>
      <value type="int" value="15"/>
    </property>
  </property>
  <property name="plugins" type="hash">
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="button-title" type="string" value=""/>
    </property>
    <property name="plugin-2" type="string" value="separator">
      <property name="transparent" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="docklike-plugin"/>
    <property name="plugin-4" type="string" value="separator">
      <property name="transparent" type="bool" value="true"/>
    </property>
    <property name="plugin-5" type="string" value="pager"/>
    <property name="plugin-6" type="string" value="separator">
      <property name="transparent" type="bool" value="true"/>
    </property>
    <property name="plugin-7" type="string" value="genmon">
      <property name="command" type="string" value="$HOME/.config/xfce4/genmon/cpu-panel.sh"/>
      <property name="period" type="uint" value="10"/>
    </property>
    <property name="plugin-8" type="string" value="genmon">
      <property name="command" type="string" value="$HOME/.config/xfce4/genmon/memory-panel.sh"/>
      <property name="period" type="uint" value="10"/>
    </property>
    <property name="plugin-9" type="string" value="genmon">
      <property name="command" type="string" value="$HOME/.config/xfce4/genmon/network-panel.sh"/>
      <property name="period" type="uint" value="10"/>
    </property>
    <property name="plugin-10" type="string" value="genmon">
      <property name="command" type="string" value="$HOME/.config/xfce4/genmon/disk-panel.sh"/>
      <property name="period" type="uint" value="10"/>
    </property>
    <property name="plugin-11" type="string" value="genmon">
      <property name="command" type="string" value="$HOME/.config/xfce4/genmon/battery-panel.sh"/>
      <property name="period" type="uint" value="10"/>
    </property>
    <property name="plugin-12" type="string" value="separator">
      <property name="transparent" type="bool" value="true"/>
    </property>
    <property name="plugin-13" type="string" value="genmon">
      <property name="command" type="string" value="$HOME/.config/xfce4/genmon/datetime-panel.sh"/>
      <property name="period" type="uint" value="30"/>
    </property>
    <property name="plugin-14" type="string" value="separator">
      <property name="transparent" type="bool" value="true"/>
    </property>
    <property name="plugin-15" type="string" value="datetime">
      <property name="digital-format" type="string" value="%H:%M"/>
      <property name="show-seconds" type="bool" value="false"/>
    </property>
  </property>
</channel>
PANELEOF
log_ok "Panel XML seeded: single bottom panel (whiskermenu → docklike → pager → genmon cluster → datetime → clock)."

if [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
    xfce4-panel -r 2>/dev/null || true
    log_ok "xfce4-panel restarted."
else
    log_warn "No graphical session detected — panel will apply on next login."
fi

log_head "9/9  Wallpapers"
WALLPAPER_DEST="/usr/share/backgrounds/xfce/devuan-tokyonight"
priv mkdir -p "$WALLPAPER_DEST"
WALLPAPER_COUNT=0
for f in "$SCRIPT_DIR/../configs/wallpapers/"*; do
    [[ -f "$f" ]] || continue
    BASENAME=$(basename "$f")
    if [[ ! -f "$WALLPAPER_DEST/$BASENAME" ]]; then
        priv cp "$f" "$WALLPAPER_DEST/"
    fi
    WALLPAPER_COUNT=$((WALLPAPER_COUNT + 1))
done
log_ok "Deployed $WALLPAPER_COUNT wallpapers to $WALLPAPER_DEST"

FIRST_WALLPAPER=$(ls "$WALLPAPER_DEST"/*.{jpg,jpeg,png} 2>/dev/null | head -1)
if [[ -n "$FIRST_WALLPAPER" && -n "${DISPLAY:-}" ]] && command -v xfconf-query &>/dev/null; then
    MONITORS=$(xrandr --query 2>/dev/null | grep ' connected' | awk '{print $1}' || true)
    if [[ -z "$MONITORS" ]]; then
        MONITORS="default"
    fi
    SCREEN_IDX=0
    for MON in $MONITORS; do
        xfconf-query -c xfce4-desktop -p "/backdrop/screen${SCREEN_IDX}/monitor${MON}/last-image" -s "$FIRST_WALLPAPER" 2>/dev/null || true
        SCREEN_IDX=$((SCREEN_IDX + 1))
    done
    log_ok "Live backdrop set to $FIRST_WALLPAPER"
else
    log_warn "No graphical session or no wallpapers found — apply after first login."
fi

echo
log_ok "Tokyo Night theme applied — GTK/WM, cursors, icons, panel, alacritty, wallpapers."
echo -e "If anything looks half-applied, a full logout/login always settles it."
echo -e "Re-run this script any time to refresh icons after installing new apps."
