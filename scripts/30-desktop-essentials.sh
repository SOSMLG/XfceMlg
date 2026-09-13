#!/usr/bin/env bash
# DEBSWAY_DESC: Flatpak, printing, firewall, Thunar full plugins, Clipman, Redshift
# DEBSWAY_DEFAULT: Y
#  30-desktop-essentials.sh — completeness pass
#  XFCE's own task install already ships Synaptic and
#  system-config-printer as recommends, so this focuses on what
#  it doesn't: Flatpak/Flathub, GParted, ufw+GUFW, the gvfs/tumbler
#  stack Thunar actually needs for trash/auto-mount/thumbnails to
#  work at all, a clipboard manager, Redshift, and a panel update
#  indicator (Devuan has no Mint-style Update Manager, so we build
#  the minimum viable version of one).
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root









apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/8  Flatpak + Flathub"
if ask "Set up Flatpak + Flathub?"; then
    install_pkgs "Flatpak" flatpak gnome-software-plugin-flatpak

    if command -v flatpak &>/dev/null; then
        if priv flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            log_ok "Flathub remote added system-wide."
        else
            log_warn "Could not add the Flathub remote (may already exist)."
        fi
    fi
    log_warn "This installs the Flatpak runtime + Flathub remote. XFCE has no bundled Flatpak"
    log_warn "GUI store — use 'flatpak install flathub <app>' from a terminal, or install"
    log_warn "gnome-software separately if you want a graphical store."
fi

log_head "2/8  Printing"
if ask "Ensure printing support is installed (CUPS + drivers + network discovery)?"; then
    install_pkgs "Printing" cups cups-browsed printer-driver-all system-config-printer

    if is_installed cups; then
        start_service cups
        log_ok "CUPS started."
    fi

    if getent group lpadmin &>/dev/null; then
        if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
            log_ok "$ACTUAL_USER already in the lpadmin group."
        elif priv usermod -aG lpadmin "$ACTUAL_USER"; then
            log_ok "Added $ACTUAL_USER to lpadmin (manage printers without a password prompt each time)."
            log_warn "Log out and back in for this to take effect."
        fi
    fi
fi

log_head "3/8  GParted (partition tool)"
if ask "Install GParted?"; then
    install_pkgs "GParted" gparted
fi

log_head "4/8  Firewall (ufw + GUFW panel)"
if ask "Install ufw + GUFW and enable a deny-incoming/allow-outgoing baseline?"; then
    install_pkgs "Firewall" ufw gufw

    if is_installed ufw; then
        # Guard against locking out an SSH session: allow SSH through
        # *before* flipping to default-deny, not after.
        NEEDS_SSH_RULE=0
        if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
            NEEDS_SSH_RULE=1
        elif command -v ss &>/dev/null && ss -tln 2>/dev/null | grep -qE ':22\b'; then
            NEEDS_SSH_RULE=1
        fi
        if [[ $NEEDS_SSH_RULE -eq 1 ]]; then
            log_info "Active SSH session or listening sshd detected — allowing SSH before enabling default-deny."
            priv ufw allow ssh comment 'preserve SSH access before enabling default-deny' \
                || log_warn "Couldn't add the SSH allow-rule — double-check before enabling ufw if you're on SSH."
        fi

        priv ufw default deny incoming
        priv ufw default allow outgoing
        if priv ufw --force enable; then
            log_ok "ufw enabled: incoming denied by default, outgoing allowed. Manage exceptions via GUFW or 'ufw allow <port>'."
        else
            log_warn "ufw failed to enable — check 'doas ufw status verbose'."
        fi
    fi
fi

log_head "5/8  Thunar full setup (plugins, auto-mount, trash, thumbnails, custom actions)"
if ask "Install the full Thunar plugin set + configure auto-mount, thumbnails and custom actions?"; then
    install_pkgs "Thunar full set" \
        gvfs gvfs-backends gvfs-fuse thunar-volman \
        tumbler ffmpegthumbnailer libgsf-bin \
        thunar-archive-plugin thunar-media-tags-plugin \
        thunar-vcs-plugin thunar-gtkhash thunar-font-manager \
        smbclient cifs-utils xarchiver
    # volman: auto-mount + auto-open removable media (the "USB does nothing" fix)
    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c thunar-volman -p /automount-drives/enabled -n -t bool -s true 2>/dev/null \
            || xfconf-query -c thunar-volman -p /automount-drives/enabled -s true 2>/dev/null || true
        xfconf-query -c thunar-volman -p /automount-media/enabled -n -t bool -s true 2>/dev/null \
            || xfconf-query -c thunar-volman -p /automount-media/enabled -s true 2>/dev/null || true
        xfconf-query -c thunar -p /misc-single-click -n -t bool -s false 2>/dev/null \
            || xfconf-query -c thunar -p /misc-single-click -s false 2>/dev/null || true
        log_ok "Thunar prefs: auto-mount on, double-click to open."
    fi
    # Custom actions worth having on every install (source of truth:
    # configs/Thunar/uca.xml — idempotent: skip when already deployed)
    UCA="$HOME/.config/Thunar/uca.xml"
    UCA_SRC="$SCRIPT_DIR/../configs/Thunar/uca.xml"
    if [[ -f "$UCA" ]] && grep -q "open-terminal-here" "$UCA" 2>/dev/null; then
        log_ok "Thunar custom actions already present."
    elif [[ -f "$UCA_SRC" ]]; then
        mkdir -p "$HOME/.config/Thunar"
        [[ -f "$UCA" ]] && cp "$UCA" "$UCA.bak.$(date +%Y%m%d%H%M%S)"
        cp "$UCA_SRC" "$UCA"
        log_ok "Thunar custom actions installed (Open Terminal Here, Open as Root)."
    else
        log_warn "Custom-action source missing at $UCA_SRC — skipping."
    fi
    log_info "Restart Thunar to pick up the new plugins: thunar -q (it relaunches on next open)."
    log_info "Without gvfs, Thunar's Trash silently does nothing and USB drives won't auto-mount —"
    log_info "this is the single most common \"XFCE feels broken\" complaint, now fixed."
