#!/usr/bin/env bash
# DEBSWAY_DESC: Plymouth + GRUB + LightDM greeter theming
# DEBSWAY_DEFAULT: Y
#  22-theme-boot.sh — the part before you see the desktop
#
#  21-theme-catppuccin.sh handles everything *inside* the session.
#  This handles the three things you see *before* that: the
#  Plymouth splash while the kernel boots, the GRUB menu (if you
#  ever see it), and the LightDM login screen. Right now all three
#  are stock — this closes that seam.
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
if ask "Install the Catppuccin Plymouth splash (shown while the kernel boots)?"; then
    priv apt-get install -y plymouth plymouth-themes || log_warn "Plymouth package install had issues — continuing."

    if git clone --depth=1 https://github.com/catppuccin/plymouth.git "$WORK_DIR/plymouth" 2>/tmp/catppuccin-plymouth-clone.log; then
        if [[ -d "$WORK_DIR/plymouth/themes/catppuccin-mocha" ]]; then
            priv mkdir -p /usr/share/plymouth/themes
            priv cp -r "$WORK_DIR/plymouth/themes/catppuccin-mocha" /usr/share/plymouth/themes/
            log_ok "Theme files copied to /usr/share/plymouth/themes/catppuccin-mocha"

            APPLIED=0
            if command -v plymouth-set-default-theme &>/dev/null; then
                # -R also rebuilds the initramfs — one command does both.
                if priv plymouth-set-default-theme -R catppuccin-mocha 2>/tmp/plymouth-set-theme.log; then
                    APPLIED=1
                fi
            fi
            if [[ $APPLIED -eq 0 ]]; then
                log_info "plymouth-set-default-theme unavailable/failed — using update-alternatives instead."
                priv update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
                    default.plymouth /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth 200 \
                    && priv update-alternatives --set default.plymouth \
                        /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth \
                    && priv update-initramfs -u \
                    && APPLIED=1
            fi

            if [[ $APPLIED -eq 1 ]]; then
                log_ok "Plymouth theme set to catppuccin-mocha."
                # Plymouth only actually shows unless the kernel cmdline
                # asks for it — add splash/quiet if they're not already
                # there, don't touch anything else on the line.
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
                log_err "Couldn't apply the Plymouth theme. Log: /tmp/plymouth-set-theme.log"
            fi
        else
            log_err "Cloned catppuccin/plymouth but themes/catppuccin-mocha wasn't there — upstream layout may have changed."
        fi
    else
        log_err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-plymouth-clone.log"
    fi
else
    log_warn "Skipped Plymouth."
fi

log_head "2/3  GRUB menu theme"
if ! command -v update-grub &>/dev/null && [[ ! -d /boot/grub ]]; then
    log_warn "This system doesn't appear to use GRUB — skipping (nothing to do, not an error)."
