# shellcheck shell=bash
# prompt.sh — the xfcemlg two-line prompt. Pure bash: no binary, no
# framework. Uses the Darkmatter palette (red #e75353, teal #5f8787,
# cream #fbcb97) and Nerd Font glyphs (JetBrainsMono Nerd Font is shipped
# by 17-fonts.sh). Set XFCONF_PLAIN_PROMPT=1 for a glyph-free variant.
#
# ── on the git segment's cost ──────────────────────────────────────────
# 0.8.x resolved the branch with `git symbolic-ref`, then `git rev-parse`
# as a fallback, then `git status --porcelain` — up to three forks on
# *every* prompt. Two of them fail outside a repository, and the third
# walks the whole worktree inside one. Measured here, 50 prompts:
#
#                              inside a repo   outside one
#     0.8.x                        7.2 ms          4.8 ms
#     this file                    4.4 ms          0.1 ms
#
# So the branch is read straight out of .git/HEAD by the shell itself: no
# fork, and the same cost inside a repository as outside one. Only the
# dirty marker forks at all, and that one call has the index lock disabled
# so it cannot make a concurrent `git` block on it. Untracked-file scanning
# is the expensive half of that call, so it is opt-in:
#
#     XFCONF_PROMPT_GIT_UNTRACKED=1   count untracked files as dirty
#
# The helpers hand results back through globals and the prompt is built by
# assignment, because `x="$(f)"` and `PS1=$(printf ...)` are each a fork
# too — an earlier draft of this file was slower than the git calls it was
# replacing for exactly that reason.
#
# A backgrounded, cached `git status` — what oh-my-posh does — would get
# the prompt to ~0.1 ms even inside a repository. It is deliberately NOT
# done here: bash prints "[1]+ Done ( trap ... )" into the terminal for
# every background job it reaps, and the only way to stop that is
# `disown`, whose `-a` form would also disown background jobs the user
# started themselves. Trading a surprise in someone's terminal for 4 ms
# nobody can perceive is a bad deal. This stays synchronous and
# side-effect free.

: "${XFCONF_PLAIN_PROMPT:=0}"
: "${XFCONF_PROMPT_GIT_UNTRACKED:=0}"

# Resolved once at load, not on every prompt.
_XFC_HAVE_GIT=0
command -v git >/dev/null 2>&1 && _XFC_HAVE_GIT=1

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

# __xfc_gitdir — the repository's git dir, found without forking.
#
# Walks up from $PWD looking for .git. A .git *directory* is the normal
# case; a .git *file* holding "gitdir: <path>" is a linked worktree or a
# submodule, and the real HEAD lives at the far end of that path. Returns 1
# outside a repository, which is the common case and costs no processes.
#
# Results go in globals rather than on stdout. That is not a style choice:
# `gd="$(__xfc_gitdir)"` is a command substitution, i.e. a fork, so the
# obvious-looking version of this forks twice and is barely quicker than
# the git binaries it replaced. The prompt path allows exactly one fork
# (the `git status` below) and no more.
_XFC_GITDIR=""
_XFC_BRANCH=""

__xfc_gitdir() {
	local d="$PWD" g
	while :; do
		if [ -d "$d/.git" ]; then
			_XFC_GITDIR="$d/.git"
			return 0
		fi
		if [ -f "$d/.git" ]; then
			g=""
			IFS= read -r g <"$d/.git" 2>/dev/null || true
			case "$g" in
			gitdir:*)
				g="${g#gitdir:}"
				g="${g# }"
				[ -d "$g" ] || return 1
				_XFC_GITDIR="$g"
				return 0
				;;
			esac
			return 1
		fi
		[ "$d" = "/" ] && return 1
		d="${d%/*}"
		[ -n "$d" ] || d="/"
	done
}

# __xfc_branch <gitdir> — sets _XFC_BRANCH to the branch name, or to a
# 7-character SHA when HEAD is detached.
__xfc_branch() {
	local head=""
	[ -r "$1/HEAD" ] || return 1
	# `|| true` is load-bearing: read reports failure at EOF even when it
	# assigned the last line, so a HEAD without a trailing newline (which
	# a hand-made one usually has) would otherwise read as "no branch".
	IFS= read -r head <"$1/HEAD" || true
	[ -n "$head" ] || return 1
	case "$head" in
	'ref: refs/heads/'*) _XFC_BRANCH="${head#ref: refs/heads/}" ;;
	*) _XFC_BRANCH="${head:0:7}" ;;
	esac
	return 0
}

