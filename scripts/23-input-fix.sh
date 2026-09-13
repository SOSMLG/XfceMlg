#!/usr/bin/env bash
# DEBSWAY_DESC: Input fixes + screen locker + Super shortcuts
# DEBSWAY_DEFAULT: Y
#  23-input-fix.sh — USB HID polling + libinput tuning
#  Core fix: raise the USB HID mouse polling rate, the classic
#  fix for laggy/jumpy USB-attached trackpoints & touchpads
#  (many ThinkPads ride on usbhid).
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






log_head "1/3  USB HID mouse polling rate"
MODPROBE_FILE="/etc/modprobe.d/mousepoll.conf"

if [[ -f "$MODPROBE_FILE" ]] && grep -q "mousepoll=2" "$MODPROBE_FILE" 2>/dev/null; then
    log_ok "$MODPROBE_FILE already sets mousepoll=2, skipping."
else
    if [[ -f "$MODPROBE_FILE" ]]; then
        BACKUP="${MODPROBE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        priv cp "$MODPROBE_FILE" "$BACKUP"
        log_info "Existing $MODPROBE_FILE backed up to $BACKUP"
    fi

    echo "options usbhid mousepoll=2" | priv tee "$MODPROBE_FILE" > /dev/null
    log_ok "Wrote $MODPROBE_FILE (options usbhid mousepoll=2)"

    if command -v update-initramfs &>/dev/null; then
        log_info "Updating initramfs..."
        priv update-initramfs -u || log_warn "update-initramfs failed (non-fatal)."
    fi

    log_info "Attempting to reload usbhid now (may briefly disconnect USB input devices)..."
    if priv modprobe -r usbhid 2>/dev/null && priv modprobe usbhid 2>/dev/null; then
        log_ok "usbhid reloaded, fix is active immediately."
    else
        log_warn "Could not hot-reload usbhid. A reboot will apply it."
    fi
fi

log_head "2/3  libinput tuning (optional)"
if ask "Apply sane libinput defaults (tap-to-click on, natural scroll off)?" "N"; then
    XORG_CONF_DIR="/etc/X11/xorg.conf.d"
    XORG_CONF_FILE="$XORG_CONF_DIR/30-touchpad.conf"
    priv mkdir -p "$XORG_CONF_DIR"

    if [[ -f "$XORG_CONF_FILE" ]]; then
        BACKUP="${XORG_CONF_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        priv cp "$XORG_CONF_FILE" "$BACKUP"
        log_info "Existing $XORG_CONF_FILE backed up to $BACKUP"
    fi

    priv tee "$XORG_CONF_FILE" > /dev/null << 'EOF'
Section "InputClass"
    Identifier "libinput touchpad defaults"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "false"
    Option "DisableWhileTyping" "true"
    Option "ClickMethod" "clickfinger"
EndSection

Section "InputClass"
    Identifier "libinput pointstick defaults"
    MatchIsPointer "on"
    MatchProduct "TrackPoint|trackpoint|Trackpoint|DualPoint Stick"
    Driver "libinput"
    Option "AccelSpeed" "0.3"
EndSection
EOF
    log_ok "Wrote $XORG_CONF_FILE"
    log_warn "XFCE's own Settings > Mouse and Touchpad panel (libinput-based) covers the same ground"
    log_warn "graphically if you'd rather use that instead."
fi

log_head "3/3  Screen locker + Super shortcuts (Butterbian set, adapted)"
# Butterbian wires Ctrl+Alt+L to xflock4 but the locker itself must be
# installed or the shortcut silently does nothing — ensure light-locker
# here even if 10-xfce-core.sh was skipped.
install_pkgs "Screen locker" light-locker || true

# Super-based shortcuts, applied idempotently via xfconf: create each
# property only when missing, never overwrite an existing user binding.
# (Same respect-user-choice rule as the wallpaper seeder in 35-*.)
bind_key() {  # bind_key <channel> <property> <command>
    local channel="$1" prop="$2" cmd="$3" current
    current="$(xfconf-query -c "$channel" -p "$prop" 2>/dev/null || true)"
    if [ "$current" = "$cmd" ]; then
        return 0
    elif [ -n "$current" ]; then
        log_warn "Keeping your existing binding: $prop → $current"
        return 0
    fi
    if xfconf-query -c "$channel" -p "$prop" -n -t string -s "$cmd" 2>/dev/null; then
        log_ok "Bound $prop → $cmd"
    else
        log_warn "Could not bind $prop (xfconf not responding?)."
    fi
}

if command -v xfconf-query &>/dev/null && ask "Install the Super-based shortcut set (terminal, files, screenshots, tiling, workspaces) + Ctrl+Alt+L lock?"; then
    # -- lock + launcher basics (commands channel) --
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Primary><Alt>l" "xflock4"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Super>Return" "exo-open --launch TerminalEmulator"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Super>f" "thunar"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Super>space" "xfce4-appfinder"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Super>s" "xfce4-screenshooter"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Shift><Super>s" "xfce4-screenshooter -r"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Alt><Super>s" "xfce4-screenshooter -w"
    bind_key xfce4-keyboard-shortcuts "/commands/custom/<Super>v" "xfce4-popup-clipman"
    # -- window actions (xfwm4 channel) --
    bind_key xfce4-keyboard-shortcuts "/xfwm4/custom/<Super>q" "close_window_key"
    bind_key xfce4-keyboard-shortcuts "/xfwm4/custom/<Super>Up" "tile_up_key"
    bind_key xfce4-keyboard-shortcuts "/xfwm4/custom/<Super>Down" "tile_down_key"
    bind_key xfce4-keyboard-shortcuts "/xfwm4/custom/<Super>Left" "tile_left_key"
    bind_key xfce4-keyboard-shortcuts "/xfwm4/custom/<Super>Right" "tile_right_key"
    for n in 1 2 3 4 5 6 7 8 9 0; do
        ws="${n}"; [ "$n" = "0" ] && ws="10"
        bind_key xfce4-keyboard-shortcuts "/xfwm4/custom/<Super>${n}" "workspace_${ws}_key"
    done
else
    log_info "Skipped the shortcut set — defaults stay as XFCE shipped them."
fi

log_ok "Touchpad/trackpoint fix complete."
log_warn "A reboot is recommended to guarantee the mousepoll fix is fully applied."
