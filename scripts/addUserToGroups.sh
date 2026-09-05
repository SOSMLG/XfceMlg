#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  addUserToGroups.sh — input/video/render group membership
#  Needed by: touchpad/trackpoint tooling, GPU accel
#  Privilege: sudo (falls back to nothing else — this script needs it)
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

REAL_USER="${SUDO_USER:-$USER}"

echo -e "\n${B}${W}══════ Group Membership ══════${Z}"
step "Adding groups"
info "Adding ${W}${REAL_USER}${Z} to input, video, render groups..."

STATUS=0
for grp in input video render; do
    if ! getent group "$grp" &>/dev/null; then
        warn "Group '$grp' doesn't exist on this system, skipping."
        continue
    fi
    if id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
        ok "Already in '$grp'"
        continue
    fi
    if sudo usermod -aG "$grp" "$REAL_USER"; then
        ok "Added to '$grp'"
    else
        warn "Failed to add to '$grp'"
        STATUS=1
    fi
done

warn "Log out and back in for new group membership to take effect."
exit "$STATUS"
