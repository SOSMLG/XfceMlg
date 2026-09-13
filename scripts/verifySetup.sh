#!/usr/bin/env bash
# =======================================================
# Verify Setup — end-state audit (XFCE edition)
# -------------------------------------------------------
# One-pass check of the toolkit's expected end state:
# group membership, key packages, fonts, Firefox policy,
# Catppuccin theme markers, Thunar plugins, LightDM config,
# and enabled services. Designed to be run from
# run.sh --verify after a run, or standalone at any time.
#
# Prints PASS/FAIL/WARN lines and exits non-zero if any
# critical check failed, so it can gate CI/validation.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PASS=0; FAIL=0; WARN=0

report() {  # report <name> <status> <detail>
    case "$2" in
        ok)
            printf '  PASS  %-48s %s\n' "$1" "${3:-}"
            PASS=$((PASS + 1))
            ;;
        fail)
            printf '  FAIL  %-48s %s\n' "$1" "${3:-}"
            FAIL=$((FAIL + 1))
            ;;
        warn)
            printf '  WARN  %-48s %s\n' "$1" "${3:-}"
            WARN=$((WARN + 1))
            ;;
    esac
}

pkg() {  # pkg <name> [critical|optional]
    local name="$1" level="${2:-critical}"
    local state detail
    if is_installed "$name"; then
        state="ok"; detail="installed"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="not installed (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "$name" "$state" "$detail"
}

bin() {  # bin <command> [critical|optional]
    local name="$1" level="${2:-critical}"
    local state detail
    if command -v "$name" >/dev/null 2>&1; then
        state="ok"; detail="$(command -v "$name")"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="not installed (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "bin: $name" "$state" "$detail"
}

cfg() {  # cfg <label> <path> [critical|optional]
    local label="$1" path="$2" level="${3:-critical}"
    local state detail
    if [ -e "$path" ]; then
        state="ok"; detail="present"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="missing (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "cfg: $label" "$state" "$detail"
}

# service_state: enabled under OpenRC (rc-update) or systemd; running via process name.
service_state() {
    local svc="$1" procname="$2" level="${3:-fail}"
    local enabled="" running=""
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        if systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-enabled "${svc}.service" >/dev/null 2>&1; then
            enabled="systemd"
        fi
    elif command -v rc-update >/dev/null 2>&1; then
        if rc-update show 2>/dev/null | awk -v s="$svc" '$1==s{found=1} END{exit !found}'; then
            enabled="openrc"
        fi
    fi
    pgrep -x "$procname" >/dev/null 2>&1 && running="yes"

    if [ -n "$running" ]; then
        report "$svc (service)" ok "${enabled:-running, not enabled}"
    elif [ -n "$enabled" ]; then
        report "$svc (service)" ok "enabled, not running (reboot or start it)"
    elif [ "$level" = "optional" ]; then
        report "$svc (service)" warn "not running"
    else
        report "$svc (service)" fail "not running"
    fi
}

log_head "Setup verification"

echo -e "  (user: ${CYAN}${ACTUAL_USER}${NC})\n"

# --- 1. Group membership ------------------------------------------------
for g in input video render plugdev bluetooth lpadmin; do
    if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
        report "group: $g" ok
    else
        report "group: $g" warn "user not in $g (re-run 12-user-groups.sh / 14-bluetooth.sh / 30-desktop-essentials.sh)"
    fi
done

# --- 2. Lean core: session, WM, panel, terminal, DM ----------------------
pkg xorg
pkg xfce4-session
pkg xfwm4
pkg xfce4-panel
pkg xfce4-settings
pkg xfce4-terminal
pkg lightdm
pkg lightdm-gtk-greeter
pkg dbus-x11
pkg xfce-polkit

# SLiM must NOT be present (tasksel leftover fights LightDM)
if is_installed slim; then
    report "slim absent" fail "installed — purge it (10-xfce-core.sh) so it can't fight LightDM"
else
    report "slim absent" ok
fi

# --- 3. Thunar full set --------------------------------------------------
pkg thunar
pkg thunar-volman
pkg thunar-archive-plugin
pkg thunar-media-tags-plugin
pkg thunar-vcs-plugin
pkg thunar-gtkhash
pkg xarchiver
pkg tumbler
pkg gvfs-backends
pkg udisks2
cfg "Thunar custom actions" "$HOME/.config/Thunar/uca.xml" optional

