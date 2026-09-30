#!/usr/bin/env bash
# XMLG_DESC: fastfetch config + btop (system monitor)
# XMLG_DEFAULT: Y
#  19-fastfetch.sh — system info on terminal open
#  Writes one hand-authored fastfetch config locally (Darkmatter palette,
#  the Devuan ASCII logo in the palette accent, a curated module set —
#  no network needed beyond the fastfetch package itself), and offers btop,
#  a terminal system monitor, on its own merits. btop ships with its own
#  default theme; the toolkit does not fetch or install a third-party
#  colour scheme for it.
#
#  The config is written, then immediately parsed back by fastfetch itself
#  (step 3). That check is not ceremony: 0.8.x shipped a config carrying
#  "general.showElapsed" and "general.statSeparatorType", neither of which
#  has ever existed in fastfetch's schema. fastfetch rejected the whole
#  file with "JsonConfig Error: Unknown general property", printed nothing
#  and exited 221 — so every "run fastfetch to see your system" in the
#  docs produced a one-line error. Nothing in the test suite covered it.
#  A one-line grep is a cheap price for never shipping that again.
#
#  Key shape is pinned to the fastfetch in the archive (2.40.x on
#  Excalibur/trixie), NOT to the `dev` branch schema, which has drifted:
#    * `display.bar` is flat here (charElapsed/charTotal/borderLeft); the
#      dev branch nests it as `bar.char.elapsed` etc. and 2.40 rejects it.
#    * `display.duration` and the `{?var}…{/var}` format conditionals are
#      dev-branch-only. 2.40 has the opposite conditional, `{/var}` = print
#      only when the value is unset. Uptime therefore keeps its default
#      rendering rather than reaching for a display block that is not there.
#    * Hex colours (#e75353) need 2.42; this file uses the ANSI RGB form
#      `38;2;R;G;B`, which every 2.x accepts. Same 24-bit values the shell
#      prompt in configs/bash/prompt.sh uses — one palette, not two.
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

log_head "2/3  Config (Darkmatter palette, Devuan logo, curated modules — no downloads)"
if ask "Write the xfcemlg fastfetch config (Darkmatter palette, custom logo)?"; then
	FF_DIR="$HOME/.config/fastfetch"
	mkdir -p "$FF_DIR"
	FF_CONF="$FF_DIR/config.jsonc"
	# Remember what we rolled out of, so a config fastfetch refuses to parse
	# can be put back the way it was rather than merely deleted.
	FF_PREV=""
	if [[ -f "$FF_CONF" ]]; then
		FF_PREV="$FF_CONF.bak.$(date +%Y%m%d%H%M%S)"
		cp "$FF_CONF" "$FF_PREV"
	fi

	# Deploy the Devuan logo art
	ASCII_SRC="$SCRIPT_DIR/../configs/fastfetch/devuan.txt"
	if [[ -f "$ASCII_SRC" ]]; then
		cp "$ASCII_SRC" "$FF_DIR/devuan.txt"
	fi
	# Retire the pre-0.9.0 bundled art name so a stale file cannot linger
	rm -f "$FF_DIR/ascii_art_anime.txt"

	cat >"$FF_CONF" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",

    // The Devuan logo. The art file is a template, not a picture: $1 is a
    // fastfetch colour placeholder, and every literal "$" in the logo is
    // escaped as "$$" (fastfetch reads "$$" as one dollar). The logo is a
    // solid mass of "$" glyphs, so it is deliberately single-coloured --
    // switching colour back to cream mid-logo would put a colour token
    // directly after a run of "$$" pairs, where fastfetch misreads the
    // token's digit as a literal character. Hence one colour, not two.
    "logo": {
        "type": "file",
        "source": "~/.config/fastfetch/devuan.txt",
        "color": {
            "1": "38;2;231;83;83"     // red #e75353 — the Darkmatter accent
        },
        "padding": { "top": 1 }
    },

    "display": {
        "separator": "  ",
        "color": {
            "keys":      "38;2;231;83;83",
            "output":    "38;2;255;255;255",
            "separator": "38;2;95;135;135"
        },
        "key": { "width": 10, "paddingLeft": 1 },
        "bar": {
            "charElapsed": "█",
            "charTotal":   "░",
            "borderLeft":  "",
            "borderRight": "",
            "width": 8
        },
        "percent": {
            "type": ["num", "num-color"],
            "ndigits": 0,
            "color": {
                "green":  "38;2;95;135;135",
                "yellow": "38;2;251;203;151",
                "red":    "38;2;231;83;83"
            }
        },
        "size":     { "binaryPrefix": "iec", "ndigits": 2 },
        "temp":     { "unit": "C", "ndigits": 1 }
    },

    // Grouped so the block breaks into readable sections. Anything the
    // machine cannot answer (no battery, no power adapter, no terminal
    // font) drops its own line — fastfetch suppresses failed modules.
    "modules": [
        // Leading break so the title lands below the logo instead of
        // sharing its last line.
        "break",
        {
            "type": "title",
            "color": {
                "user": "38;2;251;203;151",
                "at":   "38;2;95;135;135",
                "host": "38;2;231;83;83"
            }
        },
        "break",

        { "type": "os",         "key": "OS" },
        { "type": "kernel",     "key": "Kernel" },
        { "type": "host",       "key": "Machine" },
        { "type": "chassis",    "key": "Chassis" },
        { "type": "initsystem", "key": "Init" },
        { "type": "uptime",     "key": "Uptime" },
        { "type": "loadavg",    "key": "Load" },
        { "type": "processes",  "key": "Procs" },
        { "type": "packages",   "key": "Pkgs" },
        "break",

        { "type": "de",          "key": "DE" },
        { "type": "wm",          "key": "WM" },
        { "type": "shell",       "key": "Shell" },
        { "type": "terminal",    "key": "Term" },
        { "type": "terminalfont","key": "Font" },
        { "type": "display",     "key": "Screen" },
        "break",

        { "type": "cpu",          "key": "CPU", "temp": true },
        { "type": "gpu",          "key": "GPU" },
        { "type": "memory",       "key": "RAM" },
        { "type": "swap",         "key": "Swap" },
        { "type": "disk",         "key": "Disk", "folders": "/" },
        { "type": "battery",      "key": "Battery" },
        { "type": "poweradapter", "key": "Power" },
        "break",
        { "type": "colors", "paddingLeft": 2 }
    ]
}
EOF

	# Parse it back with the binary that has to accept it. A rejected config
	# is not a warning — fastfetch prints nothing at all and still exits 0,
	# so without this the step would report success and leave the user with
	# a terminal where "fastfetch" is a one-line error.
	FF_ERR="$(fastfetch --config "$FF_CONF" 2>&1 >/dev/null)"
	if printf '%s' "$FF_ERR" | grep -q 'JsonConfig Error'; then
		log_err "fastfetch rejected the config it was just given:"
		printf '  %s\n' "$FF_ERR" | sed 's/^/  /'
		if [ -n "$FF_PREV" ]; then
			mv -f "$FF_PREV" "$FF_CONF" &&
				log_err "Previous config restored from $FF_CONF — nothing was lost."
		else
			rm -f "$FF_CONF"
			log_err "No previous config to restore; the rejected one was removed."
		fi
	elif [ -n "$FF_ERR" ]; then
		log_warn "fastfetch complained about the config (it may still render): $FF_ERR"
	else
		log_ok "Config written to $FF_CONF and accepted by fastfetch."
		log_info "Preview it now with: fastfetch"
	fi
	[ -n "$FF_PREV" ] && [ -f "$FF_PREV" ] && log_info "Previous config kept at $FF_PREV"
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
