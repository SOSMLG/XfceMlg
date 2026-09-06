#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  bluetoothSetup.sh — make Bluetooth (and Bluetooth *audio*)
#  actually work out of the box under XFCE.
#
#  hardwareSupport.sh already covers the firmware blob side of
#  "Bluetooth doesn't work" (missing firmware-*). This script
#  covers everything above the firmware layer, which is the part
#  that actually breaks earbuds/headsets day-to-day:
#    - bluez + bluez-tools + rfkill (core stack, unblock radio)
#    - blueman (GUI manager + system-tray applet, autostarted —
#      XFCE ships no Bluetooth GUI of its own)
#    - the audio *bridge* between BlueZ and whichever sound
#      server is actually running: pulseaudio-module-bluetooth
#      for PulseAudio, or the pipewire bluez5 backend for
#      PipeWire — auto-detected, not assumed
#    - GStreamer's PulseAudio/PipeWire sink + the codec plugins
#      (gstreamer1.0-plugins-good/bad) apps like Rhythmbox/
#      Totem/Parole route audio playback through
#    - bluetoothd "Experimental = true", which is what lets
#      BlueZ negotiate the better A2DP codecs (AAC/aptX/LDAC)
#      instead of silently falling back to low-quality SBC
#
#  Without the audio-bridge package, Bluetooth *pairs* fine but
#  earbuds never show up as an audio output — that mismatch is
#  the single most common "my Bluetooth headphones don't work"
#  report, and it's a missing package, not a driver bug.
#
#  Privilege: sudo (packages + main.conf only; nothing here
#  touches your keyring/paired-devices state)
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
command -v sudo &>/dev/null || fatal "sudo not found — this script needs it to install packages."

REAL_USER="${SUDO_USER:-$USER}"

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        ok "$label already installed."
        return 0
    fi
    info "$label: installing ${to_install[*]}"
    if sudo apt-get install -y "${to_install[@]}"; then
        ok "$label installed."
        return 0
    else
        warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

enable_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now "$svc" &>/dev/null || warn "Couldn't enable/start $svc via systemctl."
    else
        sudo service "$svc" start &>/dev/null || warn "Couldn't start $svc via service(8)."
        sudo update-rc.d "$svc" defaults &>/dev/null || true
    fi
}

restart_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl restart "$svc" &>/dev/null || true
    else
        sudo service "$svc" restart &>/dev/null || true
    fi
}

echo -e "\n${B}${W}══════ Bluetooth (stack + audio) ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

# ══════════════════════════════════════════════════════════════
step "1/5  Core Bluetooth stack"
# ══════════════════════════════════════════════════════════════
install_pkgs "Bluetooth core" bluez bluez-tools rfkill
enable_service bluetooth

if command -v rfkill &>/dev/null; then
    if rfkill list bluetooth 2>/dev/null | grep -qi "blocked: yes"; then
        info "Bluetooth radio is rfkill-blocked — unblocking..."
        sudo rfkill unblock bluetooth && ok "Bluetooth unblocked." || warn "Couldn't unblock via rfkill (check for a hardware kill switch/BIOS setting)."
    else
        ok "Bluetooth radio is not rfkill-blocked."
    fi
fi

if getent group bluetooth &>/dev/null; then
    if id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx bluetooth; then
        ok "$REAL_USER already in the 'bluetooth' group."
    else
        sudo usermod -aG bluetooth "$REAL_USER" \
            && ok "Added $REAL_USER to the 'bluetooth' group (takes effect next login)." \
            || warn "Couldn't add $REAL_USER to 'bluetooth' group."
    fi
fi

# ══════════════════════════════════════════════════════════════
step "2/5  Audio bridge (BlueZ ↔ your sound server)"
# ══════════════════════════════════════════════════════════════
# This is the package people forget: without it, devices *pair*
# but never appear as a selectable audio output/input. Detect
# which sound server actually owns the audio session instead of
# assuming — a Devuan/XFCE box may run either.
AUDIO_SERVER="none"
if pgrep -x pipewire &>/dev/null || is_installed pipewire; then
    AUDIO_SERVER="pipewire"
elif pgrep -x pulseaudio &>/dev/null || is_installed pulseaudio; then
    AUDIO_SERVER="pulseaudio"
fi

