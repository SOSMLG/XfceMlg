# shellcheck shell=bash
# hooks.sh — fzf / zoxide / keybind integrations. fzf's key-bindings and
# completion scripts are sourced from the distro's own package files when
# present — nothing is vendored here, and everything degrades gracefully
# when the tool is not installed.

# ── fzf: the official key-bindings/completion shipped by Debian/Devuan ──
if command -v fzf >/dev/null 2>&1; then
	for _f in /usr/share/doc/fzf/examples/key-bindings.bash \
		/usr/share/doc/fzf/examples/completion.bash \
		/usr/share/bash-completion/completions/fzf; do
		[ -r "$_f" ] && source "$_f" 2>/dev/null
	done
	unset _f
	# Darkmatter-flavored default options (see prompt.sh for the palette).
	export FZF_DEFAULT_OPTS='--height 40% --border --prompt="❯ " --color=fg:#ffffff,bg:#1c1b1d,hl:#e75353,fg+:#ffffff,bg+:#121113,hl+:#e75353,info:#5f8787,pointer:#e75353,marker:#fbcb97,header:#5f8787,prompt:#fbcb97'
fi

# ── zoxide: the tool's own bash init (no vendored copy) ──
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"

# ── history keybinds: PgUp / PgDn search (already bound? bind is safe) ──
bind '"\e[5~":history-search-backward' 2>/dev/null || true
bind '"\e[6~":history-search-forward' 2>/dev/null || true
