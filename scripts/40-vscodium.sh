#!/usr/bin/env bash
# XMLG_DESC: VSCodium editor (Darkmatter theme) + Neovim retirement
# XMLG_DEFAULT: Y
#  40-vscodium.sh — VSCodium (primary GUI editor) + Neovim retirement
#  Telemetry-free VS Code build, installed via its official APT
#  repo so it updates normally afterward. VSCodium is THE editor
#  (Mousepad/Geany removed by 20-xfce-debloat.sh, Neovim retired here).
#  Ships + activates the bundled Darkmatter color theme extension
#  (configs/vscodium/xfcemlg.darkmatter-theme) and sets
#  workbench.colorTheme=Darkmatter in the user settings.
#  Privilege: priv() (doas-first, sudo fallback)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

if is_installed codium; then
	log_ok "VSCodium (codium) is already installed."
else

	log_head "1/5  Dependencies"
	for dep in wget gpg; do
		if ! command -v "$dep" &>/dev/null; then
			log_info "Installing dependency: $dep"
			apt_update || log_warn "apt-get update failed (continuing with cached lists)."
			priv apt-get install -y "$dep" || {
				log_err "Failed to install $dep"
				exit 1
			}
		fi
	done

	log_head "2/5  APT repository"
	KEYRING="/usr/share/keyrings/vscodium-archive-keyring.gpg"
	SOURCES_FILE="/etc/apt/sources.list.d/vscodium.list"

	# The repo at download.vscodium.com/debs is signed by exactly one key.
	# Verified against the live InRelease, which carries
	#   "issuer fpr v4 1302DE60231889FE1EBACADC54678CF75A278D9C"
	# (Pavlo Rudyi, rsa4096, 2018).
	#
	# We PIN that fingerprint rather than trusting whatever a URL hands
	# back. The old code accepted any parseable key, and its second URL
	# (repo.vscodium.dev) serves a *different* key (9F82ADC6..., Augrain)
	# that does not sign this repo at all — so that "fallback" installed a
	# key which could only ever produce "No public key" while looking like
	# success. Override VSCODIUM_KEY_FPR only on a genuine key rotation.
	VSCODIUM_KEY_FPR="${VSCODIUM_KEY_FPR:-1302DE60231889FE1EBACADC54678CF75A278D9C}"
	KEY_URL="https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"

	log_info "Fetching VSCodium's GPG key (pinned to ${VSCODIUM_KEY_FPR:0:16}…)..."
	KEY_TMP="$(mktemp)"
	KEY_BIN="$(mktemp)"
	cleanup_key_tmp() { rm -f "$KEY_TMP" "$KEY_BIN"; }

	KEY_STATE="failed"
	if curl -fsSL "$KEY_URL" -o "$KEY_TMP" 2>/dev/null && [ -s "$KEY_TMP" ]; then
		if gpg --batch --yes --dearmor -o "$KEY_BIN" "$KEY_TMP" 2>/dev/null && [ -s "$KEY_BIN" ]; then
			GOT_FPR="$(gpg --batch --show-keys --with-colons "$KEY_BIN" 2>/dev/null |
				awk -F: '/^fpr:/ {print $10; exit}')"
			if [ "$GOT_FPR" = "$VSCODIUM_KEY_FPR" ]; then
				KEY_STATE="verified"
			else
				log_err "Fetched key does NOT match the pinned fingerprint."
				log_err "  expected: $VSCODIUM_KEY_FPR"
				log_err "  got:      ${GOT_FPR:-<none>}"
				log_err "Refusing to install it; the existing $KEYRING is untouched."
			fi
		else
			log_err "Downloaded key is not valid OpenPGP data."
		fi
	else
		log_err "Could not download $KEY_URL"
	fi

	if [ "$KEY_STATE" != "verified" ]; then
		# Deliberately NOT `rm -f "$KEYRING"` here: on a re-run over a
		# working setup, a transient network failure must not delete a good
		# keyring and break an already-working repository.
		cleanup_key_tmp
		log_err "VSCodium signing key not installed — APT repo not configured."
		log_info "Fix: check network access to $KEY_URL, or drop the correct key"
		log_info "     at $KEYRING yourself (fingerprint $VSCODIUM_KEY_FPR)."
		exit 1
	fi

	# Atomic install: write beside the target (same filesystem) then rename,
	# so an interrupted install can never leave a truncated keyring in place.
	if priv install -o root -g root -m 644 "$KEY_BIN" "${KEYRING}.tmp.$$" &&
		priv mv -f "${KEYRING}.tmp.$$" "$KEYRING"; then
		log_ok "Key installed to $KEYRING (fingerprint verified)"
	else
		priv rm -f "${KEYRING}.tmp.$$" 2>/dev/null || true
		cleanup_key_tmp
		log_err "Failed to install the VSCodium key to $KEYRING."
		exit 1
	fi
	cleanup_key_tmp

	log_info "Adding VSCodium APT repository..."
	ARCH="$(dpkg --print-architecture)"
	if echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://download.vscodium.com/debs vscodium main" |
		priv tee "$SOURCES_FILE" >/dev/null; then
		log_ok "Repository added at $SOURCES_FILE (scoped to arch=${ARCH})"
	else
		log_err "Failed to write $SOURCES_FILE"
		exit 1
	fi

	log_head "3/5  Install"
	# New repo just added: must refresh even when the runner otherwise skips per-script updates.
	# The vscodium index omits Valid-Until and is refreshed rarely (server keeps re-serving a
	# stale InRelease), so a transient fetch blip can leave apt-cache without a candidate even
	# though the repo is fine — wipe the cached index and retry once rather than failing first.
	cand() { apt-cache policy codium 2>/dev/null | awk -F': ' '/Candidate:/{gsub(/ /,"",$2); print $2}'; }
	registered() {
		local c
		c="$(cand)"
		[[ -n "$c" ]] && [[ "$c" != "(none)" ]] &&
			apt-cache policy codium 2>/dev/null | grep -q "download.vscodium.com"
	}
	for attempt in 1 2; do
		priv apt-get update || {
			log_err "apt-get update failed after adding the VSCodium repo."
			exit 1
		}
		registered && break
		if [[ $attempt -eq 1 ]]; then
			log_warn "codium not resolved — wiping the cached vscodium index and retrying once."
			priv rm -f /var/lib/apt/lists/download.vscodium.com*_InRelease \
				/var/lib/apt/lists/download.vscodium.com*_Packages 2>/dev/null || true
		fi
	done
	if ! registered; then
		log_err "codium has no install candidate — the VSCodium repo did not register after two refreshes."
		log_info "Sources file ($SOURCES_FILE):"
		priv cat "$SOURCES_FILE" | sed 's/^/  /'
		log_info "Key fingerprints in $KEYRING:"
		gpg --batch --show-keys "$KEYRING" 2>/dev/null | sed -n '1,6s/^/  /p' || true
		log_info "apt-cache policy codium reports candidate: $(cand)"
		log_info "Check $SOURCES_FILE and $KEYRING, then re-run."
		exit 1
	fi
	if priv apt-get install -y codium; then
		log_ok "VSCodium installed. Launch it with 'codium'."
	else
		log_err "Failed to install codium."
		exit 1
	fi