case "$AUDIO_SERVER" in
    pipewire)
        info "Detected PipeWire — installing its BlueZ backend."
        install_pkgs "PipeWire Bluetooth backend" \
            libspa-0.2-bluetooth pipewire-audio-client-libraries wireplumber
        ;;
    pulseaudio)
        info "Detected PulseAudio — installing pulseaudio-module-bluetooth."
        install_pkgs "PulseAudio Bluetooth module" pulseaudio-module-bluetooth
        ;;
    none)
        warn "No sound server detected running or installed yet."
        info "Installing PulseAudio's Bluetooth module as a safe default (PulseAudio is what Devuan/XFCE installs by default without systemd)."
        install_pkgs "PulseAudio + Bluetooth module" pulseaudio pulseaudio-module-bluetooth
        AUDIO_SERVER="pulseaudio"
        ;;
esac

# GStreamer needs to be able to actually reach whatever sound
# server ended up in charge, or apps built on it (Rhythmbox,
# Totem, Parole, browsers) play silently to nowhere over BT.
install_pkgs "GStreamer audio-sink + codec plugins" \
    gstreamer1.0-pulseaudio gstreamer1.0-plugins-good gstreamer1.0-plugins-bad

# ══════════════════════════════════════════════════════════════
step "3/5  Better-than-SBC codecs (AAC/aptX/LDAC negotiation)"
# ══════════════════════════════════════════════════════════════
if ask "Enable BlueZ's experimental features (better codec negotiation for earbuds — AAC/aptX/LDAC instead of falling back to SBC)?"; then
    MAIN_CONF="/etc/bluetooth/main.conf"
    if [[ -f "$MAIN_CONF" ]]; then
        sudo cp "$MAIN_CONF" "${MAIN_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        if grep -q "^Experimental" "$MAIN_CONF"; then
            sudo sed -i 's/^Experimental.*/Experimental = true/' "$MAIN_CONF"
        elif grep -q "^\[General\]" "$MAIN_CONF"; then
            sudo sed -i '/^\[General\]/a Experimental = true' "$MAIN_CONF"
        else
            printf '[General]\nExperimental = true\n' | sudo tee -a "$MAIN_CONF" >/dev/null
        fi
        restart_service bluetooth
        ok "Experimental mode enabled in $MAIN_CONF and bluetoothd restarted."
    else
        warn "$MAIN_CONF not found — bluez packaging may have changed. Skipping."
    fi
else
    warn "Skipped — codec negotiation stays at BlueZ's conservative default (SBC-only in some cases)."
fi

# ══════════════════════════════════════════════════════════════
step "4/5  Blueman (GUI manager + tray applet)"
# ══════════════════════════════════════════════════════════════
if ask "Install Blueman (Bluetooth manager GUI + system-tray applet)?"; then
    if install_pkgs "Blueman" blueman; then
        mkdir -p "$HOME/.config/autostart"
        AUTOSTART_SRC="/etc/xdg/autostart/blueman.desktop"
        if [[ -f "$AUTOSTART_SRC" ]]; then
            cp "$AUTOSTART_SRC" "$HOME/.config/autostart/blueman.desktop"
        else
            cat > "$HOME/.config/autostart/blueman.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth Manager
Comment=Blueman applet — Bluetooth status/pairing icon in the panel tray
Exec=blueman-applet
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        fi
        # Start it now too, so it's there without a logout/login.
        (blueman-applet &>/dev/null &) || true
        ok "Blueman installed and set to autostart in the panel tray."
        info "Pair devices from the tray icon, or run: blueman-manager"
    fi
else
    warn "Skipped Blueman — you can still pair via 'bluetoothctl' from a terminal."
fi

# ══════════════════════════════════════════════════════════════
step "5/5  Restart audio + Bluetooth so changes take effect now"
# ══════════════════════════════════════════════════════════════
case "$AUDIO_SERVER" in
    pipewire)
        systemctl --user restart pipewire pipewire-pulse wireplumber &>/dev/null \
            || (pkill -x wireplumber; pkill -x pipewire; sleep 1; (pipewire &>/dev/null & disown); (pipewire-pulse &>/dev/null & disown); (wireplumber &>/dev/null & disown)) 2>/dev/null || true
        ;;
    pulseaudio)
        pulseaudio -k &>/dev/null || true
        (pulseaudio --start &>/dev/null &) || true
        ;;
esac
restart_service bluetooth

echo
ok "Bluetooth stack ready: $AUDIO_SERVER is the detected/installed audio backend."
echo -e "${C}Next: open Blueman (or 'bluetoothctl') → put your earbuds in pairing mode → pair, trust, connect.${Z}"
echo -e "${C}If audio still routes to speakers after connecting, pick the device manually in the volume tray's output dropdown.${Z}"
echo -e "${C}A full logout/login is recommended if this is the first time this account joined the 'bluetooth' group.${Z}"
