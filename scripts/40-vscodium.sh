#!/usr/bin/env bash
# DEBSWAY_DESC: VSCodium editor (primary GUI editor)
# DEBSWAY_DEFAULT: Y
#  40-vscodium.sh — VSCodium (optional)
#  Telemetry-free VS Code build, installed via its official APT
#  repo so it updates normally afterward. Geany is this project's
#  default editor (33-useful-apps.sh) — this is here as an optional
#  extra for anyone who also wants VSCodium available.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






if is_installed codium; then
    log_ok "VSCodium (codium) is already installed."
    exit 0
fi

log_head "1/3  Dependencies"
for dep in wget gpg; do
    if ! command -v "$dep" &>/dev/null; then
        log_info "Installing dependency: $dep"
        apt_update || log_warn "apt-get update failed (continuing with cached lists)."
        priv apt-get install -y "$dep" || { log_err "Failed to install $dep"; exit 1; }
    fi
done

log_head "2/3  APT repository"
KEYRING="/usr/share/keyrings/vscodium-archive-keyring.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/vscodium.list"

log_info "Adding VSCodium's GPG key..."
if wget -qO - "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg" \
        | gpg --dearmor | priv tee "$KEYRING" > /dev/null; then
    log_ok "Key installed to $KEYRING"
else
    log_err "Failed to fetch/install the VSCodium GPG key."; exit 1
fi

log_info "Adding VSCodium APT repository..."
ARCH="$(dpkg --print-architecture)"
if echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://download.vscodium.com/debs vscodium main" \
        | priv tee "$SOURCES_FILE" > /dev/null; then
    log_ok "Repository added at $SOURCES_FILE (scoped to arch=${ARCH})"
else
    log_err "Failed to write $SOURCES_FILE"; exit 1
fi

log_head "3/3  Install"
# New repo just added: must refresh even when the runner otherwise skips per-script updates.
priv apt-get update || { log_err "apt-get update failed after adding the VSCodium repo."; exit 1; }
if priv apt-get install -y codium; then
    log_ok "VSCodium installed. Launch it with 'codium'."
else
    log_err "Failed to install codium."; exit 1
fi