fi

log_head "4/5  Darkmatter color theme"
THEME_EXT_SRC="$SCRIPT_DIR/../configs/vscodium/xfcemlg.darkmatter-theme"
VSCODIUM_CONFIG="$HOME/.config/VSCodium/User"
VSCODIUM_SETTINGS="$VSCODIUM_CONFIG/settings.json"
EXT_DIR=""
# VSCodium deliberately uses ~/.vscode-oss as its user-data directory (so
# it cannot collide with real VS Code's ~/.vscode). That is where the editor
# actually reads extensions from — confirmed on this box, where the
# previously-installed theme lives in ~/.vscode-oss/extensions. The old list
# preferred ~/.vscodium/extensions, a path nothing creates, so a fresh
# install got a theme the editor would never load.
for candidate in "$HOME/.vscode-oss/extensions" "$HOME/.vscodium/extensions"; do
	if [[ -d "$candidate" ]]; then
		EXT_DIR="$candidate"
		break
	fi
done
if [[ -n "$EXT_DIR" && "$EXT_DIR" == "$HOME/.vscodium/extensions" ]]; then
	log_warn "Only the legacy ~/.vscodium/extensions exists; VSCodium reads ~/.vscode-oss/extensions."
fi
if command -v codium &>/dev/null; then
	if [[ -z "$EXT_DIR" ]]; then
		EXT_DIR="$HOME/.vscode-oss/extensions"
		mkdir -p "$EXT_DIR"
	fi
	if [[ -d "$THEME_EXT_SRC" ]]; then
		EXT_DEST="$EXT_DIR/xfcemlg.darkmatter-theme"
		if [[ -f "$EXT_DEST/package.json" ]]; then
			cp "$EXT_DEST/package.json" "${EXT_DEST}/package.json.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
			log_info "Backed up existing Darkmatter theme extension metadata."
		fi
		rm -rf "$EXT_DEST"
		cp -r "$THEME_EXT_SRC" "$EXT_DEST"
		chmod -R u+rwX,go+rX "$EXT_DEST"
		log_ok "Darkmatter theme extension deployed to $EXT_DEST."
	else
		log_warn "Darkmatter theme extension seed missing at $THEME_EXT_SRC."
	fi
	mkdir -p "$VSCODIUM_CONFIG"
	if [[ -f "$VSCODIUM_SETTINGS" ]]; then
		cp "$VSCODIUM_SETTINGS" "${VSCODIUM_SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
		log_info "Backed up existing VSCodium settings.json."
	fi
	python3 - "$VSCODIUM_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