fi

log_head "6/8  Clipboard manager (xfce4-clipman)"
if ask "Install xfce4-clipman and add it to the panel?"; then
    install_pkgs "Clipman" xfce4-clipman-plugin
    xfce4-panel --add=clipman 2>/dev/null \
        && log_ok "Clipman added to the panel — right-click it to set history size/behavior." \
        || log_warn "Couldn't auto-add Clipman — add it manually via Panel → Add New Items."
fi

log_head "7/8  Night light (Redshift)"
if ask "Install Redshift (warms colors after sunset, auto-located via geoclue)?"; then
    install_pkgs "Redshift" redshift redshift-gtk geoclue-2.0

    mkdir -p "$HOME/.config"
    REDSHIFT_CONF="$HOME/.config/redshift.conf"
    [[ -f "$REDSHIFT_CONF" ]] && cp "$REDSHIFT_CONF" "${REDSHIFT_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    cat > "$REDSHIFT_CONF" << 'EOF'
[redshift]
; Gentle values — this is for eye comfort, not an orange-screen effect.
temp-day=6500
temp-night=4500
transition=1
location-provider=geoclue2
EOF

    mkdir -p "$HOME/.config/autostart"
    if [[ ! -f /etc/xdg/autostart/redshift-gtk.desktop && ! -f "$HOME/.config/autostart/redshift-gtk.desktop" ]]; then
        cat > "$HOME/.config/autostart/redshift-gtk.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Redshift
Comment=Adjusts screen color temperature after sunset
Exec=redshift-gtk
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    fi
    (redshift-gtk &>/dev/null & disown) || true
    log_ok "Redshift configured (~/.config/redshift.conf). If location detection fails, swap"
    log_ok "location-provider=geoclue2 for manual lat/lon — see 'man redshift.conf'."
fi

log_head "8/8  Update notifier (periodic list refresh + panel indicator)"
if ask "Set up periodic apt list refresh + a panel icon showing pending updates?"; then
    install_pkgs "Update notifier" unattended-upgrades xfce4-genmon-plugin

    APT_AUTO="/etc/apt/apt.conf.d/20auto-upgrades"
    [[ -f "$APT_AUTO" ]] && priv cp "$APT_AUTO" "${APT_AUTO}.bak.$(date +%Y%m%d%H%M%S)"
    AUTO_INSTALL=0
    ask "Also auto-install security updates unattended (not just refresh the list)?" "N" && AUTO_INSTALL=1
    priv tee "$APT_AUTO" > /dev/null << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${AUTO_INSTALL}";
EOF
    if [[ $AUTO_INSTALL -eq 1 ]]; then
        log_ok "Package lists refresh periodically AND security updates install unattended."
        log_info "Review /etc/apt/apt.conf.d/50unattended-upgrades if you want to tune what's covered."
    else
        log_ok "Package lists refresh periodically; nothing installs without you running it."
    fi

    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/check-apt-updates.sh" << 'CHECKEOF'
#!/usr/bin/env bash
COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
if [[ "$COUNT" -gt 0 ]]; then
    echo "<txt>⬆ ${COUNT}</txt><tool>${COUNT} package(s) can be updated — click to upgrade</tool>"
else
    echo "<txt></txt><tool>System is up to date</tool>"
fi
CHECKEOF
    chmod +x "$HOME/.local/bin/check-apt-updates.sh"

    BEFORE_IDS=$(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null | grep -oE '/plugins/plugin-[0-9]+' | sort -u || true)
    if xfce4-panel --add=genmon 2>/dev/null; then
        sleep 1
        AFTER_IDS=$(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null | grep -oE '/plugins/plugin-[0-9]+' | sort -u || true)
        NEW_ID=$(comm -13 <(echo "$BEFORE_IDS") <(echo "$AFTER_IDS") | head -1 || true)
        if [[ -n "$NEW_ID" ]]; then
            xfconf-query -c xfce4-panel -p "${NEW_ID}/command" -n -t string -s "$HOME/.local/bin/check-apt-updates.sh" 2>/dev/null || true
            xfconf-query -c xfce4-panel -p "${NEW_ID}/period" -n -t int -s 3600 2>/dev/null || true
            xfconf-query -c xfce4-panel -p "${NEW_ID}/click-command" -n -t string -s "xfce4-terminal -e \"doas apt upgrade\"" 2>/dev/null || true
            log_ok "Update indicator added to the panel (hourly check, click to upgrade)."
        else
            log_warn "genmon added but couldn't auto-configure it — right-click it → Properties, and set"
            log_warn "the command to: $HOME/.local/bin/check-apt-updates.sh"
        fi
    else
        log_warn "Couldn't auto-add the genmon plugin — add it manually via Panel → Add New Items,"
        log_warn "then point its command at: $HOME/.local/bin/check-apt-updates.sh"
    fi
fi

log_ok "Desktop essentials log_head complete."
