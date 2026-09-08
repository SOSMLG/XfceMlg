#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  desktopEssentials.sh — completeness pass
#  XFCE's own task install already ships Synaptic and
#  system-config-printer as recommends, so this focuses on what
#  it doesn't: Flatpak/Flathub, GParted, ufw+GUFW, the gvfs/tumbler
#  stack Thunar actually needs for trash/auto-mount/thumbnails to
#  work at all, a clipboard manager, Redshift, and a panel update
#  indicator (Devuan has no Mint-style Update Manager, so we build
#  the minimum viable version of one).
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

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

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
        return 0
    else
        warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

start_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now "$svc" &>/dev/null || true
    else
        sudo service "$svc" start &>/dev/null || true
    fi
}

REAL_USER="${SUDO_USER:-$USER}"

echo -e "\n${B}${W}══════ Desktop Essentials ══════${Z}"
info "Refreshing package lists..."
sudo apt-get update -qq

step "1/8  Flatpak + Flathub"
if ask "Set up Flatpak + Flathub?"; then
    install_pkgs "Flatpak" flatpak gnome-software-plugin-flatpak

    if command -v flatpak &>/dev/null; then
        if sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            ok "Flathub remote added system-wide."
        else
            warn "Could not add the Flathub remote (may already exist)."
        fi
    fi
    warn "This installs the Flatpak runtime + Flathub remote. XFCE has no bundled Flatpak"
    warn "GUI store — use 'flatpak install flathub <app>' from a terminal, or install"
    warn "gnome-software separately if you want a graphical store."
fi

step "2/8  Printing"
if ask "Ensure printing support is installed (CUPS + drivers + network discovery)?"; then
    install_pkgs "Printing" cups cups-browsed printer-driver-all system-config-printer

    if is_installed cups; then
        start_service cups
        ok "CUPS started."
    fi

    if getent group lpadmin &>/dev/null; then
        if id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
            ok "$REAL_USER already in the lpadmin group."
        elif sudo usermod -aG lpadmin "$REAL_USER"; then
            ok "Added $REAL_USER to lpadmin (manage printers without a password prompt each time)."
            warn "Log out and back in for this to take effect."
        fi
    fi
fi

step "3/8  GParted (partition tool)"
if ask "Install GParted?"; then
    install_pkgs "GParted" gparted
fi

step "4/8  Firewall (ufw + GUFW panel)"
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
            info "Active SSH session or listening sshd detected — allowing SSH before enabling default-deny."
            sudo ufw allow ssh comment 'preserve SSH access before enabling default-deny' \
                || warn "Couldn't add the SSH allow-rule — double-check before enabling ufw if you're on SSH."
        fi

        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        if sudo ufw --force enable; then
            ok "ufw enabled: incoming denied by default, outgoing allowed. Manage exceptions via GUFW or 'ufw allow <port>'."
        else
            warn "ufw failed to enable — check 'sudo ufw status verbose'."
        fi
    fi
fi

step "5/8  File manager essentials (auto-mount, trash, thumbnails, archives)"
if ask "Install gvfs/thunar-volman/tumbler stack (auto-mount USB, trash, thumbnails, archive extract)?"; then
    install_pkgs "File manager essentials" \
        gvfs gvfs-backends gvfs-fuse thunar-volman \
        tumbler ffmpegthumbnailer libgsf-bin \
        thunar-archive-plugin thunar-media-tags-plugin xarchiver
    warn "Restart Thunar to pick up the new plugins: thunar -q (it relaunches on next open)."
    warn "Without gvfs, Thunar's Trash silently does nothing and USB drives won't auto-mount —"
    warn "this is the single most common \"XFCE feels broken\" complaint, now fixed."
fi

step "6/8  Clipboard manager (xfce4-clipman)"
if ask "Install xfce4-clipman and add it to the panel?"; then
    install_pkgs "Clipman" xfce4-clipman-plugin
    xfce4-panel --add=clipman 2>/dev/null \
        && ok "Clipman added to the panel — right-click it to set history size/behavior." \
        || warn "Couldn't auto-add Clipman — add it manually via Panel → Add New Items."
fi

step "7/8  Night light (Redshift)"
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
    ok "Redshift configured (~/.config/redshift.conf). If location detection fails, swap"
    ok "location-provider=geoclue2 for manual lat/lon — see 'man redshift.conf'."
fi

step "8/8  Update notifier (periodic list refresh + panel indicator)"
if ask "Set up periodic apt list refresh + a panel icon showing pending updates?"; then
    install_pkgs "Update notifier" unattended-upgrades xfce4-genmon-plugin

    APT_AUTO="/etc/apt/apt.conf.d/20auto-upgrades"
    [[ -f "$APT_AUTO" ]] && sudo cp "$APT_AUTO" "${APT_AUTO}.bak.$(date +%Y%m%d%H%M%S)"
    AUTO_INSTALL=0
    ask "Also auto-install security updates unattended (not just refresh the list)?" "N" && AUTO_INSTALL=1
    sudo tee "$APT_AUTO" > /dev/null << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${AUTO_INSTALL}";
EOF
    if [[ $AUTO_INSTALL -eq 1 ]]; then
        ok "Package lists refresh periodically AND security updates install unattended."
        info "Review /etc/apt/apt.conf.d/50unattended-upgrades if you want to tune what's covered."
    else
        ok "Package lists refresh periodically; nothing installs without you running it."
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
            xfconf-query -c xfce4-panel -p "${NEW_ID}/click-command" -n -t string -s "alacritty -e sudo apt upgrade" 2>/dev/null || true
            ok "Update indicator added to the panel (hourly check, click to upgrade)."
        else
            warn "genmon added but couldn't auto-configure it — right-click it → Properties, and set"
            warn "the command to: $HOME/.local/bin/check-apt-updates.sh"
        fi
    else
        warn "Couldn't auto-add the genmon plugin — add it manually via Panel → Add New Items,"
        warn "then point its command at: $HOME/.local/bin/check-apt-updates.sh"
    fi
fi

ok "Desktop essentials step complete."
