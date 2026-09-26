#!/usr/bin/env bash
# DEBSWAY_DESC: Trim task apps, keep XFCE-native, silence the beep
# DEBSWAY_DEFAULT: Y
#  20-xfce-debloat.sh — trim the default task-xfce-desktop app set.
#  Stays XFCE-native: VSCodium (40-*) replaces Mousepad, VLC replaces
#  Parole; flocked out of the box are the Xfce Terminal (Alacritty is
#  the toolkit's one true terminal, set up by 21-theme.sh) and
#  xfce4-screenshooter (flameshot owns Print), and Dunst stays opt-in
#  below. Also kills the system beep for good — that's genuinely
#  four unrelated
#  sources (PC speaker, X11 bell, XFCE's own event-sound bell, and
#  bash's readline bell), which is why so many "I turned it off but
#  it's still beeping" reports exist; this addresses all four.
#  XFCE's default install is already lean compared to KDE's
#  kde-standard (no bundled games/PIM/education suite), so this
#  is mostly about targeted swaps, not a big bloat purge.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






purge_if_installed() {
    local label="$1"; shift
    local to_purge=()
    for pkg in "$@"; do
        is_installed "$pkg" && to_purge+=("$pkg")
    done
    if [[ ${#to_purge[@]} -eq 0 ]]; then
        log_info "$label: nothing installed, skipping."
        return 0
    fi
    log_info "$label: purging ${to_purge[*]}"
    priv apt-get purge -y "${to_purge[@]}" || log_warn "$label: some packages failed to purge (continuing)."
}

apt_update || log_warn "apt-get update failed (continuing with cached lists)."

log_head "1/7  Mousepad (+ Geany, if present) → replaced by VSCodium"
if ask "Remove Mousepad and Geany (VSCodium is installed instead by 40-vscodium.sh)?"; then
    purge_if_installed "Mousepad/Geany" mousepad geany
fi

log_head "2/7  Parole/QuodLibet → replaced by VLC"
if ask "Remove Parole and QuodLibet (VLC is installed instead by 33-useful-apps.sh)?"; then
    purge_if_installed "Parole/QuodLibet" parole quodlibet
fi

log_head "3/7  Unused optical-disc tooling"
if ask "Remove Xfburn (CD/DVD burner — skip if you actually use an optical drive)?" "Y"; then
    purge_if_installed "Xfburn" xfburn
fi

log_head "4/7  Screenshots: flameshot owns Print, stock widgets purged"
# The stock task install binds Print to xfce4-screenshooter. This toolkit
# standardizes on flameshot (installed by 10-xfce-core.sh) — so kill the
# duplicate and pin Print to flameshot's region-select overlay. genmon
# (the old update-indicator widget) is retired too.
purge_if_installed "xfce4-screenshooter" xfce4-screenshooter
purge_if_installed "genmon (retired panel widget)" xfce4-genmon-plugin
rm -rf "$HOME/.config/xfce4/genmon" 2>/dev/null || true
if is_installed flameshot; then
    if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Print>" &>/dev/null; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Print>" -s "flameshot gui"
    else
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Print>" -n -t string -s "flameshot gui"
    fi
    log_ok "Print Screen opens flameshot's region-select overlay."
else
    log_warn "flameshot not installed (10-xfce-core.sh installs it) — Print binding left untouched."
fi

log_head "5/7  Xfce Terminal → Alacritty"
# Alacritty is the toolkit's default terminal (see 21-theme.sh) and also
# takes over the x-terminal-emulator alternative. Xfce Terminal stays only
# if you explicitly want a second fallback terminal.
if ask "Remove Xfce Terminal and its data package (Alacritty is the default terminal)?" "Y"; then
    purge_if_installed "Xfce Terminal" xfce4-terminal xfce4-terminal-data
fi

log_head "6/7  xfce4-notifyd → Dunst"
if ask "Replace xfce4-notifyd with Dunst (lighter, far more configurable notification daemon)?" "N"; then
    priv apt-get install -y dunst || log_warn "Dunst failed to install — leaving xfce4-notifyd in place."
    if is_installed dunst; then
        purge_if_installed "xfce4-notifyd" xfce4-notifyd

        DUNST_CONF_DIR="$HOME/.config/dunst"
        mkdir -p "$DUNST_CONF_DIR"
        if [[ -f "$DUNST_CONF_DIR/dunstrc" ]]; then
            cp "$DUNST_CONF_DIR/dunstrc" "$DUNST_CONF_DIR/dunstrc.bak.$(date +%Y%m%d%H%M%S)"
            log_info "Backed up your existing dunstrc."
        fi
        if [[ -f "$SCRIPT_DIR/../configs/dunst/dunstrc" ]]; then
            cp "$SCRIPT_DIR/../configs/dunst/dunstrc" "$DUNST_CONF_DIR/dunstrc"
            log_ok "Dunst configured (Darkmatter-accented) at $DUNST_CONF_DIR/dunstrc"
        else
            log_warn "Bundled configs/dunst/dunstrc missing — leaving your current dunstrc in place."
        fi

        # dunst registers org.freedesktop.Notifications via D-Bus service
        # activation once installed — it starts itself on the first
        # notification, no autostart entry needed. Just make sure any
        # already-running xfce4-notifyd process doesn't hold the name.
        pkill -x xfce4-notifyd 2>/dev/null || true
        log_ok "Dunst will take over notifications from here on (starts itself on first notification)."
    fi
else
    log_warn "Skipped — keeping xfce4-notifyd."
fi

log_head "7/7  Stop the system beep"
# The "beep" is actually up to four independent, unrelated sources —
# fixing only one is why so many "I turned it off but it's still
# beeping" reports exist. This addresses all four:
if ask "Silence the system beep/bell (PC speaker, X11 bell, GTK event sounds, and bash's own bell)?"; then
    # 1. PC speaker kernel driver — the actual physical "boink" noise.
    BLACKLIST_CONF="/etc/modprobe.d/pcspkr-blacklist.conf"
    if [[ ! -f "$BLACKLIST_CONF" ]]; then
        printf 'blacklist pcspkr\nblacklist snd_pcsp\n' | priv tee "$BLACKLIST_CONF" > /dev/null
        log_ok "Blacklisted pcspkr/snd_pcsp (takes full effect next reboot; unloading live below too)."
    else
        log_info "pcspkr already blacklisted."
    fi
    priv modprobe -r pcspkr 2>/dev/null || true
    priv modprobe -r snd_pcsp 2>/dev/null || true

    # 2. X11 bell — GTK widgets (backspace-at-start-of-line, tab-complete
    #    fail in a dialog, etc.) ring this independently of the PC
    #    speaker. `xset b off` only lasts the current X session, so it
    #    needs an autostart entry, not just running it once now.
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/disable-x11-bell.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Disable X11 Bell
Exec=xset b off
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    xset b off 2>/dev/null || true
    log_ok "X11 bell disabled now, and on every future login."

    # 3. XFCE/GTK's own synthesized event-sound bell — a separate layer
    #    from the raw X11 bell above (this is the libcanberra sound
    #    theme XFCE plays for "system events"). Both keys default to
    #    true; create-if-missing rather than assuming they already exist.
    for PROP in "/Net/EnableEventSounds" "/Net/EnableInputFeedbackSounds"; do
        if xfconf-query -c xsettings -p "$PROP" &>/dev/null; then
            xfconf-query -c xsettings -p "$PROP" -s false
        else
            xfconf-query -c xsettings -p "$PROP" -n -t bool -s false
        fi
    done
    log_ok "XFCE's own event-sound bell disabled."

    # 4. readline's bell — bash's own tab-complete-fail beep, independent
    #    of X11/GTK entirely (this is what still beeps even in a plain
    #    TTY with no X running at all). System-wide via /etc/inputrc.
    INPUTRC="/etc/inputrc"
    if [[ -f "$INPUTRC" ]]; then
        priv cp "$INPUTRC" "${INPUTRC}.bak.$(date +%Y%m%d%H%M%S)"
        if grep -q '^set bell-style' "$INPUTRC"; then
            priv sed -i 's/^set bell-style.*/set bell-style none/' "$INPUTRC"
        elif grep -q '^#[[:space:]]*set bell-style' "$INPUTRC"; then
            priv sed -i 's/^#[[:space:]]*set bell-style.*/set bell-style none/' "$INPUTRC"
        else
            printf '\nset bell-style none\n' | priv tee -a "$INPUTRC" > /dev/null
        fi
        log_ok "readline's bell disabled system-wide ($INPUTRC) — takes effect in new shells."
    else
        log_warn "$INPUTRC not found — readline bell left as-is (unusual, but not fatal)."
    fi

    log_ok "All four beep sources addressed. If you still hear anything after a reboot, it's almost"
    log_ok "certainly a per-application setting (e.g. a terminal's own bell toggle in its preferences)."
else
    log_warn "Skipped — the beep lives on."
fi

log_info "Cleaning up orphaned dependencies..."
priv apt-get autoremove --purge -y || log_warn "autoremove reported issues (non-fatal)."
priv apt-get clean || true

log_head "8/7  Orphaned .desktop entries"
# After task-meta purges / theme rebrands, a .desktop whose Exec binary is
# gone shows up as a broken menu entry. Scan both per-user spots; system
# /usr/share stays untouched. ask_no_full: removing entries is destructive.
stale_entries=()
for dir in "$HOME/.local/share/applications" "$HOME/.config/autostart"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        exec_cmd="$(grep -m1 '^Exec=' "$f" 2>/dev/null | sed 's/^Exec=//' | sed 's/%.*//')"
        [ -z "$exec_cmd" ] && continue
        # First word is the binary (strip env wrappers like env/sh).
        case "$exec_cmd" in
            env\ *|sh\ *|bash\ *) bin="$(echo "$exec_cmd" | awk '{print $2}')" ;;
            *) bin="$(echo "$exec_cmd" | awk '{print $1}')" ;;
        esac
        # Absolute path: check it exists. Bare name: check PATH. --no-store
        # or unknown-when-not-in-path means "fine, skip".
        if [[ "$bin" == /* ]]; then
            [ ! -e "$bin" ] && stale_entries+=("$f")
        else
            command_exists "$bin" || stale_entries+=("$f")
        fi
    done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
done

if [ ${#stale_entries[@]} -eq 0 ]; then
    log_ok "No orphaned .desktop entries under ~/.local/share/applications / ~/.config/autostart."
else
    echo -e "${YELLOW}[!] Orphaned .desktop entries (Exec binary missing):${NC}"
    for f in "${stale_entries[@]}"; do
        echo "     ${f#$HOME/}"
    done
    if ask_no_full "Remove these orphaned entries?"; then
        for f in "${stale_entries[@]}"; do
            rm -f "$f" && log_ok "Removed: ${f#$HOME/}"
        done
    else
        log_warn "Left in place."
    fi
fi

log_ok "XFCE debloat complete."
