#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  touchpadTrackpointFix.sh — USB HID polling + libinput tuning
#  Core fix: raise the USB HID mouse polling rate, the classic
#  fix for laggy/jumpy USB-attached trackpoints & touchpads
#  (many ThinkPads ride on usbhid).
#  Privilege: sudo
# ══════════════════════════════════════════════════════════════
set -euo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && err "Run this script as your normal user, not root."

command -v sudo &>/dev/null || err "sudo not found — this script needs it to install packages."

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo -e "\n${B}${W}══════ Touchpad / Trackpoint Fix ══════${Z}"

# ══════════════════════════════════════════════════════════════
step "1/2  USB HID mouse polling rate"
# ══════════════════════════════════════════════════════════════
MODPROBE_FILE="/etc/modprobe.d/mousepoll.conf"

if [[ -f "$MODPROBE_FILE" ]] && grep -q "mousepoll=2" "$MODPROBE_FILE" 2>/dev/null; then
    ok "$MODPROBE_FILE already sets mousepoll=2, skipping."
else
    if [[ -f "$MODPROBE_FILE" ]]; then
        BACKUP="${MODPROBE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$MODPROBE_FILE" "$BACKUP"
        info "Existing $MODPROBE_FILE backed up to $BACKUP"
    fi

    echo "options usbhid mousepoll=2" | sudo tee "$MODPROBE_FILE" > /dev/null
    ok "Wrote $MODPROBE_FILE (options usbhid mousepoll=2)"

    if command -v update-initramfs &>/dev/null; then
        info "Updating initramfs..."
        sudo update-initramfs -u || warn "update-initramfs failed (non-fatal)."
    fi

    info "Attempting to reload usbhid now (may briefly disconnect USB input devices)..."
    if sudo modprobe -r usbhid 2>/dev/null && sudo modprobe usbhid 2>/dev/null; then
        ok "usbhid reloaded, fix is active immediately."
    else
        warn "Could not hot-reload usbhid. A reboot will apply it."
    fi
fi

# ══════════════════════════════════════════════════════════════
step "2/2  libinput tuning (optional)"
# ══════════════════════════════════════════════════════════════
if ask "Apply sane libinput defaults (tap-to-click on, natural scroll off)?" "N"; then
    XORG_CONF_DIR="/etc/X11/xorg.conf.d"
    XORG_CONF_FILE="$XORG_CONF_DIR/30-touchpad.conf"
    sudo mkdir -p "$XORG_CONF_DIR"

    if [[ -f "$XORG_CONF_FILE" ]]; then
        BACKUP="${XORG_CONF_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$XORG_CONF_FILE" "$BACKUP"
        info "Existing $XORG_CONF_FILE backed up to $BACKUP"
    fi

    sudo tee "$XORG_CONF_FILE" > /dev/null << 'EOF'
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
    ok "Wrote $XORG_CONF_FILE"
    warn "XFCE's own Settings > Mouse and Touchpad panel (libinput-based) covers the same ground"
    warn "graphically if you'd rather use that instead."
fi

ok "Touchpad/trackpoint fix complete."
warn "A reboot is recommended to guarantee the mousepoll fix is fully applied."
