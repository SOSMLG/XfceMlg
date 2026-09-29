#!/usr/bin/env bash
# XMLG_DESC: fastfetch config + btop (system monitor)
# XMLG_DEFAULT: Y
#  19-fastfetch.sh — system info on terminal open
#  Writes one minimal, fancy fastfetch config locally (Darkmatter red
#  accent, custom anime ASCII art, essential modules only — no network
#  needed beyond the fastfetch package itself), and offers btop, a
#  terminal system monitor, on its own merits. btop ships with its own
#  default theme; the toolkit does not fetch or install a third-party
#  colour scheme for it.
#  Privilege: priv() (doas-first, sudo fallback) (fastfetch/btop installs)
set -uo pipefail
# NOTE: no -e — one failed package must degrade gracefully, not abort
# everything after it (lib install_pkgs returns 1 on partial failure).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

log_head "1/3  Install fastfetch"
if is_installed fastfetch; then
	log_ok "fastfetch already installed."
else
	apt_update || log_warn "apt-get update failed (continuing with cached lists)."
	priv apt-get install -y fastfetch || {
		log_err "Failed to install fastfetch."
		exit 1
	}
	log_ok "fastfetch installed."
fi

log_head "2/3  Config (minimal, fancy — written locally, no downloads)"
if ask "Write the minimal fancy fastfetch config (Darkmatter palette, custom logo)?"; then
	FF_DIR="$HOME/.config/fastfetch"
	mkdir -p "$FF_DIR"
	FF_CONF="$FF_DIR/config.jsonc"
	[[ -f "$FF_CONF" ]] && cp "$FF_CONF" "${FF_CONF}.bak.$(date +%Y%m%d%H%M%S)"

	# Deploy the bundled ASCII art
	ASCII_SRC="$SCRIPT_DIR/../configs/fastfetch/ascii_art_anime.txt"
	if [[ -f "$ASCII_SRC" ]]; then
		cp "$ASCII_SRC" "$FF_DIR/ascii_art_anime.txt"
	fi

	cat >"$FF_CONF" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "source": "~/.config/fastfetch/ascii_art_anime.txt",
        "type": "file",
        "padding": { "top": 1 }
    },
    "display": {
        "color": { "keys": "blue", "title": "blue" },
        "separator": "  "
    },
    "general": {
        "showElapsed": false,
        "statSeparatorType": "hidden"
    },
    "modules": [
        "title",
        "separator",
        "os",
        "kernel",
        "uptime",
        "shell",
        "display",
        "de",
        "terminal",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "separator",
        "colors"
    ]
}
EOF
	log_ok "Minimal fancy config written to $FF_CONF (try it: fastfetch)."
fi

log_head "3/3  btop (system monitor)"
if ask "Install btop (a terminal system monitor)?"; then
	install_pkgs "btop" btop || log_warn "btop install failed (re-run this script later)."
	if is_installed btop; then
		log_ok "btop ready — start it with 'btop'."
	else
		log_warn "btop not installed — skipping (re-run this script later)."
	fi
fi

log_ok "fastfetch setup complete. Try it: fastfetch"
