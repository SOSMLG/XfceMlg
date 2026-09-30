# shellcheck shell=bash
# aliases.sh — xfcemlg aliases, written from scratch for this toolkit.
# Every alias is guarded so a missing command degrades gracefully, and
# nothing is defined that would shadow a tool the user may have installed
# themselves: `fd` is only aliased to Debian's `fdfind` when `fd` does not
# already exist, and so on.
#
# Command names are resolved once, here, into `_xfc_*` variables. Alias
# bodies are double-quoted so the variable expands at *definition* time —
# a single-quoted alias would defer it to execution, which is the whole
# point of resolving it up front.

# ── Debian's renamed binaries ──────────────────────────────────
# Debian and Devuan ship these as fdfind/batcat; upstream renamed them to
# fd/bat. 18-shell-config.sh also puts ~/.local/bin symlinks in place, but
# an alias costs nothing and works before the symlink exists (or in a shell
# that has not re-hashed yet). Only when the short name is free.
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
	alias fd='fdfind'
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
	alias bat='batcat'
fi

# ── navigation ──
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias ~='cd ~'

# ── listing (eza when present, plain ls otherwise) ──
if command -v eza >/dev/null 2>&1; then
	alias ll="eza -la --group --header --git --icons --group-directories-first"
	alias la="eza -la --group --header --git --icons --group-directories-first"
	alias lt="eza --tree --level=2 --icons"
	alias lh="eza -la --group --sort=modified --reverse"
else
	alias ll='ls -laF'
	alias la='ls -A'
	alias lt='ls -R'
	alias lh='ls -lath'
fi

# ── file safety (never in a root shell) ──
if [ "$(id -u)" -ne 0 ]; then
	alias cp='cp -i'
	alias mv='mv -i'
	alias rm='rm -i'
fi
alias mkdir='mkdir -p'

# ── sizes and disk usage ──
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
command -v ncdu >/dev/null 2>&1 && alias disk='ncdu -x'
command -v free >/dev/null 2>&1 && alias free='free -h'

# ── text search ──
# `grep` stays real GNU grep — only colourised. It is the one tool here
# that stays load-bearing: scripts, `ps aux | grep`, config files and every
# tutorial on the internet assume that is GNU grep with these semantics, so
# rg is offered *alongside* it rather than in place of it.
#
# The rg shortcuts differ by what they are willing to look at:
#   rgs  tracked + untracked, case-smart
#   rgi  ...and case-insensitive
#   rgh  ...and dotfiles, but never inside .git
#   rga  ...and ignored files too (build output, .venv, target/…)
if command -v rg >/dev/null 2>&1; then
	alias rgs='rg --smart-case'
	alias rgi='rg --smart-case --ignore-case'
	alias rgh='rg --smart-case --hidden --glob "!.git/"'
	alias rga='rg --smart-case --hidden --no-ignore --glob "!.git/"'
fi

# ── git (only when git is installed) ──
if command -v git >/dev/null 2>&1; then
	alias gs='git status -sb'
	alias ga='git add'
	alias gl='git log --oneline --graph --decorate -20'
	alias gd='git diff'
	alias gds='git diff --staged'
	alias glog='git log --oneline --graph --decorate --all'
	alias gsw='git switch'
	alias gcb='git checkout -b'
	alias gco='git checkout'
	alias gpf='git push --force-with-lease'
	alias gsta='git stash'
	alias gamend='git commit --amend --no-edit'
	# Deliberately not `gcm='git commit -m'`: it reads as though the message
	# is optional, and `gcm -a` would then silently commit -a -m "-a".
	# Spell the message out every time: `git commit -m '…'`.
fi

# ── this toolkit's own commands (24-power-user.sh, 23-input-fix.sh) ──
command -v alacritty >/dev/null 2>&1 && alias term='alacritty'
command -v flameshot >/dev/null 2>&1 && alias screenshot='flameshot gui'
command -v xfce-update-check >/dev/null 2>&1 && alias update-check='xfce-update-check'
command -v xfce-menu >/dev/null 2>&1 && alias menu='xfce-menu'
command -v xdg-open >/dev/null 2>&1 && alias open='xdg-open'

# ── less: keep colours, do not clear the screen, remember nothing ──
# -R  keep ANSI colour (grep/git output is colourised throughout)
# -i  ignore case when searching
# -X  do not clear the screen on exit
# -F  quit if the content fits on one screen
# LESSHISTFILE=-  keep less from writing ~/.lesshst; a pager that litters
# the home directory is a small thing that irritates every time.
if command -v less >/dev/null 2>&1; then
	export PAGER='less -R -i -X -F'
	export MANPAGER='less -R -i -X -F'
	export LESS='-R -i -X -F'
	export LESSHISTFILE=-
fi