# __xfc_git_prompt — set _XFC_GITSEG to the branch/dirty segment, or to
# the empty string outside a repository. Prints nothing.
_XFC_GITSEG=""
__xfc_git_prompt() {
	local dirty untracked=
	_XFC_GITSEG=""
	[ "$_XFC_HAVE_GIT" = 1 ] || return 0
	__xfc_gitdir || return 0
	__xfc_branch "$_XFC_GITDIR" || return 0
	[ -n "$_XFC_BRANCH" ] || return 0

	# Untracked files are excluded by default. `git status --porcelain`
	# with no --untracked-files flag defaults to "normal", which *does*
	# stat every untracked entry and is the bulk of the call's cost; a
	# build tree with tens of thousands of objects pays for that on every
	# single prompt to learn nothing. Opt in to see them.
	#
	# GIT_OPTIONAL_LOCKS=0 keeps this from blocking on — or invalidating —
	# another git process's index refresh.
	#
	# Run it in $PWD, not in the git dir: `git -C <gitdir> status` has no
	# worktree to compare against and reports an empty tree, which reads
	# as "clean" forever. $PWD is inside the worktree by construction —
	# __xfc_gitdir only succeeds when walking up from it found this repo.
	if [ "$XFCONF_PROMPT_GIT_UNTRACKED" = "1" ]; then
		untracked=--untracked-files=all
	else
		untracked=--untracked-files=no
	fi
	dirty=""
	if [ -n "$(GIT_OPTIONAL_LOCKS=0 git status --porcelain "$untracked" 2>/dev/null)" ]; then
		dirty="*"
	fi

	_XFC_GITSEG=" ${_RED}${_ic_git}${_XFC_BRANCH}${_FG}${dirty}${_RESET}"
	return 0
}

# __xfc_title — set the terminal/tab title. A printf builtin, no fork.
# Skipped where the terminal cannot show it. $HOSTNAME is a bash builtin
# variable, so this does not need a `hostname` fork either; note that
# printf would eat "\u"/"\h" as escape sequences, so the real values go in.
__xfc_title() {
	case "${TERM:-}" in
	'' | dumb | unknown) return 0 ;;
	esac
	[ -n "${HOSTNAME:-}" ] || return 0
	printf '\033]0;%s@%s: %s\007' "${USER:-user}" \
		"${HOSTNAME%%.*}" "${PWD/#$HOME/\~}"
	return 0
}

__xfc_ps1() {
	# Must be the first statement: it is the previous command's status.
	local rc=$?
	local st caret seg1
	__xfc_git_prompt
	# Last-exit segment: teal check on success, red cross + code on failure.
	if [ "$rc" -eq 0 ]; then
		st="${_TEAL}${_ic_ok}${_RESET}"
		caret="${_TEAL}${_ic_end}${_RESET}"
	else
		st="${_RED}${_ic_err}[${rc}]${_RESET}"
		caret="${_RED}${_ic_end}${_RESET}"
	fi
	# "\u" and "\w" are left literal on purpose: bash expands them itself at
	# render time, which is what makes a doas/sudo root shell show root
	# instead of the invoking user. 0.8.x interpolated $USER here, so a
	# root shell was indistinguishable from the normal one.
	#
	# Built by assignment rather than `PS1=$(printf ...)`, and with
	# __xfc_git_prompt called directly: command substitution forks, and two
	# invisible forks per prompt cost more than the git call they wrapped.
	seg1="${_CREAM}${_ic_user}"'\u@\h'"${_RESET} ${_TEAL}${_ic_dir}"'\w'"${_RESET}${_XFC_GITSEG} $st"
	PS1=$'\n'"$seg1"$'\n'"$caret"' '
	__xfc_title
}

# Chain rather than clobber: a PROMPT_COMMAND the user set in their own
# .bashrc keeps running, and re-sourcing this file does not stack copies.
case "${PROMPT_COMMAND:-}" in
__xfc_ps1*) ;;
"") PROMPT_COMMAND=__xfc_ps1 ;;
*) PROMPT_COMMAND="__xfc_ps1;${PROMPT_COMMAND}" ;;
esac

# History tuning (append across sessions, dedupe, no transient commands).
HISTSIZE=5000
HISTFILESIZE=10000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize cmdhist
