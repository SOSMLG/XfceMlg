#!/usr/bin/env bash
# DEBSWAY_DESC: VSCodium editor (primary GUI editor)
# DEBSWAY_DEFAULT: Y
#  40-vscodium.sh — VSCodium (primary GUI editor) + Neovim retirement
#  Telemetry-free VS Code build, installed via its official APT
#  repo so it updates normally afterward. VSCodium is THE editor
#  (Mousepad/Geany removed by 20-xfce-debloat.sh, Neovim retired here).
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






if is_installed codium; then
    log_ok "VSCodium (codium) is already installed."
else

log_head "1/4  Dependencies"
for dep in wget gpg; do
    if ! command -v "$dep" &>/dev/null; then
        log_info "Installing dependency: $dep"
        apt_update || log_warn "apt-get update failed (continuing with cached lists)."
        priv apt-get install -y "$dep" || { log_err "Failed to install $dep"; exit 1; }
    fi
done

log_head "2/4  APT repository"
KEYRING="/usr/share/keyrings/vscodium-archive-keyring.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/vscodium.list"
KEY_SOURCES=(
    "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"
    "https://repo.vscodium.dev/vscodium.gpg"
)

log_info "Adding VSCodium's GPG key..."
KEY_TMP="$(mktemp)"
KEY_OBTAINED=""
for url in "${KEY_SOURCES[@]}"; do
    wget -qO - "$url" > "$KEY_TMP" 2>/dev/null || continue
    [[ -s "$KEY_TMP" ]] || continue
    gpg --dearmor -o "$KEY_TMP.bin" "$KEY_TMP" 2>/dev/null || continue
    gpg --batch --show-keys "$KEY_TMP.bin" &>/dev/null || continue
    KEY_OBTAINED="$url"
    break
done
if [[ -n "$KEY_OBTAINED" ]]; then
    if priv install -o root -g root -m 644 "$KEY_TMP.bin" "$KEYRING"; then
        log_ok "Key installed to $KEYRING (source: $KEY_OBTAINED)"
    else
        log_err "Failed to install the VSCodium key."
        priv rm -f "$KEYRING"; rm -f "$KEY_TMP" "$KEY_TMP.bin"; exit 1
    fi
else
    priv rm -f "$KEYRING"
    rm -f "$KEY_TMP" "$KEY_TMP.bin"
    log_err "Failed to fetch a valid VSCodium signing key."
    log_err "Tried: ${KEY_SOURCES[*]}"
    log_info "Fix: re-run $0 once download.vscodium.com's pub.gpg is reachable, or drop a valid key at $KEYRING."
    exit 1
fi
rm -f "$KEY_TMP" "$KEY_TMP.bin"

log_info "Adding VSCodium APT repository..."
ARCH="$(dpkg --print-architecture)"
if echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://download.vscodium.com/debs vscodium main" \
        | priv tee "$SOURCES_FILE" > /dev/null; then
    log_ok "Repository added at $SOURCES_FILE (scoped to arch=${ARCH})"
else
    log_err "Failed to write $SOURCES_FILE"; exit 1
fi

log_head "3/4  Install"
# New repo just added: must refresh even when the runner otherwise skips per-script updates.
priv apt-get update || { log_err "apt-get update failed after adding the VSCodium repo."; exit 1; }
if ! apt-cache policy codium | grep -q 'Candidate:'; then
    log_err "codium has no install candidate — the VSCodium repo did not register."
    log_info "Check the key in $KEYRING and the URL in $SOURCES_FILE, then re-run."
    exit 1
fi
if priv apt-get install -y codium; then
    log_ok "VSCodium installed. Launch it with 'codium'."
else
    log_err "Failed to install codium."; exit 1
fi
fi

log_head "4/4  Retire Neovim (VSCodium is the editor now)"
# The old 46-neovim.sh step is gone. If neovim lingers from an earlier
# run, purge it; user data is never deleted, only moved aside.
if is_installed neovim || command -v nvim &>/dev/null; then
    priv apt-get purge -y neovim 2>/dev/null \
        && log_ok "Neovim package purged (VSCodium is the editor now)." \
        || log_warn "Neovim purge had issues (continuing)."
else
    log_ok "No Neovim package installed — nothing to purge."
fi
# Script-managed fd shim only (Debian calls it fdfind; the old neovim step
# symlinked it to fd). Never touch a real fd binary or ~/.local/bin/fd.
if [[ -L /usr/local/bin/fd ]] && [[ "$(readlink /usr/local/bin/fd 2>/dev/null)" == "/usr/bin/fdfind" ]]; then
    priv rm -f /usr/local/bin/fd && log_ok "Removed script-managed fd shim (/usr/local/bin/fd -> fdfind)."
fi
# Script-managed /opt tarball install only (symlink into /opt/nvim-*).
if [[ -L /usr/local/bin/nvim ]]; then
    _target="$(readlink /usr/local/bin/nvim 2>/dev/null || true)"
    case "${_target:-}" in
        /opt/nvim-*)
            priv rm -f /usr/local/bin/nvim
            for d in /opt/nvim-*/; do
                [[ -d "$d" ]] || continue
                priv rm -rf "$d" && log_info "Removed stale $d."
            done
            ;;
    esac
    unset _target
fi
if [[ -d "$HOME/.config/nvim" ]] && [[ -n "$(ls -A "$HOME/.config/nvim" 2>/dev/null)" ]]; then
    BACKUP="$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
    mv "$HOME/.config/nvim" "$BACKUP" \
        && log_ok "Existing ~/.config/nvim moved aside to $BACKUP (nothing deleted)." \
        || log_warn "Could not move ~/.config/nvim aside — leaving it untouched."
fi
log_ok "VSCodium step complete."
