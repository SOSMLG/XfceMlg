# shellcheck shell=bash
# rc.sh — the xfcemlg shell config loader.
#
# Sourced from ~/.bashrc by the guarded hook this toolkit appends
# (scripts/18-shell-config.sh, step 7). Loads functions, aliases, the
# two-line prompt and the completion/fzf/keybind hooks, then prints the
# system summary once per shell.
#
# Interactive-only: when bash starts non-interactively (scp, scripts,
# crons), a sourced .bashrc must do nothing but return.
case $- in
*i*) ;;
*) return 0 ;;
esac

_xfc_bash_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xfcemlg/bash"
_xfc_vendor_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bash"
_xfc_have_vendor=0
[ -d "$_xfc_vendor_dir" ] && _xfc_have_vendor=1

# Order matters: aliases define the tool-name shims the hooks look for
# (fd/bat), and hooks run last because the keybind block inspects the
# readline mode the prompt has already set up.
#
# prompt is skipped when the vendored payload is present. Both files build
# a PROMPT_COMMAND chain, and the payload *prepends* its builder while
# ours appends, so loading both leaves ours running last and silently
# wins — the payload's prompt would never be seen. Skipping ours is the
# only way the vendored prompt can actually take effect.
for _xfc_part in functions aliases prompt hooks; do
	if [ "$_xfc_part" = prompt ] && [ "$_xfc_have_vendor" = 1 ]; then
		continue
	fi
	[ -r "$_xfc_bash_dir/$_xfc_part.sh" ] && source "$_xfc_bash_dir/$_xfc_part.sh"
done

unset _xfc_part

# ── the vendored third-party payload ────────────────────────────
# configs/butterbash/ is restored upstream-verbatim (GPL-2.0, see its own
# LICENSE) and installed to ~/.config/bash by scripts/18-shell-config.sh,
# which is where upstream's own bashrc expects to find it. Loaded here,
# after the xfcemlg parts, so its prompt and aliases are what the user
# actually sees — that is the point of shipping it.
#
# Load order is the same one upstream's bashrc uses, and it is glob order,
# so it is alphabetical: aliases, fzf, keybinds, prompt, zoxide.
if [ "$_xfc_have_vendor" = 1 ]; then
	for _xfc_v in "$_xfc_vendor_dir"/*.bash; do
		[ -r "$_xfc_v" ] && source "$_xfc_v"
	done
	if [ -d "$_xfc_vendor_dir/functions" ]; then
		for _xfc_vf in "$_xfc_vendor_dir/functions"/*.bash; do
			[ -r "$_xfc_vf" ] && source "$_xfc_vf"
		done
	fi
fi
unset _xfc_vendor_dir _xfc_have_vendor _xfc_v _xfc_vf

# Local corrections for that payload's machine-specific mistakes. Last,
# so it has the final word (see the file's own header).
[ -r "$_xfc_bash_dir/99-xfcemlg-overrides.sh" ] &&
	source "$_xfc_bash_dir/99-xfcemlg-overrides.sh"
unset _xfc_bash_dir

# ── the once-per-shell system summary ──────────────────────────
# fastfetch 19-fastfetch.sh writes the config this reads. Switches, all
# optional:
#
#   XFCONF_FASTFETCH=0        do not print it at all
#   XFCONF_FASTFETCH_TMUX=1   print it inside tmux too (off by default —
#                             a logo that redraws a pane is mostly noise)
#
# It is also skipped, without asking, when fastfetch is not installed, when
# the output is not a real terminal (a pipe, a cron job, `bash -c`, a CI
# run — nobody wants an ASCII logo in a log file), and when $TERM is empty
# or `dumb`.
if command -v fastfetch >/dev/null 2>&1; then
	case "${XFCONF_FASTFETCH:-1}" in
	0 | false | no) ;;
	*)
		if [ -t 1 ] && [ -t 2 ] &&
			[ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
			{ [ -z "${TMUX:-}" ] || [ "${XFCONF_FASTFETCH_TMUX:-0}" = "1" ]; }; then
			# Never allowed to break login: if the user points
			# fastfetch at a config of their own and it is broken, the
			# error is discarded and the shell carries on.
			fastfetch 2>/dev/null || true
		fi
		;;
	esac
fi
