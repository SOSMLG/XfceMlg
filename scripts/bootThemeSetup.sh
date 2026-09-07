#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  bootThemeSetup.sh — the part before you see the desktop
#
#  catppuccinTheme.sh handles everything *inside* the session.
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
#  Privilege: sudo
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
command -v sudo &>/dev/null || fatal "sudo not found — this script needs it to touch system files."

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo -e "\n${B}${W}══════ Boot → Login Theming (Catppuccin Mocha) ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

# ══════════════════════════════════════════════════════════════
step "1/3  Plymouth boot splash"
# ══════════════════════════════════════════════════════════════
if ask "Install the Catppuccin Plymouth splash (shown while the kernel boots)?"; then
    sudo apt-get install -y plymouth plymouth-themes || warn "Plymouth package install had issues — continuing."

    if git clone --depth=1 https://github.com/catppuccin/plymouth.git "$WORK_DIR/plymouth" 2>/tmp/catppuccin-plymouth-clone.log; then
        if [[ -d "$WORK_DIR/plymouth/themes/catppuccin-mocha" ]]; then
            sudo mkdir -p /usr/share/plymouth/themes
            sudo cp -r "$WORK_DIR/plymouth/themes/catppuccin-mocha" /usr/share/plymouth/themes/
            ok "Theme files copied to /usr/share/plymouth/themes/catppuccin-mocha"

            APPLIED=0
            if command -v plymouth-set-default-theme &>/dev/null; then
                # -R also rebuilds the initramfs — one command does both.
                if sudo plymouth-set-default-theme -R catppuccin-mocha 2>/tmp/plymouth-set-theme.log; then
                    APPLIED=1
                fi
            fi
            if [[ $APPLIED -eq 0 ]]; then
                info "plymouth-set-default-theme unavailable/failed — using update-alternatives instead."
                sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
                    default.plymouth /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth 200 \
                    && sudo update-alternatives --set default.plymouth \
                        /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth \
                    && sudo update-initramfs -u \
                    && APPLIED=1
            fi

            if [[ $APPLIED -eq 1 ]]; then
                ok "Plymouth theme set to catppuccin-mocha."
                # Plymouth only actually shows unless the kernel cmdline
                # asks for it — add splash/quiet if they're not already
                # there, don't touch anything else on the line.
                GRUB_DEFAULT="/etc/default/grub"
                if [[ -f "$GRUB_DEFAULT" ]]; then
                    sudo cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
                    LINE=$(grep -m1 '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT" || true)
                    if [[ -n "$LINE" ]]; then
                        NEEDS_UPDATE=0
                        NEW_LINE="$LINE"
                        [[ "$NEW_LINE" != *"splash"* ]] && { NEW_LINE="${NEW_LINE%\"}"; NEW_LINE="${NEW_LINE} splash\""; NEEDS_UPDATE=1; }
                        [[ "$NEW_LINE" != *"quiet"* ]] && { NEW_LINE="${NEW_LINE%\"}"; NEW_LINE="${NEW_LINE} quiet\""; NEEDS_UPDATE=1; }
                        if [[ $NEEDS_UPDATE -eq 1 ]]; then
                            sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|${NEW_LINE}|" "$GRUB_DEFAULT"
                            ok "Added splash/quiet to GRUB_CMDLINE_LINUX_DEFAULT (backup saved alongside it)."
                        fi
                    else
                        echo 'GRUB_CMDLINE_LINUX_DEFAULT="splash quiet"' | sudo tee -a "$GRUB_DEFAULT" > /dev/null
                        ok "Added GRUB_CMDLINE_LINUX_DEFAULT with splash/quiet."
                    fi
                    if command -v update-grub &>/dev/null; then
                        sudo update-grub || warn "update-grub failed — run it yourself once you've checked $GRUB_DEFAULT"
                    fi
                else
                    warn "No /etc/default/grub found — if this system doesn't use GRUB, add 'splash quiet' to your bootloader's kernel cmdline manually."
                fi
                warn "You won't see this until your next real reboot — a logout doesn't touch it."
            else
                err "Couldn't apply the Plymouth theme. Log: /tmp/plymouth-set-theme.log"
            fi
        else
            err "Cloned catppuccin/plymouth but themes/catppuccin-mocha wasn't there — upstream layout may have changed."
        fi
    else
        err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-plymouth-clone.log"
    fi
else
    warn "Skipped Plymouth."
fi

# ══════════════════════════════════════════════════════════════
step "2/3  GRUB menu theme"
# ══════════════════════════════════════════════════════════════
if ! command -v update-grub &>/dev/null && [[ ! -d /boot/grub ]]; then
    warn "This system doesn't appear to use GRUB — skipping (nothing to do, not an error)."
elif ask "Install the Catppuccin GRUB theme (only matters if you actually see the GRUB menu)?"; then
    if git clone --depth=1 https://github.com/catppuccin/grub.git "$WORK_DIR/grub" 2>/tmp/catppuccin-grub-clone.log; then
        THEME_TXT=$(find "$WORK_DIR/grub" -maxdepth 3 -iname "theme.txt" -ipath "*mocha*" | head -1)
        if [[ -n "$THEME_TXT" ]]; then
            THEME_DIR=$(dirname "$THEME_TXT")
            THEME_NAME=$(basename "$THEME_DIR")
            sudo mkdir -p /usr/share/grub/themes
            sudo cp -r "$THEME_DIR" "/usr/share/grub/themes/"
            ok "GRUB theme copied to /usr/share/grub/themes/$THEME_NAME"

            GRUB_DEFAULT="/etc/default/grub"
            if [[ -f "$GRUB_DEFAULT" ]]; then
                sudo cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
                THEME_LINE="GRUB_THEME=\"/usr/share/grub/themes/${THEME_NAME}/theme.txt\""
                if grep -q '^GRUB_THEME=' "$GRUB_DEFAULT"; then
                    sudo sed -i "s|^GRUB_THEME=.*|${THEME_LINE}|" "$GRUB_DEFAULT"
                elif grep -q '^#GRUB_THEME=' "$GRUB_DEFAULT"; then
                    sudo sed -i "s|^#GRUB_THEME=.*|${THEME_LINE}|" "$GRUB_DEFAULT"
                else
                    echo "$THEME_LINE" | sudo tee -a "$GRUB_DEFAULT" > /dev/null
                fi
                # GRUB_TERMINAL_OUTPUT=console (if set) suppresses the
                # graphical theme entirely — a common "theme installed
                # but GRUB still looks stock" cause.
                sudo sed -i 's/^GRUB_TERMINAL_OUTPUT=console/#GRUB_TERMINAL_OUTPUT=console/' "$GRUB_DEFAULT"

                if command -v update-grub &>/dev/null; then
                    if sudo update-grub; then
                        ok "GRUB theme applied ($THEME_NAME). You'll see it next time GRUB's menu actually shows."
                    else
                        err "update-grub failed — check $GRUB_DEFAULT for typos before rebooting."
                    fi
                fi
            else
                warn "No /etc/default/grub found — theme files are in place but not wired up."
            fi
        else
            err "Cloned catppuccin/grub but couldn't find a Mocha theme.txt in it — upstream layout may have changed."
        fi
    else
        err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-grub-clone.log"
    fi
else
    warn "Skipped GRUB theme."
fi

# ══════════════════════════════════════════════════════════════
step "3/3  LightDM login screen"
# ══════════════════════════════════════════════════════════════
if ! dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
    warn "LightDM isn't installed — skipping (if you use a different display manager, this script doesn't know its config format)."
elif ! command -v lightdm-gtk-greeter 2>/dev/null && ! dpkg -l lightdm-gtk-greeter 2>/dev/null | grep -q '^ii'; then
    sudo apt-get install -y lightdm-gtk-greeter || warn "Couldn't install lightdm-gtk-greeter — skipping greeter theming."
fi

if dpkg -l lightdm-gtk-greeter 2>/dev/null | grep -q '^ii'; then
    if ask "Theme the LightDM login screen to match (copies your already-installed GTK theme system-wide)?"; then
        # The greeter runs as its own system user with no access to your
        # $HOME, so ~/.themes doesn't exist as far as it's concerned —
        # everything has to actually live under /usr/share.
        GTK_THEME_NAME=$(find "$HOME/.themes" -maxdepth 1 -type d -iname "*catppuccin*red*dark*" -printf '%f\n' 2>/dev/null | head -1)
        [[ -z "$GTK_THEME_NAME" ]] && GTK_THEME_NAME=$(find "$HOME/.themes" -maxdepth 1 -type d -iname "*catppuccin*" -printf '%f\n' 2>/dev/null | head -1)

        if [[ -n "$GTK_THEME_NAME" && -d "$HOME/.themes/$GTK_THEME_NAME" ]]; then
            sudo mkdir -p /usr/share/themes
            sudo cp -r "$HOME/.themes/$GTK_THEME_NAME" /usr/share/themes/
            ok "GTK theme copied to /usr/share/themes/$GTK_THEME_NAME"
        else
            warn "No Catppuccin GTK theme found in ~/.themes — run catppuccinTheme.sh first for this to have"
            warn "something to copy. Leaving the greeter on its default theme for now."
        fi

        ICON_THEME_NAME=""
        for candidate in "Catppuccin-SE-Local" "Catppuccin-SE"; do
            if [[ -d "$HOME/.local/share/icons/$candidate" ]]; then
                sudo mkdir -p /usr/share/icons
                sudo cp -r "$HOME/.local/share/icons/$candidate" /usr/share/icons/
                ICON_THEME_NAME="$candidate"
                ok "Icon theme copied to /usr/share/icons/$candidate"
                break
            fi
        done

        CURSOR_THEME_NAME=$(find "$HOME/.icons" -maxdepth 1 -type d -iname "*mocha*red*cursor*" -printf '%f\n' 2>/dev/null | head -1)
        if [[ -n "$CURSOR_THEME_NAME" && -d "$HOME/.icons/$CURSOR_THEME_NAME" ]]; then
            sudo mkdir -p /usr/share/icons
            sudo cp -r "$HOME/.icons/$CURSOR_THEME_NAME" /usr/share/icons/
            ok "Cursor theme copied to /usr/share/icons/$CURSOR_THEME_NAME"
        fi

        GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
        [[ -f "$GREETER_CONF" ]] && sudo cp "$GREETER_CONF" "${GREETER_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        {
            echo "[greeter]"
            [[ -n "$GTK_THEME_NAME" ]] && echo "theme-name = $GTK_THEME_NAME"
            [[ -n "$ICON_THEME_NAME" ]] && echo "icon-theme-name = $ICON_THEME_NAME"
            [[ -n "$CURSOR_THEME_NAME" ]] && echo "cursor-theme-name = $CURSOR_THEME_NAME"
            echo "font-name = Sans 10"
        } | sudo tee "$GREETER_CONF" > /dev/null
        ok "Wrote $GREETER_CONF"
        warn "Takes effect at next login/reboot — restarting the display manager now would end this session."
    fi
else
    warn "lightdm-gtk-greeter isn't installed — skipping greeter theming."
fi

echo
ok "Boot → login theming pass complete. Reboot to see all three."
