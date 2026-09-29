# shellcheck shell=bash
# prompt.sh — the xfcemlg two-line prompt. Pure bash: no binary, no
# framework. Uses the Darkmatter palette (red #e75353, teal #5f8787,
# cream #fbcb97) and Nerd Font glyphs (JetBrainsMono Nerd Font is shipped
# by 17-fonts.sh). Set XFCONF_PLAIN_PROMPT=1 for a glyph-free variant.

: "${XFCONF_PLAIN_PROMPT:=0}"

if [ "$XFCONF_PLAIN_PROMPT" = "1" ]; then
	_ic_user='u'
	_ic_dir='~'
	_ic_git='G'
	_ic_ok='v'
	_ic_err='x'
	_ic_end='>'
else
	_ic_user=$'\uf007' # nf-fa-user
	_ic_dir=$'\uf07b'  # nf-fa-folder
	_ic_git=$'\ue725'  # nf-cod-git_branch
	_ic_ok=$'\uf00c'   # nf-fa-check
	_ic_err=$'\uf00d'  # nf-fa-times
	_ic_end=$'\ue0b0'  # nf-ple-right_half_circle
fi

# 24-bit ANSI for the Darkmatter palette.
_CREAM=$'\e[38;2;251;203;151m'
_TEAL=$'\e[38;2;95;135;135m'
_RED=$'\e[38;2;231;83;83m'
_FG=$'\e[38;2;255;255;255m'
_RESET=$'\e[0m'

PROMPT_DIRTRIM=2

# __xfc_git_prompt — branch (or short SHA) segment; dirty marks with '*'.
__xfc_git_prompt() {
	local b dirty
	b="$(git symbolic-ref --short HEAD 2>/dev/null)" ||
		b="$(git rev-parse --short HEAD 2>/dev/null)" || return 0
	dirty=""
	[ -n "$(git status --porcelain 2>/dev/null)" ] && dirty="*"
	printf '%s%s%s%s%s%s' " ${_RED}${_ic_git}" "${b}" "${_FG}" "${dirty}" "${_RESET}"
	return 0
}

__xfc_ps1() {
	local rc=$? st="" git="" caret
	if command -v git >/dev/null 2>&1; then
		git="$(__xfc_git_prompt)"
	fi
	# Last-exit segment: teal check on success, red cross + code on failure.
	if [ "$rc" -eq 0 ]; then
		st="${_TEAL}${_ic_ok}${_RESET}"
		caret="${_TEAL}${_ic_end}${_RESET}"
	else
		st="${_RED}${_ic_err}[${rc}]${_RESET}"
		caret="${_RED}${_ic_end}${_RESET}"
	fi
	PS1=$(printf '\n%s%s%s%s%s%s\n%s ' \
		"${_CREAM}${_ic_user}" "${USER}@\\h${_RESET}" \
		" ${_TEAL}${_ic_dir}\\w${_RESET}" \
		"$git" " $st" \
		"$caret")
}

PROMPT_COMMAND=__xfc_ps1

# History tuning (append across sessions, dedupe, no transient commands).
HISTSIZE=5000
HISTFILESIZE=10000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize
