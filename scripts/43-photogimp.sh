#!/usr/bin/env bash
# DEBSWAY_DESC: (optional) GIMP + PhotoGIMP layout
# DEBSWAY_DEFAULT: N
#  43-photogimp.sh — GIMP + PhotoGIMP's Photoshop-like layout
#  Fetched live from https://github.com/Diolinux/PhotoGIMP at
#  install time (latest release tag, pinned fallback if the
#  GitHub API is rate-limited). Two adaptations from upstream:
#   1. Their .desktop assumes Flatpak — rewritten for the
#      native apt-installed /usr/bin/gimp instead.
#   2. This patch targets GIMP 3.0's config format — the script
#      checks the installed GIMP version first and refuses to
#      apply it to an incompatible 2.10 install.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






REPO="Diolinux/PhotoGIMP"
FALLBACK_TAG="3.1"
PHOTOGIMP_TARGET_VER="3.0"


for dep in curl python3 tar; do
    command -v "$dep" &>/dev/null || { log_err "Missing required tool: $dep"; exit 1; }
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log_head "1/5  Fetch PhotoGIMP from GitHub"
log_info "Looking up the latest PhotoGIMP release tag..."
TAG=""
API_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
[[ -n "$API_JSON" ]] && TAG="$(echo "$API_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)"

if [[ -z "$TAG" ]]; then
    log_warn "Could not reach the GitHub API (rate-limited?). Falling back to pinned tag: $FALLBACK_TAG"
    TAG="$FALLBACK_TAG"
else
    log_ok "Latest release: $TAG"
fi

TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/refs/tags/${TAG}"
log_info "Downloading: $TARBALL_URL"
curl -fL -o "$TMP_DIR/photogimp.tar.gz" "$TARBALL_URL" || { log_err "Download failed."; exit 1; }
tar xzf "$TMP_DIR/photogimp.tar.gz" -C "$TMP_DIR" || { log_err "Extraction failed."; exit 1; }

SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [[ -z "$SRC_DIR" ]] || [[ ! -d "$SRC_DIR/.config/GIMP" ]]; then
    log_err "Downloaded archive doesn't have the expected .config/GIMP layout."
    exit 1
fi
# Prefer the target-version dir (3.0); recent releases only ship one GIMP
# config dir, but never assume — fall back to whatever actually shipped.
if [[ -d "$SRC_DIR/.config/GIMP/$PHOTOGIMP_TARGET_VER" ]]; then
    SRC_GIMP_DIR="$SRC_DIR/.config/GIMP/$PHOTOGIMP_TARGET_VER"
    SRC_GIMP_VER="$PHOTOGIMP_TARGET_VER"
else
    SRC_GIMP_DIR="$(find "$SRC_DIR/.config/GIMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
    SRC_GIMP_VER="$(basename "$SRC_GIMP_DIR")"
    log_warn "PhotoGIMP release only ships a GIMP $SRC_GIMP_VER config — targeting that instead."
fi
log_ok "PhotoGIMP $TAG downloaded and verified (config for GIMP $SRC_GIMP_VER)."

log_head "2/5  Install GIMP"
if ! is_installed gimp; then
    apt_update || log_warn "apt-get update failed (continuing with cached lists)."
    priv apt-get install -y gimp || { log_err "Failed to install GIMP."; exit 1; }
else
    log_ok "GIMP is already installed."
fi

log_head "3/5  Version check"
GIMP_VERSION="$(gimp --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
GIMP_CONFIG_VER="$SRC_GIMP_VER"
BACKEND="system"

if [[ -z "$GIMP_VERSION" ]]; then
    log_warn "Could not determine the installed GIMP version."
elif [[ "$(echo "$GIMP_VERSION" | cut -d. -f1,2)" != "$SRC_GIMP_VER" ]]; then
    log_warn "Installed GIMP is $GIMP_VERSION, but this PhotoGIMP release targets GIMP $SRC_GIMP_VER."
    log_warn "Devuan currently ships GIMP 2.10 — GIMP 3 is available as a Flatpak."
    # A version mismatch must never auto-fire on --full: ask explicitly, and
    # a refusal skips cleanly (exit 0) instead of failing the whole run.
    if ask_no_full "Install GIMP $SRC_GIMP_VER via Flatpak and apply PhotoGIMP's config there?" "N"; then
        if priv flatpak install -y flathub "org.gimp.GIMP" 2>/dev/null; then
            BACKEND="flatpak"
            log_ok "GIMP $SRC_GIMP_VER installed via Flatpak."
        else
            log_warn "Flatpak install failed — falling back to the system GIMP ($GIMP_VERSION)."
        fi
    else
        log_warn "Skipping PhotoGIMP for now — re-run 43-photogimp.sh if you switch GIMP versions."
        exit 0
    fi
else
    log_ok "Detected GIMP $GIMP_VERSION — matches the config this release targets."
fi

log_head "4/5  Apply config + icons"
if ask "Apply PhotoGIMP's config (Photoshop-like layout, shortcuts, theme)?"; then
    if [[ "$BACKEND" = "flatpak" ]]; then
        GIMP_CONFIG_DIR="$HOME/.var/app/org.gimp.GIMP/config/GIMP/$GIMP_CONFIG_VER"
    else
        GIMP_CONFIG_DIR="$HOME/.config/GIMP/$GIMP_CONFIG_VER"
    fi
    if [[ -d "$GIMP_CONFIG_DIR" ]]; then
        BACKUP="$GIMP_CONFIG_DIR.bak.$(date +%Y%m%d_%H%M%S)"
        cp -r "$GIMP_CONFIG_DIR" "$BACKUP"
        log_info "Existing GIMP config backed up to $BACKUP"
    fi
    mkdir -p "$GIMP_CONFIG_DIR"
    cp -r "$SRC_GIMP_DIR/." "$GIMP_CONFIG_DIR/"
    log_ok "PhotoGIMP config applied to $GIMP_CONFIG_DIR"
fi

if ask "Install PhotoGIMP icons?"; then
    ICON_DIR="$HOME/.local/share/icons/hicolor"
    mkdir -p "$ICON_DIR"
    cp -r "$SRC_DIR/.local/share/icons/hicolor/." "$ICON_DIR/"
    log_ok "Icons installed to $ICON_DIR"
    if command -v gtk-update-icon-cache &>/dev/null; then
        if gtk-update-icon-cache -f "$ICON_DIR" &>/dev/null; then
            log_ok "Icon cache refreshed."
        else
            log_warn "Icon cache refresh failed (non-log_err)."
        fi
    fi
fi

log_head "5/5  Application launcher"
if ask "Install PhotoGIMP application launcher?"; then
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"
    SRC_DESKTOP="$(find "$SRC_DIR/.local/share/applications" -maxdepth 1 -name '*.desktop' | head -1)"
    if [[ -z "$SRC_DESKTOP" ]]; then
        log_err "No .desktop file found in the downloaded release, skipping launcher."
    else
        sed 's|^Exec=.*|Exec=gimp %U|' "$SRC_DESKTOP" > "$APPS_DIR/photogimp.desktop"
        log_ok "Launcher installed (pointed at the native gimp binary, not Flatpak)."
        command -v update-desktop-database &>/dev/null && update-desktop-database "$APPS_DIR" &>/dev/null
    fi
fi

log_ok "PhotoGIMP $TAG setup complete."
log_warn "Restart GIMP if it's currently running for the new theme to take effect."
