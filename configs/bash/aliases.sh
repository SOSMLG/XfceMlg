# shellcheck shell=bash
# aliases.sh — xfcemlg aliases, written from scratch for this toolkit.
# Every alias is guarded so a missing command degrades gracefully.

# ── navigation ──
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias ~='cd ~'

# ── listing (eza when present, plain ls otherwise) ──
if command -v eza >/dev/null 2>&1; then
	alias ll='eza -la --group --header --git --icons --group-directories-first'
	alias la='eza -la --group --header --git --icons --group-directories-first'
	alias lt='eza --tree --level=2 --icons'
	alias lh='eza -la --group --sort=modified --reverse'
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
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'

# ── git (only when git is installed) ──
if command -v git >/dev/null 2>&1; then
	alias gs='git status -sb'
	alias ga='git add'
	alias gl='git log --oneline --graph --decorate -20'
	alias gd='git diff'
	alias gds='git diff --staged'
fi

# ── this toolkit's own commands (24-power-user.sh, 23-input-fix.sh) ──
command -v alacritty >/dev/null 2>&1 && alias term='alacritty'
command -v flameshot >/dev/null 2>&1 && alias screenshot='flameshot gui'
command -v xfce-update-check >/dev/null 2>&1 && alias update-check='xfce-update-check'
command -v xfce-menu >/dev/null 2>&1 && alias menu='xfce-menu'

# ── extract(): unpack the common archive formats by extension ──
extract() {
	[ $# -eq 1 ] || {
		printf 'Usage: extract <archive>\n' >&2
		return 1
	}
	case "$1" in
	*.tar.gz | *.tgz) tar -xzf "$1" ;;
	*.tar.bz2 | *.tbz2) tar -xjf "$1" ;;
	*.tar.xz | *.txz) tar -xJf "$1" ;;
	*.tar.zst | *.tzst) tar --zstd -xf "$1" 2>/dev/null || zstd -dc "$1" | tar -x ;;
	*.tar) tar -xf "$1" ;;
	*.zip) unzip "$1" ;;
	*.7z) 7z x "$1" ;;
	*.rar) unrar x "$1" ;;
	*.gz) gunzip -k "$1" ;;
	*.bz2) bunzip2 -k "$1" ;;
	*.xz) xz -dk "$1" ;;
	*.zst) zstd -d "$1" ;;
	*)
		printf 'extract: no rule for %s\n' "$1" >&2
		return 1
		;;
	esac
}
