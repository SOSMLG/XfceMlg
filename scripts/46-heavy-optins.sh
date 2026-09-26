#!/usr/bin/env bash
# DEBSWAY_DESC: (optional) Thunderbird, LibreOffice, OBS Studio
# DEBSWAY_DEFAULT: Y
#  46-heavy-optins.sh — Thunderbird, LibreOffice, OBS Studio (optional)
#  Large apps that don't belong in the default install but many users want.
#  LibreOffice gets the GTK3 VCL so it picks up the system Darkmatter
#  theme automatically; the welcome screen is disabled via a minimal
#  registrymodifications.xcu pre-seed.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/3  Thunderbird"
if ask "Install Thunderbird (email client)?" "Y"; then
    install_pkgs "Thunderbird" thunderbird
    is_installed thunderbird && log_ok "Thunderbird installed. On first launch, choose 'Sync' to link your account."
fi

log_head "2/3  LibreOffice"
if ask "Install LibreOffice (office suite, GTK3-themed to match the desktop)?" "Y"; then
    install_pkgs "LibreOffice" libreoffice libreoffice-gtk3

    # Pre-create a first-run profile that disables the welcome screen and
    # tip-of-the-day — idempotent (skip if the file already exists).
    LO_REGISTRY="$HOME/.config/libreoffice/4/user/registrymodifications.xcu"
    if [[ -f "$LO_REGISTRY" ]]; then
        log_ok "LibreOffice registry already exists — skipping pre-seed (no overwrite)."
    else
        mkdir -p "$HOME/.config/libreoffice/4/user"
        cat > "$LO_REGISTRY" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
  <item oor:path="/org.openoffice.Office.Quickstart">
    <prop oor:name="Quickstart">
      <value>false</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Office.Lookup">
    <prop oor:name="ShowTipOfTheDay" oor:op="fuse">
      <value>false</value>
    </prop>
  </item>
</oor:items>
XMLEOF
        log_ok "LibreOffice profile pre-seeded (welcome screen + tip-of-day disabled)."
    fi
    log_info "LibreOffice will use the system GTK3 theme (Darkmatter) via the gtk3 VCL — no manual theme files needed."
fi

log_head "3/3  OBS Studio"
if ask "Install OBS Studio (screen recording / streaming)?" "Y"; then
    install_pkgs "OBS Studio" obs-studio
    is_installed obs-studio && log_ok "OBS Studio installed. First launch opens the auto-config wizard."
    log_info "Hardware encoding (VA-API) is available if your GPU supports it — check Settings → Output → Encoder."
fi

log_ok "Heavy optional apps setup complete."
echo -e "  • Thunderbird: sync your email/account on first launch"
echo -e "  • LibreOffice: GTK3 themed, welcome screen pre-disabled"
echo -e "  • OBS Studio: auto-config wizard runs on first launch"
