#!/usr/bin/env bash
# DEBSWAY_DESC: Audio/video codecs, DVD playback, Audacity/Shotcut
# DEBSWAY_DEFAULT: Y
# =======================================================
# Multimedia Codecs
# -------------------------------------------------------
# The single most common "why doesn't this just work like
# Mint" complaint: MP3s, H.264/H.265 video, and DVDs don't
# play out of the box on a stock Debian/Devuan install
# because the codecs are licensing-encumbered and live
# outside main. This installs the same practical set Mint's
# own "Install Multimedia Codecs" step pulls in.
#
# libdvd-pkg is the one genuine gotcha here: it builds
# libdvdcss from source via a debconf-driven postinst step
# that can sit waiting for input if not handled carefully.
# This runs it under DEBIAN_FRONTEND=noninteractive with a
# hard timeout, so the script can never hang indefinitely.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

log_head "Multimedia Codecs"


apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Core codec packages
# ---------------------------------------------------------------------------
if ask "Install audio/video codec packages (ffmpeg, GStreamer plugins)?"; then
    install_pkgs "Codec packages" \
        ffmpeg \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav libavcodec-extra
    # GPU video decode (YouTube etc. without it): va-driver-all pulls the
    # right VA-API driver per GPU (i965 for older Intel, intel-media for
    # newer, mesa-va for AMD). Do NOT add intel-media-va-driver-non-free —
    # it conflicts with the free driver and breaks pre-Broadwell Intel.
    install_pkgs "GPU video-accel drivers" \
        va-driver-all vdpau-driver-all mesa-va-drivers mesa-vdpau-drivers \
        libvdpau-va-gl1 || true
fi

# ---------------------------------------------------------------------------
# 2. DVD playback (libdvdcss, built from source by libdvd-pkg's postinst)
# ---------------------------------------------------------------------------
if ask "Install DVD playback support (libdvd-pkg)?"; then
    if is_installed libdvd-pkg && is_installed libdvdcss2; then
        log_ok "libdvd-pkg already installed and libdvdcss already built."
    else
        log_info "Installing libdvd-pkg..."
        if priv DEBIAN_FRONTEND=noninteractive apt-get install -y libdvd-pkg; then
            log_info "Building libdvdcss (this runs non-interactively, capped at 5 minutes)..."
            if priv timeout 300 env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg; then
                log_ok "libdvd-pkg configured."
            else
                log_warn "libdvd-pkg's build step timed out or failed."
                log_warn "Retry manually later with: doas dpkg-reconfigure libdvd-pkg"
            fi

            # The build produces a separate "libdvdcss2" package — its
            # presence is the real signal the build succeeded.
            if is_installed libdvdcss2; then
                log_ok "libdvdcss built successfully."
            else
                log_warn "Could not confirm libdvdcss built. DVDs with copy protection may not play."
                log_warn "Check manually with: doas dpkg-reconfigure libdvd-pkg"
            fi
        else
            log_err "Failed to install libdvd-pkg."
        fi
    fi
fi

log_ok "Multimedia codecs step complete."