if data.get("workbench.colorTheme") != "Darkmatter":
    data["workbench.colorTheme"] = "Darkmatter"
# Darkmatter-consistent editor defaults — only keys the user hasn't set
# themselves, so hand-made settings always win.
DEFAULTS = {
    "editor.fontFamily": "'JetBrainsMono Nerd Font', 'monospace'",
    "editor.fontSize": 13,
    "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', 'monospace'",
    "editor.minimap.enabled": False,
    "editor.bracketPairColorization.enabled": True,
    "editor.smoothScrolling": True,
    "files.trimTrailingWhitespace": True,
    "files.insertFinalNewline": True,
    "workbench.startupEditor": "none",
}
for k, v in DEFAULTS.items():
    if k not in data:
        data[k] = v
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
print("colorTheme set to Darkmatter; editor defaults merged")
PYEOF
	log_ok "VSCodium colorTheme set to Darkmatter (relaunch codium to pick up the new theme)."

	# Keybindings — seed once, never clobber the user's own overrides
	KEYBIND_SRC="$SCRIPT_DIR/../configs/vscodium/keybindings.json"
	KEYBIND_DST="$VSCODIUM_CONFIG/keybindings.json"
	if [[ -f "$KEYBIND_SRC" ]] && [[ ! -f "$KEYBIND_DST" ]]; then
		cp "$KEYBIND_SRC" "$KEYBIND_DST"
		log_ok "VSCodium keybindings.json seeded (ctrl+alt+t terminal, ctrl+alt+b sidebar)."
	fi
else
	log_warn "codium not on PATH — theme deploy skipped (re-run after installing VSCodium)."
fi

log_head "5/5  Retire Neovim (optional — VSCodium is the primary editor)"
# Neovim and VSCodium coexist fine — nothing in this toolkit needs Neovim
# gone, and its config is the user's, not ours. So this is a prompt that
# defaults to No, it never uses `purge` unless asked a second time, and it
# NEVER touches ~/.config/nvim.
if is_installed neovim || command -v nvim &>/dev/null; then
	if ask_no_full "Neovim is installed. Remove the neovim package? (VSCodium is the primary editor.)" "N"; then
		# Tarball installs a previous run of this step made: /usr/local/bin/nvim
		# symlinked into /opt/nvim-*. Narrow guard, still asked.
		if [[ -L /usr/local/bin/nvim ]]; then
			_target="$(readlink /usr/local/bin/nvim 2>/dev/null || true)"
			case "${_target:-}" in
			/opt/nvim-*)
				if ask_no_full "Also remove the /opt tarball install behind it?" "Y"; then
					priv rm -f /usr/local/bin/nvim
					for d in /opt/nvim-*/; do
						[[ -d "$d" ]] || continue
						priv rm -rf "$d" && log_info "Removed stale $d."
					done
				fi
				;;
			esac
			unset _target
		fi
		# Script-managed fd shim only (Debian calls it fdfind; the old neovim
		# step symlinked it to fd). Never touch a real fd or ~/.local/bin/fd.
		if [[ -L /usr/local/bin/fd ]] && [[ "$(readlink /usr/local/bin/fd 2>/dev/null)" == "/usr/bin/fdfind" ]]; then
			priv rm -f /usr/local/bin/fd && log_ok "Removed script-managed fd shim (/usr/local/bin/fd -> fdfind)."
		fi
		# `remove` keeps /etc config; `purge` deletes it. Only purge on consent.
		if ask_no_full "Purge Neovim's system config too (apt-get purge), or keep it (apt-get remove)?" "N"; then
			priv apt-get purge -y neovim 2>/dev/null &&
				log_ok "Neovim purged." ||
				log_warn "Neovim purge had issues (continuing)."
		else
			priv apt-get remove -y neovim 2>/dev/null &&
				log_ok "Neovim removed (system config kept)." ||
				log_warn "Neovim remove had issues (continuing)."
		fi
	else
		log_ok "Neovim left installed — it coexists with VSCodium, no conflict."
	fi
else
	log_ok "No Neovim package installed — nothing to do."
fi
# Reported, never moved or deleted: this is the user's editor config (an
# active LazyVim setup, for instance) and no part of this step owns it.
if [[ -d "$HOME/.config/nvim" ]]; then
	log_info "Found a neovim config at $HOME/.config/nvim — left untouched (yours, not this step's)."
fi
log_ok "VSCodium step complete."