# --- 4. Desktop apps & essentials ----------------------------------------
pkg xfce4-power-manager
pkg xfce4-notifyd
pkg xfce4-screenshooter
pkg xfce4-pulseaudio-plugin
pkg xfce4-taskmanager
pkg light-locker
pkg lightdm-gtk-greeter-settings optional
pkg pavucontrol optional
pkg smbclient optional
pkg cifs-utils optional
bin xflock4
pkg xfce4-clipman-plugin optional
pkg ristretto optional
pkg atril optional
pkg vlc optional
pkg firefox-esr
pkg flatpak
pkg timeshift
pkg redshift optional
pkg network-manager optional
pkg chrony optional
pkg tlp optional
pkg fwupd optional
pkg ffmpeg
pkg fonts-noto-color-emoji
pkg fastfetch optional
pkg codium optional
bin gcc optional
bin g++ optional
pkg python3-numpy optional
pkg python3-matplotlib optional
bin nvim optional
pkg steam optional
pkg heroic optional
pkg gimp optional

# --- 5. Fonts -------------------------------------------------------------
if [ -n "$(fc-list 2>/dev/null | grep -i "JetBrainsMono Nerd Font")" ]; then
    report "JetBrainsMono Nerd Font" ok
else
    report "JetBrainsMono Nerd Font" fail "not found — re-run 17-fonts.sh"
fi

# --- 6. Firefox policy ----------------------------------------------------
if [ -f /usr/lib/firefox-esr/distribution/policies.json ]; then
    report "Firefox policies.json" ok
else
    report "Firefox policies.json" warn "not installed (re-run 16-firefox.sh)"
fi
if [ -f /etc/firefox-esr/devuan-xfce-setup.js ]; then
    report "Firefox Betterfox defaults" ok
else
    report "Firefox Betterfox defaults" warn "not installed (re-run 16-firefox.sh)"
fi

# --- 7. Catppuccin theme markers -------------------------------------------
if ls -d "$HOME/.themes/"*catppuccin* >/dev/null 2>&1; then
    report "Catppuccin GTK theme" ok
else
    report "Catppuccin GTK theme" fail "missing — re-run 21-theme-catppuccin.sh"
fi
if [ -d "$HOME/.local/share/icons/Catppuccin-SE-Local" ] || [ -d "$HOME/.local/share/icons/Catppuccin-SE" ]; then
    report "Catppuccin icons" ok
else
    report "Catppuccin icons" fail "missing — re-run 21-theme-catppuccin.sh"
fi
if [ -f "$HOME/.config/xfce4/terminal/terminalrc" ] && grep -q "ColorCursor" "$HOME/.config/xfce4/terminal/terminalrc"; then
    report "xfce4-terminal theme" ok
else
    report "xfce4-terminal theme" fail "missing — re-run 21-theme-catppuccin.sh"
fi
if grep -q "TerminalEmulator=xfce4-terminal" "$HOME/.config/xfce4/helpers.rc" 2>/dev/null; then
    report "default terminal" ok "xfce4-terminal"
else
    report "default terminal" warn "not set to xfce4-terminal (re-run 21-theme-catppuccin.sh)"
fi
if [ -f /etc/lightdm/lightdm-gtk-greeter.conf ] && grep -q "^\[greeter\]" /etc/lightdm/lightdm-gtk-greeter.conf; then
    report "LightDM greeter themed" ok
else
    report "LightDM greeter themed" warn "not themed (re-run 22-theme-boot.sh)"
fi
if grep -q "^user-background = false" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
    report "greeter keeps staged art" ok "user-background = false"
else
    report "greeter keeps staged art" warn "user-background not pinned (re-run 22-theme-boot.sh)"
fi
if [ -f /var/lib/lightdm/.config/gtk-3.0/gtk.css ]; then
    report "greeter login-box CSS" ok
else
    report "greeter login-box CSS" warn "missing (re-run 22-theme-boot.sh)"
fi

# --- 8. Services -----------------------------------------------------------
service_state lightdm lightdm critical
service_state bluetooth bluetoothd optional
service_state tlp tlp optional
service_state cups cupsd optional
service_state chrony chronyd optional
service_state NetworkManager NetworkManager optional

echo
echo -e "${GREEN}  ${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo
    log_err "Some checks failed — see lines above, then re-run the relevant script."
    exit 1
fi
exit 0
