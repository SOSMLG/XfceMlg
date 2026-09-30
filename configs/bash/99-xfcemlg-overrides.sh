# shellcheck shell=bash
# 99-xfcemlg-overrides.sh — local corrections, loaded *after* the vendored
# payload (scripts/18-shell-config.sh installs it to ~/.config/bash/).
#
# Why this file exists: the vendored third-party tree is kept byte-identical
# to upstream so its licence and diff-ability stay intact, which means its
# machine-specific mistakes cannot be fixed inside it. They are corrected
# here instead, and only here. Anything not named below is upstream
# behaviour, reproduced deliberately.
#
# Sourced from rc.sh, so: interactive shells only, and last.

# ── privilege escalation ──────────────────────────────────────────
# The payload hardcodes bare `sudo`. This box runs a doas-first policy
# (scripts/lib/common.sh priv()), and the vendored aliases are therefore
# both stylistically wrong and, on a doas-only system, non-functional.
# xfc_priv mirrors priv(): doas first, sudo fallback, overridable with
# XMLG_PRIV=doas|sudo.
xfc_priv() {
	case "${XMLG_PRIV:-}" in
	doas) command -v doas >/dev/null 2>&1 && doas "$@" || sudo "$@" ;;
	sudo) sudo "$@" ;;
	*)
		if command -v doas >/dev/null 2>&1; then doas "$@"
		elif command -v sudo >/dev/null 2>&1; then sudo "$@"
		else
			printf 'xfc_priv: no doas or sudo on PATH.\n' >&2
			printf 'Add yourself with: usermod -aG sudo $USER   (then relogin)\n' >&2
			return 1
		fi
		;;
	esac
}

if [ -n "${BASH_VERSION:-}" ]; then
	alias install='xfc_priv apt install'
	alias update='xfc_priv apt update'
	alias upgrade='xfc_priv apt update && xfc_priv apt upgrade'
	alias remove='xfc_priv apt remove'
	alias uplist='xfc_priv apt list --upgradable'
	alias autoremove='xfc_priv apt autoremove --purge'
	alias purge='xfc_priv apt purge'
fi

# ── ports ────────────────────────────────────────────────────────
# The payload aliases ports to `netstat -tulanp`. netstat is gone from
# Debian trixie (iproute2 replaced it), so that alias only ever prints
# "command not found". functions.sh already defines a working `ports`
# function over `ss`; the payload's alias shadows it, so the function is
# re-declared here to take precedence back.
#
# The unalias MUST be its own statement, not a line inside the if. Bash
# parses a whole compound command before running any of it, and this file
# is sourced by an interactive shell, where aliases are expanded as it
# reads. With the unalias inside the block, the parser reached
# `ports() { ... }` and expanded the still-live `ports` alias into
# `netstat -tulanp() { ... }` — a syntax error that aborted the rest of
# the file. Separating the two commands means the alias is already gone
# by the time the definition is read.
unalias ports 2>/dev/null || true
if command -v ss >/dev/null 2>&1; then
	ports() { ss -ltunap "$@"; }
fi
