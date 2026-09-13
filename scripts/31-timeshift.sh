#!/usr/bin/env bash
# DEBSWAY_DESC: Timeshift snapshots
# DEBSWAY_DEFAULT: Y
#  31-timeshift.sh — system snapshot/restore
#  Mint's signature safety net. Depends on plain cron, not
#  systemd, so it works fine on Devuan's default init.
#  Deliberately does NOT auto-configure a snapshot device or
#  schedule — that's a one-time choice with real disk-space
#  implications, worth doing deliberately via the setup wizard.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root






apt_update || log_warn "apt-get update failed (continuing with cached lists)."

# cron is normally already present, but this is defensive — Timeshift
# hard-depends on it, not on systemd.
install_pkgs "cron" cron
install_pkgs "Timeshift" timeshift

if is_installed timeshift; then
    log_ok "Timeshift installed."
    log_warn "One-time setup needed: run 'doas timeshift-launcher' (or find Timeshift in the"
    log_warn "app menu) to choose rsync vs BTRFS mode, where snapshots are stored, and a"
    log_warn "schedule. That choice is left to you rather than guessed automatically."
else
    log_err "Timeshift installation failed."; exit 1
fi
