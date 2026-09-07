#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  devuan-xfce-setup — ordered runner
#  Runs setup scripts in order, asking Y/N per script with a
#  default. Same pattern as the KDE-side version of this toolkit.
# ══════════════════════════════════════════════════════════════
set -uo pipefail
# NOTE: deliberately not using -e here — one script failing
# shouldn't silently abort every later step. Each script still
# exits non-zero on failure so this runner can report it.

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
    echo -e "${R}${W}Please run this as your normal user, not as root.${Z}"
    echo -e "${Y}Each script calls sudo itself for the parts that need it.${Z}"
    exit 1
fi

if [[ -f /etc/devuan_version ]]; then
    echo -e "${G}Devuan detected: $(cat /etc/devuan_version)${Z}"
elif [[ -f /etc/debian_version ]]; then
    echo -e "${G}Debian-based system detected: $(cat /etc/debian_version)${Z}"
else
    echo -e "${Y}Warning: this toolkit targets Devuan/Debian. Your system may not be compatible.${Z}"
    read -rp "Continue anyway? (y/N): " continue_anyway
    [[ "$continue_anyway" =~ ^[Yy]$ ]] || exit 1
fi

SCRIPTS=(
    "addUserToGroups.sh|Add your user to input/video/render groups|Y"
    "xfceDebloat.sh|Swap Mousepad/Parole for Geany/VLC, trim unused optical-disc tooling|Y"
    "catppuccinTheme.sh|Catppuccin (Red/Black) GTK/xfwm4 theme, icons, cursors, panel CSS, picom, and Alacritty as the terminal — mostly automatic, just a couple of optional extras at the end|Y"
    "usefulApps.sh|Install base tools, Python/data-science stack, Geany, VLC, plus Mint-style everyday apps (Ristretto, Atril, GNOME Disks)|Y"
    "bootThemeSetup.sh|Carry the Catppuccin theme to Plymouth (boot splash), GRUB, and the LightDM login screen — the part before you reach the desktop|Y"
    "touchpadTrackpointFix.sh|Apply touchpad/trackpoint polling + libinput fixes|Y"
    "hardwareSupport.sh|Install WiFi/Bluetooth firmware, CPU microcode, fwupd, and TLP (ThinkPad battery thresholds)|Y"
    "bluetoothSetup.sh|Set up Bluetooth stack, Blueman GUI, and audio bridging for headsets/earbuds|Y"
    "multimediaCodecs.sh|Install audio/video codecs, DVD playback, Audacity/Shotcut|Y"
    "firefoxHarden.sh|Install & harden Firefox ESR with Betterfox + privacy policies|Y"
    "installFonts.sh|Install Noto, Font Awesome, and JetBrainsMono Nerd Font|Y"
    "terminalButterbash.sh|Install ButterBash + XFCE-specific shell additions|Y"
    "fastfetchConfig.sh|Install fastfetch + your curated presets, plus optional Catppuccin-themed btop|Y"
    "desktopEssentials.sh|Flatpak, printing, GParted, ufw+GUFW, gvfs/Thunar essentials, Clipman, Redshift, and an update-notifier panel icon|Y"
    "timeshiftSetup.sh|Install Timeshift for system snapshots/restore|Y"
    "installPhotogimp.sh|(optional) Install GIMP + PhotoGIMP's Photoshop-like layout/theme|N"
    "installVscodium.sh|(optional) Install VSCodium editor|N"
    "vscodiumDevSetup.sh|(optional) Configure VSCodium for C++/Python development|N"
    "gamingSetup.sh|(optional) Install Steam / Heroic Games Launcher / Wine|N"
    "vesktopTelegram.sh|(optional) Install Vesktop (Discord client) / Telegram|N"
)

echo -e "${B}${W}=========================================================${Z}"
echo -e "${B}${W}   Devuan/Debian XFCE Setup${Z}"
echo -e "${B}${W}=========================================================${Z}\n"

FAILED=()
SKIPPED=()

for ENTRY in "${SCRIPTS[@]}"; do
    SCRIPT="${ENTRY%%|*}"
    REST="${ENTRY#*|}"
    DESC="${REST%%|*}"
    DEFAULT="${REST##*|}"
    SCRIPT_PATH="$SCRIPTS_DIR/$SCRIPT"

    echo -e "${Y}▶ ${SCRIPT}${Z}"
    echo -e "   ${C}${DESC}${Z}"

    if [[ ! -f "$SCRIPT_PATH" ]]; then
        echo -e "${R}   ✖ Script not found: $SCRIPT_PATH${Z}\n"
        FAILED+=("$SCRIPT (missing)")
        continue
    fi

    DEFAULT=${DEFAULT^^}
    PROMPT="   ➤ Run this script? (y/N): "
    [[ "$DEFAULT" == "Y" ]] && PROMPT="   ➤ Run this script? (Y/n): "

    read -rp "$PROMPT" ANSWER
    ANSWER=${ANSWER:-$DEFAULT}
    echo

    if [[ "${ANSWER^^}" == "Y" ]]; then
        echo -e "${G}   ✔ Running $SCRIPT...${Z}"
        if bash "$SCRIPT_PATH"; then
            echo -e "${G}   ✔ Done: $SCRIPT${Z}\n"
        else
            echo -e "${R}   ✖ $SCRIPT exited with an error (continuing with the rest)${Z}\n"
            FAILED+=("$SCRIPT")
        fi
    else
        echo -e "${Y}   ! Skipped: $SCRIPT${Z}\n"
        SKIPPED+=("$SCRIPT")
    fi
done

echo -e "${B}${W}=========================================================${Z}"
echo -e "${B}${W}   All tasks processed.${Z}"
echo -e "${B}${W}=========================================================${Z}"

[[ ${#SKIPPED[@]} -gt 0 ]] && echo -e "${Y}Skipped: ${SKIPPED[*]}${Z}"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "${R}Failed:  ${FAILED[*]}${Z}"
    echo -e "${Y}Re-run individual scripts directly with: bash scripts/<name>.sh${Z}"
    exit 1
fi

echo -e "${G}Done. A logout/reboot is recommended (group membership + firmware changes).${Z}"
