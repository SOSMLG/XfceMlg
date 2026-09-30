# shellcheck shell=bash
# hooks.sh — completion, readline keybinds and the fzf/zoxide integrations.
# Sourced last, after aliases and the prompt, because the keybind block
# below needs to know whether the user is in emacs or vi mode.
#
# Nothing here is vendored: fzf and zoxide source their own distro-shipped
# files when installed, and every block degrades to a no-op when the tool
# is missing. The keybinds are the exception — they are readline settings,
# not a tool, so they are ours to define.

# ── completion ──────────────────────────────────────────────────
# bash-completion is a separate package, and on Debian it does *not* load
# itself from .bashrc — it is pulled in by /etc/bash_completion, which
# Debian's stock ~/.bashrc sources. Sourcing it here as well is safe
# because bash-completion is idempotent, and it is the only way this
# config works on a machine where that line is missing.
if ! declare -F __load_completion >/dev/null 2>&1 &&
	[ -r /usr/share/bash-completion/bash_completion ]; then
	source /usr/share/bash-completion/bash_completion 2>/dev/null
fi

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
	# FZF_DEFAULT_COMMAND is what Ctrl-T and the completion widget feed
	# themselves. `fd` when it exists, else `find` — the same preference
	# order as ff() in functions.sh, and the .git exclusion is what keeps
	# the file finder from walking object stores.
	if command -v fd >/dev/null 2>&1; then
		export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
	elif command -v fdfind >/dev/null 2>&1; then
		export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --exclude .git'
	else
		export FZF_DEFAULT_COMMAND='find . -name .git -prune -o -type f -print'
	fi
	export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
	# Previews: an image shows as an image, a document as its first page.
	export FZF_CTRL_T_OPTS="--preview 'file --brief --mime-type {} 2>/dev/null | grep -q image && chafa --size=40x20 {} 2>/dev/null || bat --color=always --style=numbers {} 2>/dev/null || cat {} 2>/dev/null'"
	export FZF_ALT_C_OPTS="--preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {} 2>/dev/null'"
fi

# ── zoxide: the tool's own bash init (no vendored copy) ──
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"

# ── readline keybinds ───────────────────────────────────────────
#
# Ctrl-R already searches history; the PgUp/PgDn pair below searches history
# *by prefix* (history-search-backward/forward), which is the thing people
# actually reach for after typing the first few characters of a long
# command. The other bindings are the standard vi/emacs disagreements
# resolved once, here, so the behaviour is the same in every new terminal.
#
# All of this only means anything in an interactive shell with readline;
# `bind` in a script is a no-op, and every call is guarded so a stripped
# build cannot make the config fail.
if [[ $- == *i* ]] && command -v bind >/dev/null 2>&1; then
	# Prefix search backwards/forwards through the history list.
	bind '"\e[5~":history-search-backward' 2>/dev/null || true
	bind '"\e[6~":history-search-forward' 2>/dev/null || true

	# Home/End, which some terminals only send in application mode.
	bind '"\e[1~":beginning-of-line' 2>/dev/null || true
	bind '"\e[4~":end-of-line' 2>/dev/null || true

	# Delete the word *before* the cursor on Ctrl-W. Readline's default is
	# backward-kill-word, but Ctrl-W is bound to unix-word-rubout in some
	# configurations, which eats a trailing space first; this is the
	# behaviour that does not surprise anyone.
	bind '"\C-w":backward-kill-word' 2>/dev/null || true

	# Ctrl-Y yanks the most recent kill — the default in bash, but emacs
	# muscle memory expects it after an accidental Ctrl-K.
	bind '"\C-y":yank' 2>/dev/null || true

	# Alt-. inserts the last word of the previous command. A small,
	# high-frequency win: `cd /very/long/path` then `Alt-.` `Alt-.`.
	bind '"\e.":yank-last-arg' 2>/dev/null || true

	# Bash's second-Tab (menu-complete) and its default Ctrl-W
	# (backward-kill-word) are left as they are — those are the emacs
	# defaults and the ones muscle memory is built on.
fi