elif ask "Install the Catppuccin GRUB theme (only matters if you actually see the GRUB menu)?"; then
    if git clone --depth=1 https://github.com/catppuccin/grub.git "$WORK_DIR/grub" 2>/tmp/catppuccin-grub-clone.log; then
        THEME_TXT=$(find "$WORK_DIR/grub" -maxdepth 3 -iname "theme.txt" -ipath "*mocha*" | head -1)
        if [[ -n "$THEME_TXT" ]]; then
            THEME_DIR=$(dirname "$THEME_TXT")
            THEME_NAME=$(basename "$THEME_DIR")
            priv mkdir -p /usr/share/grub/themes
            priv cp -r "$THEME_DIR" "/usr/share/grub/themes/"
            log_ok "GRUB theme copied to /usr/share/grub/themes/$THEME_NAME"

            GRUB_DEFAULT="/etc/default/grub"
            if [[ -f "$GRUB_DEFAULT" ]]; then
                priv cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
                THEME_LINE="GRUB_THEME=\"/usr/share/grub/themes/${THEME_NAME}/theme.txt\""
                if grep -q '^GRUB_THEME=' "$GRUB_DEFAULT"; then
                    priv sed -i "s|^GRUB_THEME=.*|${THEME_LINE}|" "$GRUB_DEFAULT"
                elif grep -q '^#GRUB_THEME=' "$GRUB_DEFAULT"; then
                    priv sed -i "s|^#GRUB_THEME=.*|${THEME_LINE}|" "$GRUB_DEFAULT"
                else
                    echo "$THEME_LINE" | priv tee -a "$GRUB_DEFAULT" > /dev/null
                fi
                # GRUB_TERMINAL_OUTPUT=console (if set) suppresses the
                # graphical theme entirely — a common "theme installed
                # but GRUB still looks stock" cause.
                priv sed -i 's/^GRUB_TERMINAL_OUTPUT=console/#GRUB_TERMINAL_OUTPUT=console/' "$GRUB_DEFAULT"

                if command -v update-grub &>/dev/null; then
                    if priv update-grub; then
                        log_ok "GRUB theme applied ($THEME_NAME). You'll see it next time GRUB's menu actually shows."
                    else
                        log_err "update-grub failed — check $GRUB_DEFAULT for typos before rebooting."
                    fi
                fi
            else
                log_warn "No /etc/default/grub found — theme files are in place but not wired up."
            fi
        else
            log_err "Cloned catppuccin/grub but couldn't find a Mocha theme.txt in it — upstream layout may have changed."
        fi
    else
        log_err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-grub-clone.log"
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
        # The greeter runs as its own system user with no access to your
        # $HOME, so ~/.themes doesn't exist as far as it's concerned —
        # everything has to actually live under /usr/share.
        GTK_THEME_NAME=$(find "$HOME/.themes" -maxdepth 1 -type d -iname "*catppuccin*red*dark*" -printf '%f\n' 2>/dev/null | head -1)
        [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$HOME/.themes" -maxdepth 1 -type d -iname "*catppuccin*" -printf '%f\n' 2>/dev/null | head -1)

        if [[ -n "$GTK_THEME_NAME" && -d "$HOME/.themes/$GTK_THEME_NAME" ]]; then
            priv mkdir -p /usr/share/themes
            priv cp -r "$HOME/.themes/$GTK_THEME_NAME" /usr/share/themes/
            log_ok "GTK theme copied to /usr/share/themes/$GTK_THEME_NAME"
        else
            log_warn "No Catppuccin GTK theme found in ~/.themes — run 21-theme-catppuccin.sh first for this to have"
            log_warn "something to copy. Leaving the greeter on its default theme for now."
        fi

        ICON_THEME_NAME=""
        for candidate in "Catppuccin-SE-Local" "Catppuccin-SE"; do
            if [[ -d "$HOME/.local/share/icons/$candidate" ]]; then
                priv mkdir -p /usr/share/icons
                priv cp -r "$HOME/.local/share/icons/$candidate" /usr/share/icons/
                ICON_THEME_NAME="$candidate"
                log_ok "Icon theme copied to /usr/share/icons/$candidate"
                break
            fi
        done

        CURSOR_THEME_NAME=$(find "$HOME/.icons" -maxdepth 1 -type d -iname "*mocha*red*cursor*" -printf '%f\n' 2>/dev/null | head -1)
        if [[ -n "$CURSOR_THEME_NAME" && -d "$HOME/.icons/$CURSOR_THEME_NAME" ]]; then
            priv mkdir -p /usr/share/icons
            priv cp -r "$HOME/.icons/$CURSOR_THEME_NAME" /usr/share/icons/
            log_ok "Cursor theme copied to /usr/share/icons/$CURSOR_THEME_NAME"
        fi

        # Greeter background: reuse the desktop wallpaper. The greeter user
        # cannot read $HOME, so the image is staged world-readable under
        # /usr/share/backgrounds (the FHS home for exactly this).
        GREETER_BG=""
        for candidate in "$HOME/.config/xfce4/backdrops" "$HOME/Pictures" "$HOME/.local/share/backgrounds"; do
            found=$(find "$candidate" -maxdepth 2 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -1)
            if [[ -n "$found" ]]; then
                priv mkdir -p /usr/share/backgrounds
                priv cp "$found" /usr/share/backgrounds/xfce-catppuccin-login$(echo "$found" | grep -qi png && echo ".png" || echo ".jpg")
                priv chmod 644 /usr/share/backgrounds/xfce-catppuccin-login.* 2>/dev/null || true
                GREETER_BG=$(ls /usr/share/backgrounds/xfce-catppuccin-login.* 2>/dev/null | head -1)
                log_ok "Login background staged at $GREETER_BG"
                break
            fi
        done
        [[ -z "$GREETER_BG" ]] && log_warn "No wallpaper found to reuse — greeter keeps its default background."

        GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
        [[ -f "$GREETER_CONF" ]] && priv cp "$GREETER_CONF" "${GREETER_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        {
            echo "[greeter]"
            [[ -n "$GTK_THEME_NAME" ]] && echo "theme-name = $GTK_THEME_NAME"
            [[ -n "$ICON_THEME_NAME" ]] && echo "icon-theme-name = $ICON_THEME_NAME"
            [[ -n "$CURSOR_THEME_NAME" ]] && echo "cursor-theme-name = $CURSOR_THEME_NAME"
            echo "font-name = Sans 10"
            [[ -n "$GREETER_BG" ]] && echo "background = $GREETER_BG"
            # user-background=false: xfdesktop would otherwise swap our staged
            # art for the selected user's own wallpaper after their first login
            # (with the login box still parked where our artwork wants it).
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
        # Greeter login-box styling: Catppuccin Red shim over the dark GTK
        # theme (source of truth: configs/lightdm/gtk.css). The greeter runs
        # as user lightdm, so the file must live under /var/lib/lightdm and
        # be owned by lightdm — otherwise it silently gets ignored.
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

        # NumLock on at the login prompt when numlockx exists (21-* offers it)
        LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
        if command -v numlockx &>/dev/null; then
            [[ -f "$LIGHTDM_CONF" ]] && priv cp "$LIGHTDM_CONF" "${LIGHTDM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
            if grep -q "^greeter-setup-script" "$LIGHTDM_CONF" 2>/dev/null; then
                priv sed -i 's|^greeter-setup-script.*|greeter-setup-script=/usr/bin/numlockx on|' "$LIGHTDM_CONF"
            else
                printf '\n[Seat:*]\ngreeter-setup-script=/usr/bin/numlockx on\n' | priv tee -a "$LIGHTDM_CONF" >/dev/null
            fi
            log_ok "NumLock enabled at the login prompt."
        fi
        log_warn "Takes effect at next login/reboot — restarting the display manager now would end this session."
    fi
else
    log_warn "lightdm-gtk-greeter isn't installed — skipping greeter theming."
fi

echo
log_ok "Boot → login theming pass complete. Reboot to see all three."
