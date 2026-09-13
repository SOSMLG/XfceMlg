#!/usr/bin/env bash
# DEBSWAY_DESC: Bluetooth stack, Blueman GUI, audio bridging
# DEBSWAY_DEFAULT: Y
#  14-bluetooth.sh — make Bluetooth (and Bluetooth *audio*)
#  actually work out of the box under XFCE.
#
#  13-hardware.sh already covers the firmware blob side of
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
#  Privilege: priv() (doas-first, sudo fallback) (packages + main.conf only; nothing here
#  touches your keyring/paired-devices state)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root







enable_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        priv systemctl enable --now "$svc" &>/dev/null || log_warn "Couldn't enable/start $svc via systemctl."
    else
        priv service "$svc" start &>/dev/null || log_warn "Couldn't start $svc via service(8)."
        priv update-rc.d "$svc" defaults &>/dev/null || true
    fi
}

restart_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        priv systemctl restart "$svc" &>/dev/null || true
    else
        priv service "$svc" restart &>/dev/null || true
    fi
}

apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/5  Core Bluetooth stack"
install_pkgs "Bluetooth core" bluez bluez-tools rfkill
enable_service bluetooth

if command -v rfkill &>/dev/null; then
    if rfkill list bluetooth 2>/dev/null | grep -qi "blocked: yes"; then
        log_info "Bluetooth radio is rfkill-blocked — unblocking..."
        priv rfkill unblock bluetooth && log_ok "Bluetooth unblocked." || log_warn "Couldn't unblock via rfkill (check for a hardware kill switch/BIOS setting)."
    else
        log_ok "Bluetooth radio is not rfkill-blocked."
    fi
fi

if getent group bluetooth &>/dev/null; then
    if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx bluetooth; then
        log_ok "$ACTUAL_USER already in the 'bluetooth' group."
    else
        priv usermod -aG bluetooth "$ACTUAL_USER" \
            && log_ok "Added $ACTUAL_USER to the 'bluetooth' group (takes effect next login)." \
            || log_warn "Couldn't add $ACTUAL_USER to 'bluetooth' group."
    fi
fi

log_head "2/5  Audio bridge (BlueZ ↔ your sound server)"
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
        log_info "Detected PipeWire — installing its BlueZ backend."
        install_pkgs "PipeWire Bluetooth backend" \
            libspa-0.2-bluetooth pipewire-audio-client-libraries wireplumber
        ;;
    pulseaudio)
        log_info "Detected PulseAudio — installing pulseaudio-module-bluetooth."
        install_pkgs "PulseAudio Bluetooth module" pulseaudio-module-bluetooth
        ;;
    none)
        log_warn "No sound server detected running or installed yet."
        log_info "Installing PulseAudio's Bluetooth module as a safe default (PulseAudio is what Devuan/XFCE installs by default without systemd)."
        install_pkgs "PulseAudio + Bluetooth module" pulseaudio pulseaudio-module-bluetooth
        AUDIO_SERVER="pulseaudio"
        ;;
esac

# GStreamer needs to be able to actually reach whatever sound
# server ended up in charge, or apps built on it (Rhythmbox,
# Totem, Parole, browsers) play silently to nowhere over BT.
install_pkgs "GStreamer audio-sink + codec plugins" \
    gstreamer1.0-pulseaudio gstreamer1.0-plugins-good gstreamer1.0-plugins-bad

log_head "3/5  Better-than-SBC codecs (AAC/aptX/LDAC negotiation)"
if ask "Enable BlueZ's experimental features (better codec negotiation for earbuds — AAC/aptX/LDAC instead of falling back to SBC)?"; then
    MAIN_CONF="/etc/bluetooth/main.conf"
    if [[ -f "$MAIN_CONF" ]]; then
        priv cp "$MAIN_CONF" "${MAIN_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        if grep -q "^Experimental" "$MAIN_CONF"; then
            priv sed -i 's/^Experimental.*/Experimental = true/' "$MAIN_CONF"
        elif grep -q "^\[General\]" "$MAIN_CONF"; then
            priv sed -i '/^\[General\]/a Experimental = true' "$MAIN_CONF"
        else
            printf '[General]\nExperimental = true\n' | priv tee -a "$MAIN_CONF" >/dev/null
        fi
        restart_service bluetooth
        log_ok "Experimental mode enabled in $MAIN_CONF and bluetoothd restarted."
    else
        log_warn "$MAIN_CONF not found — bluez packaging may have changed. Skipping."
    fi
else
    log_warn "Skipped — codec negotiation stays at BlueZ's conservative default (SBC-only in some cases)."
fi

log_head "4/5  Blueman (GUI manager + tray applet) + volume control"
if ask "Install Blueman (Bluetooth manager GUI + system-tray applet) + pavucontrol (per-app volume/routing)?"; then
    install_pkgs "Volume control" pavucontrol || true
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
        log_ok "Blueman installed and set to autostart in the panel tray."
        log_info "Pair devices from the tray icon, or run: blueman-manager"
    fi
else
    log_warn "Skipped Blueman — you can still pair via 'bluetoothctl' from a terminal."
fi

log_head "5/5  Restart audio + Bluetooth so changes take effect now"
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
log_ok "Bluetooth stack ready: $AUDIO_SERVER is the detected/installed audio backend."
echo -e "Next: open Blueman (or 'bluetoothctl') → put your earbuds in pairing mode → pair, trust, connect."
echo -e "If audio still routes to speakers after connecting, pick the device manually in the volume tray's output dropdown."
echo -e "A full logout/login is recommended if this is the first time this account joined the 'bluetooth' group."
