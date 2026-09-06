#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  picomSetup.sh — picom compositor, tuned for "a little bit of
#  animation" without hurting battery life on a laptop.
#
#  xfwm4 has its own built-in compositor (catppuccinTheme.sh can
#  enable it), but it's fairly basic — window-open/close fades
#  only, no per-app control. picom does the same job with more
#  headroom, so this script:
#    - installs picom (falls back to compton on very old
#      Debian/Devuan releases that predate picom's debianization)
#    - turns OFF xfwm4's own compositor first — running two X11
#      compositors against the same display at once causes
#      flicker/tearing and doubles GPU wake-ups, which is the
#      opposite of "lightweight"
#    - writes a deliberately minimal ~/.config/picom.conf:
#        · fade in/out only (open/close + menus) — the actual
#          "bit of animation" that was asked for
#        · NO shadows, NO blur — these are what actually burn
#          battery on a compositor (per-frame blur/shadow
#          re-rendering keeps the GPU from ever going idle)
#        · xrender backend — works on effectively any GPU
#          (including old/integrated ThinkPad-era hardware this
#          toolkit targets) without needing a GLX context kept
#          alive in the background
#        · vsync on — caps redraws to the monitor's refresh
#          rate instead of redrawing as fast as possible
#        · unredir-if-possible on — this is the single biggest
#          battery win: picom fully steps aside (no compositing
#          at all) whenever a fullscreen window (video, a game,
#          a presentation) has focus
#    - autostarts it in the XFCE session
#
#  Privilege: sudo (package install only; everything else is
#  $HOME config + xfconf-query)
# ══════════════════════════════════════════════════════════════
set -uo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; }
fatal() { err "$*"; exit 1; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && fatal "Run this script as your normal user, not root."
command -v sudo &>/dev/null || fatal "sudo not found — this script needs it to install packages."

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

echo -e "\n${B}${W}══════ Picom (lightweight animations) ══════${Z}"

if ! ask "Install picom with a minimal, battery-friendly config (fades only, no shadows/blur)?"; then
    warn "Skipped picom setup."
    exit 0
fi

# ══════════════════════════════════════════════════════════════
step "1/4  Disable xfwm4's built-in compositor"
# ══════════════════════════════════════════════════════════════
# Two compositors fighting over the same X11 compositing extension
# is the classic cause of flicker/tearing — and it means both are
# burning GPU cycles for the same job. picom replaces xfwm4's, so
# turn xfwm4's off first regardless of what catppuccinTheme.sh set
# it to earlier in the run.
if command -v xfconf-query &>/dev/null; then
    xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null \
        && ok "xfwm4's built-in compositor turned off (picom replaces it)." \
        || warn "Couldn't reach xfconf (not in an XFCE session right now?) — turn it off manually later via Window Manager Tweaks → Compositor if picom looks glitchy."
else
    warn "xfconf-query not found — skipping the xfwm4-compositor-off step."
fi

# ══════════════════════════════════════════════════════════════
step "2/4  Install picom"
# ══════════════════════════════════════════════════════════════
info "Refreshing package lists..."
sudo apt-get update -qq

COMPOSITOR_BIN=""
if is_installed picom || sudo apt-get install -y picom; then
    COMPOSITOR_BIN="picom"
    ok "picom installed."
else
    warn "picom isn't available in this system's repos (only on Debian/Devuan releases based on Debian 11+)."
    info "Falling back to compton (picom's predecessor, available on older releases)..."
    if is_installed compton || sudo apt-get install -y compton; then
        COMPOSITOR_BIN="compton"
        ok "compton installed as a fallback — config below is compton-compatible too."
    else
        err "Neither picom nor compton could be installed. Skipping."
        exit 1
    fi
fi

# ══════════════════════════════════════════════════════════════
step "3/4  Write a minimal, battery-friendly config"
# ══════════════════════════════════════════════════════════════
mkdir -p "$HOME/.config"
PICOM_CONF="$HOME/.config/picom.conf"
if [[ -f "$PICOM_CONF" ]]; then
    cp "$PICOM_CONF" "${PICOM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    info "Backed up existing picom.conf."
fi

cat > "$PICOM_CONF" << 'EOF'
# ══════════════════════════════════════════════════════════════
# picom.conf — deliberately minimal. This is a "just fades"
# config, not a full eye-candy setup, on purpose: shadows and
# blur are what make a compositor expensive, not fades.
# ══════════════════════════════════════════════════════════════

# xrender works on essentially any GPU (including old/integrated
# hardware) without holding a GLX context open in the background.
# If you're on a modern discrete/iGPU setup and want glx instead
# for slightly smoother fades, swap this one line — everything
# else here still applies.
backend = "xrender";

# Cap redraws to the display's refresh rate instead of redrawing
# as fast as possible — this alone noticeably cuts idle GPU wakeups.
vsync = true;

# ── Fading — the actual "bit of animation" ──────────────────────
fading = true;
fade-in-step = 0.05;
fade-out-step = 0.05;
fade-delta = 6;
no-fading-openclose = false;
no-fading-destroyed-argb = true;

# ── Everything expensive, explicitly OFF ─────────────────────────
shadow = false;
blur-method = "none";
corner-radius = 0;

# ── The actual battery-saving flag ───────────────────────────────
# Fully disables compositing whenever a fullscreen window (video
# player, game, presentation, browser fullscreen) has focus, so
# it costs nothing when it would matter most.
unredir-if-possible = true;

# Don't bother compositing windows that are fully obscured.
detect-transient = true;
detect-client-opacity = true;
use-damage = true;

wintypes:
{
  tooltip = { fade = true; shadow = false; };
  dock = { shadow = false; };
  dnd = { shadow = false; };
  popup_menu = { fade = true; shadow = false; };
  dropdown_menu = { fade = true; shadow = false; };
};
EOF
ok "Config written to $PICOM_CONF"

# ══════════════════════════════════════════════════════════════
step "4/4  Autostart"
# ══════════════════════════════════════════════════════════════
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/picom.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Picom Compositor
Comment=Lightweight compositor — fades only, no shadows/blur, unredirects fullscreen windows to save battery
Exec=${COMPOSITOR_BIN} --config $PICOM_CONF
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
ok "Autostart entry written — picom will start on next login."

# Start it now too, so it's visible without a logout/login. Kill
# any prior instance first (re-running this script should refresh
# the running config, not stack a second process on top).
pkill -x "$COMPOSITOR_BIN" 2>/dev/null
sleep 0.3
("$COMPOSITOR_BIN" --config "$PICOM_CONF" &>/dev/null & disown) || true

echo
ok "Picom is running with fades-only, battery-conscious settings."
echo -e "${C}Open/close a window or menu to see the fade. If it ever feels janky on your GPU, try switching 'backend' to \"glx\" in ${PICOM_CONF}.${Z}"
