#!/usr/bin/env bash
# DEBSWAY_DESC: VSCodium editor (Darkmatter theme) + Neovim retirement
# DEBSWAY_DEFAULT: Y
#  40-vscodium.sh — VSCodium (primary GUI editor) + Neovim retirement
#  Telemetry-free VS Code build, installed via its official APT
#  repo so it updates normally afterward. VSCodium is THE editor
#  (Mousepad/Geany removed by 20-xfce-debloat.sh, Neovim retired here).
#  Ships + activates the bundled Darkmatter color theme extension
#  (configs/vscodium/devuan-xfce-setup.darkmatter-theme) and sets
#  workbench.colorTheme=Darkmatter in the user settings.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






if is_installed codium; then
    log_ok "VSCodium (codium) is already installed."
else

log_head "1/5  Dependencies"
for dep in wget gpg; do
    if ! command -v "$dep" &>/dev/null; then
        log_info "Installing dependency: $dep"
        apt_update || log_warn "apt-get update failed (continuing with cached lists)."
        priv apt-get install -y "$dep" || { log_err "Failed to install $dep"; exit 1; }
    fi
done

log_head "2/5  APT repository"
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

log_head "3/5  Install"
# New repo just added: must refresh even when the runner otherwise skips per-script updates.
# The vscodium index omits Valid-Until and is refreshed rarely (server keeps re-serving a
# stale InRelease), so a transient fetch blip can leave apt-cache without a candidate even
# though the repo is fine — wipe the cached index and retry once rather than failing first.
cand() { apt-cache policy codium 2>/dev/null | awk -F': ' '/Candidate:/{gsub(/ /,"",$2); print $2}'; }
registered() { local c; c="$(cand)"; [[ -n "$c" ]] && [[ "$c" != "(none)" ]] \
    && apt-cache policy codium 2>/dev/null | grep -q "download.vscodium.com"; }
for attempt in 1 2; do
    priv apt-get update || { log_err "apt-get update failed after adding the VSCodium repo."; exit 1; }
    registered && break
    if [[ $attempt -eq 1 ]]; then
        log_warn "codium not resolved — wiping the cached vscodium index and retrying once."
        priv rm -f /var/lib/apt/lists/download.vscodium.com*_InRelease \
                   /var/lib/apt/lists/download.vscodium.com*_Packages 2>/dev/null || true
    fi
done
if ! registered; then
    log_err "codium has no install candidate — the VSCodium repo did not register after two refreshes."
    log_info "Sources file ($SOURCES_FILE):"
    priv cat "$SOURCES_FILE" | sed 's/^/  /'
    log_info "Key fingerprints in $KEYRING:"
    gpg --batch --show-keys "$KEYRING" 2>/dev/null | sed -n '1,6s/^/  /p' || true
    log_info "apt-cache policy codium reports candidate: $(cand)"
    log_info "Check $SOURCES_FILE and $KEYRING, then re-run."
    exit 1
fi
if priv apt-get install -y codium; then
    log_ok "VSCodium installed. Launch it with 'codium'."
else
    log_err "Failed to install codium."; exit 1
fi
fi

log_head "4/5  Darkmatter color theme"
THEME_EXT_SRC="$SCRIPT_DIR/../configs/vscodium/devuan-xfce-setup.darkmatter-theme"
VSCODIUM_CONFIG="$HOME/.config/VSCodium/User"
VSCODIUM_SETTINGS="$VSCODIUM_CONFIG/settings.json"
EXT_DIR=""
for candidate in "$HOME/.vscodium/extensions" "$HOME/.vscode-oss/extensions"; do
    if [[ -d "$candidate" ]]; then
        EXT_DIR="$candidate"
        break
    fi
done
if command -v codium &>/dev/null; then
    if [[ -z "$EXT_DIR" ]]; then
        EXT_DIR="$HOME/.vscodium/extensions"
        mkdir -p "$EXT_DIR"
    fi
    if [[ -d "$THEME_EXT_SRC" ]]; then
        EXT_DEST="$EXT_DIR/devuan-xfce-setup.darkmatter-theme"
        if [[ -f "$EXT_DEST/package.json" ]]; then
            cp "$EXT_DEST/package.json" "${EXT_DEST}/package.json.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            log_info "Backed up existing Darkmatter theme extension metadata."
        fi
        rm -rf "$EXT_DEST"
        cp -r "$THEME_EXT_SRC" "$EXT_DEST"
        chmod -R u+rwX,go+rX "$EXT_DEST"
        log_ok "Darkmatter theme extension deployed to $EXT_DEST."
    else
        log_warn "Darkmatter theme extension seed missing at $THEME_EXT_SRC."
    fi
    mkdir -p "$VSCODIUM_CONFIG"
    if [[ -f "$VSCODIUM_SETTINGS" ]]; then
        cp "$VSCODIUM_SETTINGS" "${VSCODIUM_SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "Backed up existing VSCodium settings.json."
    fi
    python3 - "$VSCODIUM_SETTINGS" << 'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
if data.get("workbench.colorTheme") != "Darkmatter":
    data["workbench.colorTheme"] = "Darkmatter"
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
print("colorTheme set to Darkmatter")
PYEOF
    log_ok "VSCodium colorTheme set to Darkmatter (relaunch codium to pick up the new theme)."
else
    log_warn "codium not on PATH — theme deploy skipped (re-run after installing VSCodium)."
fi

log_head "5/5  Retire Neovim (VSCodium is the editor now)"
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
