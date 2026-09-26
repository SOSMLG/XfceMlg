#!/usr/bin/env bash
# DEBSWAY_DESC: Plymouth + GRUB + LightDM greeter theming (Darkmatter)
# DEBSWAY_DEFAULT: Y
#  22-theme-boot.sh — the part before you see the desktop
#
#  21-theme.sh handles everything *inside* the session. This handles the
#  three things you see *before* that: the Plymouth splash while the
#  kernel boots, the GRUB menu (if you ever see it), and the LightDM
#  login screen. It matches the Darkmatter palette (near-black #121113,
#  red accent #e75353) from step 21.
#
#  This is more invasive than the rest of the toolkit — it edits
#  /etc/default/grub, regenerates grub.cfg, and rebuilds the
#  initramfs. Every edit is backed up first, and every step checks
#  it actually applies to this machine (no GRUB? no LightDM? it
#  says so and skips, instead of guessing).
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root


WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/3  Plymouth boot splash"
if ask "Install the Darkmatter Plymouth splash (near-black with a red spinner, shown while the kernel boots)?"; then
    priv apt-get install -y plymouth plymouth-themes imagemagick || log_warn "Plymouth package install had issues — continuing."

    SPLASH_SRC="/usr/share/plymouth/themes/spinner"
    SPLASH_NAME="devuan-darkmatter"
    SPLASH_DEST="/usr/share/plymouth/themes/$SPLASH_NAME"
    if [[ ! -d "$SPLASH_SRC" ]]; then
        log_warn "Stock 'spinner' Plymouth theme not found — skipping splash."
    else
        priv mkdir -p "$SPLASH_DEST"
        # Ship the stock spinner layout, then recolor every PNG to the
        # Darkmatter palette: spinner green -> red accent, box darkened.
        priv cp -r "$SPLASH_SRC"/. "$SPLASH_DEST/"
        RECOLORED=0
        for png in "$SPLASH_DEST"/*.png; do
            [[ -f "$png" ]] || continue
            # The stock spinner uses that recognizable lime-green. Fuzz so
            # antialiased edges get mapped too, and drop any watermark.
            case "$(basename "$png")" in
                watermark.png)
                    W=$(identify -format '%w' "$png" 2>/dev/null || echo 0)
                    H=$(identify -format '%h' "$png" 2>/dev/null || echo 0)
                    [[ "$W" -gt 0 && "$H" -gt 0 ]] && priv convert "$png" -size "${W}x${H}" xc:none "$png"
                    ;;
                box.png)
                    priv convert "$png" -fuzz 40% -fill '#121113' -opaque '#333333' \
                        -fuzz 20% -fill '#121113' -opaque '#444444' "$png"
                    ;;
                *)
                    priv convert "$png" -fuzz 35% \
                        -fill '#e75353' -opaque '#27ae60' \
                        -fill '#e75353' -opaque '#2ecc71' \
                        -fill '#e75353' -opaque '#33cc33' \
                        -fill '#e75353' -opaque '#00ff00' \
                        -fill '#e75353' -opaque '#16a085' \
                        -fill '#e75353' -opaque '#1abc9c' \
                        -fill '#e75353' -opaque '#27a9e3' \
                        -fill '#e75353' -opaque '#3498d8' "$png"
                    ;;
            esac
            RECOLORED=$((RECOLORED + 1))
        done
        if [[ $RECOLORED -gt 0 ]]; then
            log_ok "Recolored $RECOLORED splash images to Darkmatter #e75353."
        else
            log_warn "No PNGs found to recolor — falling back to stock spinner look."
        fi

        PLYMOUTH_PLY=$(find "$SPLASH_DEST" -maxdepth 1 -name "*.plymouth" | head -1)
        if [[ -z "$PLYMOUTH_PLY" ]]; then
            PLYMOUTH_PLY="$SPLASH_DEST/$SPLASH_NAME.plymouth"
        fi

        APPLIED=0
        if command -v plymouth-set-default-theme &>/dev/null; then
            if priv plymouth-set-default-theme -R "$SPLASH_NAME" 2>/tmp/darkmatter-plymouth-set.log; then
                APPLIED=1
            fi
        fi
        if [[ $APPLIED -eq 0 ]]; then
            log_info "plymouth-set-default-theme unavailable/failed — using update-alternatives instead."
            priv update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
                default.plymouth "$PLYMOUTH_PLY" 200 \
                && priv update-alternatives --set default.plymouth "$PLYMOUTH_PLY" \
                && priv update-initramfs -u \
                && APPLIED=1
        fi

        if [[ $APPLIED -eq 1 ]]; then
            log_ok "Plymouth theme set to $SPLASH_NAME."
            GRUB_DEFAULT="/etc/default/grub"
            if [[ -f "$GRUB_DEFAULT" ]]; then
                priv cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
                LINE=$(grep -m1 '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT" || true)
                if [[ -n "$LINE" ]]; then
                    NEEDS_UPDATE=0
                    NEW_LINE="$LINE"
                    [[ "$NEW_LINE" != *"splash"* ]] && { NEW_LINE="${NEW_LINE%\"}"; NEW_LINE="${NEW_LINE} splash\""; NEEDS_UPDATE=1; }
                    [[ "$NEW_LINE" != *"quiet"* ]] && { NEW_LINE="${NEW_LINE%\"}"; NEW_LINE="${NEW_LINE} quiet\""; NEEDS_UPDATE=1; }
                    if [[ $NEEDS_UPDATE -eq 1 ]]; then
                        priv sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|${NEW_LINE}|" "$GRUB_DEFAULT"
                        log_ok "Added splash/quiet to GRUB_CMDLINE_LINUX_DEFAULT (backup saved alongside it)."
                    fi
                else
                    echo 'GRUB_CMDLINE_LINUX_DEFAULT="splash quiet"' | priv tee -a "$GRUB_DEFAULT" > /dev/null
                    log_ok "Added GRUB_CMDLINE_LINUX_DEFAULT with splash/quiet."
                fi
                if command -v update-grub &>/dev/null; then
                    priv update-grub || log_warn "update-grub failed — run it yourself once you've checked $GRUB_DEFAULT"
                fi
            else
                log_warn "No /etc/default/grub found — if this system doesn't use GRUB, add 'splash quiet' to your bootloader's kernel cmdline manually."
            fi
            log_warn "You won't see this until your next real reboot — a logout doesn't touch it."
        else
            log_err "Couldn't apply the Plymouth theme. Log: /tmp/darkmatter-plymouth-set.log"
        fi
    fi
else
    log_warn "Skipped Plymouth."
fi

log_head "2/3  GRUB menu theme"
if ! command -v update-grub &>/dev/null && [[ ! -d /boot/grub ]]; then
    log_warn "This system doesn't appear to use GRUB — skipping (nothing to do, not an error)."
elif ask "Install the Darkmatter GRUB background (only matters if you actually see the GRUB menu)?"; then
    GRUB_DEFAULT="/etc/default/grub"
    WALLPAPER_DIR="/usr/share/backgrounds/xfce/devuan-darkmatter"
    GRUB_BG=$(ls "$WALLPAPER_DIR"/*.{jpg,jpeg,png} 2>/dev/null | head -1)
    if [[ -n "$GRUB_BG" ]]; then
        # Preserve the file extension
        GRUB_BG_EXT="${GRUB_BG##*.}"
        GRUB_BG_DEST="/boot/grub/devuan-darkmatter.$GRUB_BG_EXT"
        priv cp "$GRUB_BG" "$GRUB_BG_DEST"
        log_ok "GRUB background copied to $GRUB_BG_DEST"

        if [[ -f "$GRUB_DEFAULT" ]]; then
            priv cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
            GRUB_BG_LINE="GRUB_BACKGROUND=\"$GRUB_BG_DEST\""
            if grep -q '^GRUB_BACKGROUND=' "$GRUB_DEFAULT"; then
                priv sed -i "s|^GRUB_BACKGROUND=.*|${GRUB_BG_LINE}|" "$GRUB_DEFAULT"
            elif grep -q '^#GRUB_BACKGROUND=' "$GRUB_DEFAULT"; then
                priv sed -i "s|^#GRUB_BACKGROUND=.*|${GRUB_BG_LINE}|" "$GRUB_DEFAULT"
            else
                echo "$GRUB_BG_LINE" | priv tee -a "$GRUB_DEFAULT" > /dev/null
            fi
            # GRUB_TERMINAL_OUTPUT=console suppresses graphical theme — disable it.
            priv sed -i 's/^GRUB_TERMINAL_OUTPUT=console/#GRUB_TERMINAL_OUTPUT=console/' "$GRUB_DEFAULT"

            if command -v update-grub &>/dev/null; then
                if priv update-grub; then
                    log_ok "GRUB background applied. You'll see it next time GRUB's menu actually shows."
                else
                    log_err "update-grub failed — check $GRUB_DEFAULT for typos before rebooting."
                fi
            fi
        else
            log_warn "No /etc/default/grub found — background is in place but not wired up."
        fi
    else
        log_warn "No wallpaper found in $WALLPAPER_DIR — run 21-theme.sh first."
    fi
else
    log_warn "Skipped GRUB theme."
fi

log_head "3/3  LightDM login screen"
if ! dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
    log_warn "LightDM isn't installed — skipping (if you use a different display manager, this script doesn't know its config format)."
elif ! command -v lightdm-gtk-greeter 2>/dev/null && ! dpkg -l lightdm-gtk-greeter 2>/dev/null | grep -q '^ii'; then
    priv apt-get install -y lightdm-gtk-greeter || log_warn "Couldn't install lightdm-gtk-greeter — skipping greeter theming."
fi

if dpkg -l lightdm-gtk-greeter 2>/dev/null | grep -q '^ii'; then
    if ask "Theme the LightDM login screen to match (copies your already-installed GTK theme system-wide)?"; then
        GTK_THEME_NAME="Darkmatter"
        if [[ -d "/usr/share/themes/$GTK_THEME_NAME" ]]; then
            log_ok "GTK theme already deployed to /usr/share/themes/$GTK_THEME_NAME."
        else
            log_warn "Darkmatter not found in /usr/share/themes — run 21-theme.sh first."
        fi

        ICON_THEME_NAME=""
        for candidate in "Zafiro-icons-Dark" "Papirus-Dark" "Tela-circle-dark"; do
            if [[ -d "/usr/share/icons/$candidate" ]] || [[ -d "$HOME/.local/share/icons/$candidate" ]]; then
                priv mkdir -p /usr/share/icons
                [[ -d "$HOME/.local/share/icons/$candidate" && ! -d "/usr/share/icons/$candidate" ]] \
                    && priv cp -r "$HOME/.local/share/icons/$candidate" /usr/share/icons/
                ICON_THEME_NAME="$candidate"
                log_ok "Icon theme available: $candidate"
                break
            fi
        done

        CURSOR_THEME_NAME=""
        for candidate in "breeze_cursors" "Breeze_Dark" "Adwaita"; do
            if [[ -d "/usr/share/icons/$candidate" ]] || [[ -d "$HOME/.icons/$candidate" ]]; then
                CURSOR_THEME_NAME="$candidate"
                break
            fi
        done
        if [[ -n "$CURSOR_THEME_NAME" ]]; then
            log_ok "Cursor theme available: $CURSOR_THEME_NAME"
        fi

        GREETER_BG=""
        WALLPAPER_DIR="/usr/share/backgrounds/xfce/devuan-darkmatter"
        FIRST_WALL=$(ls "$WALLPAPER_DIR"/*.{jpg,jpeg,png} 2>/dev/null | head -1)
        if [[ -n "$FIRST_WALL" ]]; then
            GREETER_BG="$FIRST_WALL"
            log_ok "Login background: $GREETER_BG"
        fi

        GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
        [[ -f "$GREETER_CONF" ]] && priv cp "$GREETER_CONF" "${GREETER_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        {
            echo "[greeter]"
            [[ -n "$GTK_THEME_NAME" ]] && echo "theme-name = $GTK_THEME_NAME"
            [[ -n "$ICON_THEME_NAME" ]] && echo "icon-theme-name = $ICON_THEME_NAME"
            [[ -n "$CURSOR_THEME_NAME" ]] && echo "cursor-theme-name = $CURSOR_THEME_NAME"
            echo "font-name = Sans 10"
            [[ -n "$GREETER_BG" ]] && echo "background = $GREETER_BG"
            echo "user-background = false"
            echo "clock-format = %a %d %b, %H:%M"
            echo "indicators = ~host;~spacer;~clock;~spacer;~language;~session;~a11y;~power"
            echo "position = 50%,center 50%,center"
            echo "screensaver-timeout = 60"
            echo "xft-antialias = true"
            echo "xft-hintstyle = slight"
            echo "xft-rgba = rgb"
        } | priv tee "$GREETER_CONF" > /dev/null
        log_ok "Wrote $GREETER_CONF (matched theme, background, clock, tidy indicators)"

        GREETER_CSS_SRC="$SCRIPT_DIR/../configs/lightdm/gtk.css"
        GREETER_CSS_DIR="/var/lib/lightdm/.config/gtk-3.0"
        if [[ -f "$GREETER_CSS_SRC" ]]; then
            priv mkdir -p "$GREETER_CSS_DIR"
            [[ -f "$GREETER_CSS_DIR/gtk.css" ]] && priv cp "$GREETER_CSS_DIR/gtk.css" "$GREETER_CSS_DIR/gtk.css.bak.$(date +%Y%m%d%H%M%S)"
            priv cp "$GREETER_CSS_SRC" "$GREETER_CSS_DIR/gtk.css"
            priv chown -R lightdm:lightdm /var/lib/lightdm 2>/dev/null || true
            log_ok "Greeter login-box styling installed."
        else
            log_warn "Greeter CSS source missing at $GREETER_CSS_SRC — skipping."
        fi

        LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
        if command -v numlockx &>/dev/null; then
            [[ -f "$LIGHTDM_CONF" ]] && priv cp "$LIGHTDM_CONF" "${LIGHTDM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
            [[ -f "$LIGHTDM_CONF" ]] || touch "$LIGHTDM_CONF"
            ini_dedup_key "$LIGHTDM_CONF" "Seat:*" "greeter-setup-script" "/usr/bin/numlockx on"
        fi
        log_warn "Takes effect at next login/reboot — restarting the display manager now would end this session."
    fi
else
    log_warn "lightdm-gtk-greeter isn't installed — skipping greeter theming."
fi

echo
log_ok "Boot → login theming pass complete. Reboot to see all three."