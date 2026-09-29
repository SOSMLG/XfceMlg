# shellcheck shell=bash
# rc.sh — the xfcemlg shell config loader.
#
# Sourced from ~/.bashrc by the guarded hook this toolkit appends
# (scripts/18-shell-config.sh, step 7). Loads aliases, the two-line
# prompt and the fzf/zoxide/keybind hooks.
#
# Interactive-only: when bash starts non-interactively (scp, scripts,
# crons), a sourced .bashrc must do nothing but return.
case $- in
*i*) ;;
*) return 0 ;;
esac

_xfc_bash_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xfcemlg/bash"

for _xfc_part in aliases prompt hooks; do
	[ -r "$_xfc_bash_dir/$_xfc_part.sh" ] && source "$_xfc_bash_dir/$_xfc_part.sh"
done

unset _xfc_bash_dir _xfc_part
