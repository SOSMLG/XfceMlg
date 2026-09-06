#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  firewallSetup.sh — sane ufw baseline: deny incoming, allow
#  outgoing. Same defaults as ohmydebn's ufw.sh, with one
#  addition it doesn't need but this toolkit does: ohmydebn only
#  ever runs on a machine you're sitting in front of, so a bare
#  "deny incoming" is safe there. This toolkit might be run over
#  SSH on a headless box or a remote laptop — enabling that
#  without an SSH allow-rule first would drop your own session
#  and lock you out. So: detect an active SSH session or a
#  listening sshd, and allow SSH through before enabling deny-by-
#  default, not after.
#
#  Privilege: sudo (ufw only)
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
command -v sudo &>/dev/null || fatal "sudo not found — this script needs it to install/configure ufw."

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo -e "\n${B}${W}══════ Firewall (ufw) ══════${Z}"

if ! ask "Enable ufw with a deny-incoming / allow-outgoing baseline?"; then
    warn "Skipped firewall setup."
    exit 0
fi

# ══════════════════════════════════════════════════════════════
step "1/3  Install ufw"
# ══════════════════════════════════════════════════════════════
info "Refreshing package lists..."
sudo apt-get update -qq
if ! sudo apt-get install -y ufw; then
    err "ufw failed to install."
    exit 1
fi
ok "ufw installed."

# ══════════════════════════════════════════════════════════════
step "2/3  Guard against locking out an SSH session"
# ══════════════════════════════════════════════════════════════
NEEDS_SSH_RULE=0
if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
    info "This looks like an active SSH session."
    NEEDS_SSH_RULE=1
elif command -v ss &>/dev/null && ss -tln 2>/dev/null | grep -qE ':22\b'; then
    info "sshd appears to be listening on port 22."
    NEEDS_SSH_RULE=1
fi

if [[ $NEEDS_SSH_RULE -eq 1 ]]; then
    info "Allowing SSH through before enabling deny-by-default, so this doesn't cut your own access."
    sudo ufw allow ssh comment 'preserve SSH access before enabling default-deny' \
        && ok "SSH allow-rule added." \
        || warn "Couldn't add the SSH allow-rule — double-check before enabling ufw if you're on SSH."
else
    info "No active SSH session or listening sshd detected — skipping the SSH allow-rule."
fi

# ══════════════════════════════════════════════════════════════
step "3/3  Enable deny-incoming / allow-outgoing"
# ══════════════════════════════════════════════════════════════
sudo ufw default deny incoming
sudo ufw default allow outgoing
if sudo ufw --force enable; then
    ok "ufw enabled: incoming denied by default, outgoing allowed."
else
    err "ufw failed to enable — check 'sudo ufw status verbose' for details."
    exit 1
fi

echo
sudo ufw status verbose
echo
ok "Firewall baseline set. Add rules for anything you actually serve, e.g.: sudo ufw allow <port>/tcp"
