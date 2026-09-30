#!/usr/bin/env bash
# XMLG_DESC: Retire pre-0.8 shell leftovers, then deploy the vendored butterbash + xfcemlg shell config
# XMLG_DEFAULT: Y
#  18-shell-config.sh — the shell step. It does two jobs:
#
#  (1) Retire the pre-0.8.0 butterbash integration. Up to 0.7.x this step
#      copied a third-party bash configuration framework into
#      ~/.config/bash, let that project's own installer overwrite
#      $HOME/.bashrc with its example rc, and then appended a marked
#      "XFCE ADDITIONS" block to it. The framework is vendored again as of
#      0.9.0 (docs/PROVENANCE.md), but phases 1-6 still run first and
#      unchanged: they clear what an old run wrote into the user's HOME,
#      which is what makes phase 7 idempotent — it can install the current
#      tree over a stale copy without the two ever fighting.
#
#  (2) Deploy this toolkit's own shell config (since 0.8.1): utility
#      functions, aliases, a Nerd-Font two-line prompt, and the
#      completion/fzf/zoxide/keybind hooks, installed to
#      ~/.config/xfcemlg/bash/ and sourced from a guarded block at the end
#      of ~/.bashrc. On top of that it deploys the vendored upstream
#      framework verbatim to ~/.config/bash (GPL-2.0, licence shipped with
#      it) and loads it after the xfcemlg parts, so its prompt and aliases
#      are what the user sees. The tree is never edited in place: the two
#      machine-specific defects it carries are corrected by
#      99-xfcemlg-overrides.sh, which is sourced last.
#
#  Rules this step holds itself to:
#    * every retirement question is ask_no_full with a default of N, so
#      neither --full nor an unattended run can answer it on the user's
#      behalf; the deploy half is append-only and marker-guarded;
#    * every path is shown before it is touched;
#    * $HOME/.bashrc is only ever edited *inside* a marked block, and is
#      replaced (never truncated) only when it is positively identified
#      as the retired project's own file and a pre-0.8 backup exists;
#    * the old step's own backups hold the user's *previous* .bashrc, so
#      they are recovery material: reported, never removed.
#
#  Privilege: priv() (doas first, sudo fallback) for the CLI ergonomics
#  packages in step 1; everything after that lives in the invoking user's
#  HOME.
set -uo pipefail
# NOTE: no -e — this step is best-effort by design: a leftover we cannot
# clean must never abort the rest of the retirement pass.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

# Counters for the closing summary.
N_FOUND=0
N_REMOVED=0
N_LEFT=0

note_found() { N_FOUND=$((N_FOUND + 1)); }
note_removed() { N_REMOVED=$((N_REMOVED + 1)); }
note_left() { N_LEFT=$((N_LEFT + 1)); }

# The two filesystem fingerprints the old integration left behind.
BB_DIR="$HOME/.config/bash"             # the project's config payload
BB_BLOCK_BEGIN="# BEGIN XFCE ADDITIONS" # the block *we* appended
BB_BLOCK_END="# END XFCE ADDITIONS"

# Where step 2 saves a pre-edit copy of .bashrc. Declared up front
# because step 4 reuses it and either step may be skipped; `set -u`
# turns a later reference to an unset variable into a fatal error.
BASHRC_BAK=""

# Exact basenames the old payload consisted of. Used to delete the
# project's files without ever touching a file of the user's own that
# happens to live in the same directory.
BB_PAYLOAD=(aliases.bash prompt.bash fzf.bash keybinds.bash zoxide.bash
	functions/system.bash functions/utils.bash)

# preview <file> [lines] — show the head of a file, indented, so the
# user can recognise it before being asked about it.
preview() {
	local f="$1" n="${2:-6}" line
	[ -f "$f" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		printf '      | %s\n' "$line"
		n=$((n - 1))
		[ "$n" -le 0 ] && break
	done <"$f"
}

# newest_of <glob> — newest path matching a glob, by name. The old
# backups are timestamped %Y%m%d_%H%M%S, so lexical order is
# chronological order. Prints nothing when there is no match.
newest_of() {
	local pat="$1" f out=""
	for f in $pat; do
		[ -e "$f" ] || continue
		out="$f"
	done
	[ -n "$out" ] || return 1
	printf '%s\n' "$out"
}

# is_payload_bashrc <file> — true only if <file> is the project's own
# rc, recognised by two independent strings from its shipped example.
# Both must match, so an ordinary .bashrc is never mistaken for it.
is_payload_bashrc() {
	local f="$1"
	[ -f "$f" ] || return 1
	grep -qF '# Modular .bashrc configuration' "$f" || return 1
	grep -qF 'BASH_CONFIG_DIR="$HOME/.config/bash"' "$f" || return 1
	return 0
}

# show_bashrc_block — print the marked block we appended, if present.
# Requires a *well-formed* block: a BEGIN line, then a matching END
# line after it. A lone END line (or an unterminated BEGIN) is reported
# as "no block" so the stripper never runs on a malformed marker pair —
# that is what stops awk from eating a user's stray marker line.
show_bashrc_block() {
	local f="$HOME/.bashrc" line inblk=0 seen_begin=0
	[ -f "$f" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"$BB_BLOCK_BEGIN"*)
			# A second BEGIN before an END: the pair is malformed.
			[ "$inblk" -eq 0 ] || return 1
			inblk=1
			seen_begin=1
			printf '      | %s\n' "$line"
			continue
			;;
		esac
		if [ "$inblk" -eq 1 ]; then
			printf '      | %s\n' "$line"
			[ "$line" = "$BB_BLOCK_END" ] && inblk=0
		fi
	done <"$f"
	[ "$seen_begin" -eq 1 ] || return 1
	[ "$inblk" -eq 0 ] || return 1
	return 0
}

# ── 1. CLI ergonomics packages ────────────────────────────────
# The old step shipped these tools alongside a vendored framework; the
# tools are wanted on their own merits and make the config below work.
# Installed unconditionally (no ask) — this is the step's job. btop stays
# with 19-fastfetch.sh; duf/git-delta/starship are not re-added (the
# prompt is self-contained bash, see step 6 for what remains unpurged).
#
# fd-find is Debian's package name for `fd` (it installs /usr/bin/fdfind);
# aliases.sh aliases the short name to it when nothing else provides one.
# bash-completion is also in 33-useful-apps.sh, but that step runs later —
# completion is part of *this* config, so it is owned here and the later
# install is simply a no-op. xclip backs the cfile() clipboard function,
# jq backs json().
log_head "1/7  CLI ergonomics packages (bat, eza, fzf, zoxide, ripgrep, fd, ncdu, tree, jq, xclip, unar)"
install_pkgs "CLI ergonomics" bat eza fzf zoxide ripgrep fd-find ncdu tree jq xclip bash-completion unar ||
	log_warn "Some CLI packages failed — the aliases/prompt still deploy and degrade gracefully."

# ── 2. Audit ───────────────────────────────────────────────────
# Read-only. Establish what is actually on this machine before asking
# the user anything about it.
log_head "2/7  Audit: what the old step left behind"

TMP_OUT=""

# (a) the config payload in ~/.config/bash
PAYLOAD_HITS=()
if [ -d "$BB_DIR" ]; then
	for rel in "${BB_PAYLOAD[@]}"; do
		# -f and not -L: only plain files, never a symlink the user made.
		if [ -f "$BB_DIR/$rel" ] && [ ! -L "$BB_DIR/$rel" ]; then
			PAYLOAD_HITS+=("$BB_DIR/$rel")
		fi
	done
fi
if [ "${#PAYLOAD_HITS[@]}" -gt 0 ]; then
	note_found
	log_info "Vendored config payload in $BB_DIR (${#PAYLOAD_HITS[@]} file(s)):"
	for f in "${PAYLOAD_HITS[@]}"; do
		log_info "  $f"
	done
else
	log_ok "No vendored config payload in $BB_DIR."
fi

# (b) anything else sitting in that directory that is not ours — we must
#     not delete those, and their presence changes the cleanup.
STRAY_HITS=()
if [ -d "$BB_DIR" ]; then
	for f in "$BB_DIR"/*.bash "$BB_DIR"/functions/*.bash; do
		[ -f "$f" ] || continue
		known=0
		for rel in "${BB_PAYLOAD[@]}"; do
			[ "$f" = "$BB_DIR/$rel" ] && known=1 && break
		done
		[ "$known" -eq 0 ] && STRAY_HITS+=("$f")
	done
fi
if [ "${#STRAY_HITS[@]}" -gt 0 ]; then
	note_left
	log_warn "Also in that directory, and NOT ours — will be left alone:"
	for f in "${STRAY_HITS[@]}"; do
		log_warn "  $f"
	done
fi

# (c) the marked block in $HOME/.bashrc
if show_bashrc_block >/dev/null 2>&1; then
	note_found
	log_info "Marked XFCE ADDITIONS block in $HOME/.bashrc:"
	show_bashrc_block
else
	log_ok "No marked XFCE ADDITIONS block in $HOME/.bashrc."
fi

# (d) a $HOME/.bashrc that is the project's own file (it replaced the user's)
PAYLOAD_BASHRC=0
if is_payload_bashrc "$HOME/.bashrc"; then
	PAYLOAD_BASHRC=1
	note_found
	log_warn "$HOME/.bashrc is the retired project's own rc (it replaced yours). First lines:"
	preview "$HOME/.bashrc"
fi

# (e) the old backups — recovery material, reported only
BASHRC_BACKUPS=()
for f in "$HOME"/.bashrc.backup.*; do
	[ -f "$f" ] || continue
	BASHRC_BACKUPS+=("$f")
done
DIR_BACKUPS=()
for f in "$HOME"/.config/bash.backup.*; do
	[ -d "$f" ] || continue
	DIR_BACKUPS+=("$f")
done

# ── 3. Take the marked block back out of $HOME/.bashrc ─────────────
# The narrowest possible edit: drop only the lines between the markers,
# keep every other byte, and keep one copy of the pre-edit file.
log_head "3/7  $HOME/.bashrc: remove only the marked XFCE ADDITIONS block"
if [ "${#BASHRC_BACKUPS[@]}" -gt 0 ]; then
	log_info "Pre-0.8 .bashrc backups found (these are YOUR old file — kept):"
	for f in "${BASHRC_BACKUPS[@]}"; do
		log_info "  $f"
	done
fi

if ! show_bashrc_block >/dev/null 2>&1; then
	log_ok "Nothing to do — $HOME/.bashrc has no marked block."
elif ! ask_no_full "Remove the marked 'XFCE ADDITIONS' block from $HOME/.bashrc?" "N"; then
	note_left
	log_warn "Left the block in place (harmless: the aliases just sit there)."
else
	TMP_OUT="$(mktemp)" || TMP_OUT=""
	if [ -z "$TMP_OUT" ]; then
		log_err "mktemp failed — skipping the .bashrc edit."
		note_left
	else
		# Drop every line from the BEGIN marker to the END marker
		# (inclusive). Anything outside the markers is untouched, so no
		# unrelated user content can be lost here.
		awk -v beg="$BB_BLOCK_BEGIN" -v end="$BB_BLOCK_END" '
			index($0, beg) == 1 { inblk = 1; next }
			$0 == end            { inblk = 0; next }
			inblk                { next }
			{ print }
		' "$HOME/.bashrc" >"$TMP_OUT"
		BASHRC_BAK="$HOME/.bashrc.bak.$(date +%Y%m%d%H%M%S)"
		cp -p "$HOME/.bashrc" "$BASHRC_BAK" &&
			mv -f "$TMP_OUT" "$HOME/.bashrc" &&
			{
				log_ok "Marked block removed. Pre-edit copy: $BASHRC_BAK"
				note_removed
			} ||
			{
				log_err "Edit failed — $HOME/.bashrc left untouched."
				note_left
			}
	fi
fi

# ── 4. Remove the vendored config payload ────────────────────────
# Deletes only the exact basenames the payload consisted of, and only
# when nothing else is left — a directory holding one of the user's own
# files is never rmdir'd.
log_head "4/7  ~/.config/bash: remove the vendored config files"
if [ "${#PAYLOAD_HITS[@]}" -eq 0 ]; then
	log_ok "Nothing to remove."
else
	log_info "Will remove these ${#PAYLOAD_HITS[@]} file(s) and nothing else:"
	for f in "${PAYLOAD_HITS[@]}"; do
		log_info "  $f"
	done
	if ask_no_full "Delete the retired project's config files listed above?" "N"; then
		for f in "${PAYLOAD_HITS[@]}"; do
			rm -f -- "$f" && note_removed
		done
		# Only tidy up directories we can prove are now empty.
		rmdir "$BB_DIR/functions" 2>/dev/null && log_info "Removed empty $BB_DIR/functions"
		rmdir "$BB_DIR" 2>/dev/null && log_ok "Removed empty $BB_DIR" ||
			log_info "$BB_DIR kept (not empty — it still holds files of yours)."
	else
		note_left
		log_warn "Kept $BB_DIR — the shell may still source files from it (see step 4)."
	fi
fi

# ── 5. Offer to give the user's own .bashrc back ─────────────────
# Only ever a *replace* with the user's own backup, never a delete and
# never a truncation. If there is no backup, this step does nothing.
log_head "5/7  $HOME/.bashrc: offer to restore your pre-0.8 .bashrc"
if [ "$PAYLOAD_BASHRC" -eq 0 ]; then
	log_ok "$HOME/.bashrc is not the retired project's file — left alone."
else
	RESTORE_SRC=""
	RESTORE_SRC="$(newest_of "$HOME/.bashrc.backup.*")" || RESTORE_SRC=""
	if [ -z "$RESTORE_SRC" ]; then
		note_left
		log_warn "No $HOME/.bashrc.backup.* found, so the original .bashrc is unrecoverable."
		log_warn "$HOME/.bashrc left exactly as it is — review it by hand."
	else
		log_info "Newest pre-0.8 backup: $RESTORE_SRC"
		if [ -n "$BASHRC_BAK" ]; then
			log_info "Your current .bashrc was saved to $BASHRC_BAK already."
		else
			log_info "Your current .bashrc will be saved aside before anything changes."
		fi
		if ask_no_full "Replace $HOME/.bashrc with $RESTORE_SRC?" "N"; then
			if [ ! -f "$BASHRC_BAK" ]; then
				cp -p "$HOME/.bashrc" "$BASHRC_BAK" ||
					{
						log_err "Could not save the current .bashrc — refusing to replace it."
						note_left
						BASHRC_BAK=""
					}
			fi
			if [ -n "$BASHRC_BAK" ] && cp -p "$RESTORE_SRC" "$HOME/.bashrc"; then
				log_ok "$HOME/.bashrc restored from $RESTORE_SRC (previous version: $BASHRC_BAK)."
				note_removed
			else
				log_err "Restore failed — $HOME/.bashrc left as it was."
				note_left
			fi
		else
			note_left
			log_warn "Left $HOME/.bashrc as it is (it still sources \$HOME/.config/bash)."
		fi
	fi
fi

# ── 6. What is deliberately being kept ──────────────────────────
# Everything below was also written by the old step, but removing it
# would either destroy something of the user's, break something they
# use, or undo a change that belongs to the toolkit rather than to the
# retired project. Listed so the decision is visible, not silent.
log_head "6/7  Deliberately left in place"
KEEP_REPORT=()

for f in "${BASHRC_BACKUPS[@]+"${BASHRC_BACKUPS[@]}"}"; do
	KEEP_REPORT+=("$f — your pre-0.8 .bashrc; this is the only copy. Keep.")
done
for f in "${DIR_BACKUPS[@]+"${DIR_BACKUPS[@]}"}"; do
	KEEP_REPORT+=("$f — your pre-0.8 ~/.config/bash, moved aside by the old installer. Keep.")
done

for pair in "fd:fdfind" "bat:batcat"; do
	link="$HOME/.local/bin/${pair%%:*}"
	target="${pair##*:}"
	if [ -L "$link" ]; then
		# Raw readlink, then match on the target's basename: the link may
		# dangle (target not installed) and readlink -f would fail on it.
		raw="$(readlink "$link" 2>/dev/null || true)"
		if [ "${raw##*/}" = "$target" ]; then
			KEEP_REPORT+=("$link — symlink to $target, created so the short command name exists on Debian. Useful, and indistinguishable from one you made. Kept.")
		fi
	fi
done

if [ -f "$HOME/.config/tmux/tmux.conf" ]; then
	KEEP_REPORT+=("$HOME/.config/tmux/tmux.conf — deployed from this toolkit's own configs/tmux.conf, not the retired project's. Kept.")
fi

if command -v delta >/dev/null 2>&1; then
	KEEP_REPORT+=("git-delta as the pager (core.pager/interactive.diffFilter/delta.*) — ordinary wanted config, and you may have changed it since. Left as-is.")
fi

OLD_PKGS="bat duf eza fzf btop ncdu ripgrep tree zoxide unar git-delta starship"
present=""
for p in $OLD_PKGS; do
	command -v "$p" >/dev/null 2>&1 && present="$present $p"
done
if [ -n "$present" ]; then
	KEEP_REPORT+=("CLI packages:$present — the 0.7.x-era apt stack; step 1 now re-owns bat/eza/fzf/zoxide/ripgrep/ncdu/tree/unar deliberately. Not purged.")
fi

if [ "${#KEEP_REPORT[@]}" -gt 0 ]; then
	for f in "${KEEP_REPORT[@]}"; do
		log_info "$f"
	done
	note_left
else
	log_ok "Nothing else from the old step is present."
fi

# ── 7. Deploy the xfcemlg shell config ──────────────────────────
# The from-scratch replacement for the retired framework (0.8.1): our own
# aliases/prompt/hooks, installed under ~/.config/xfcemlg/bash and hooked
# into ~/.bashrc with a guarded, append-only marker block. deploy_seed_file
# keeps the repo's discipline: user edits are the truth (backed up and left
# in place), and the shipped seed only wins when XMLG_FORCE_SEEDS=1.
log_head "7/7  Deploy the shell config: vendored butterbash to ~/.config/bash, xfcemlg parts to ~/.config/xfcemlg/bash"

SHELL_SEED_DIR="$SCRIPT_DIR/../configs/bash"
SHELL_CONF_DIR="$HOME/.config/xfcemlg/bash"

mkdir -p "$SHELL_CONF_DIR" || log_warn "Cannot create $SHELL_CONF_DIR"
for seed in rc.sh functions.sh aliases.sh prompt.sh hooks.sh 99-xfcemlg-overrides.sh; do
	deploy_seed_file "$SHELL_SEED_DIR/$seed" "$SHELL_CONF_DIR/$seed"
done

# -- the vendored third-party payload, restored to ~/.config/bash ----
# configs/butterbash/ is upstream-verbatim (GPL-2.0, its own LICENSE in
# tree). It is deployed with deploy_seed_file like everything else, so a
# user edit is preserved rather than stomped, and XMLG_FORCE_SEEDS=1
# restores the shipped copy. Phase 4 above cleared whatever a pre-0.8.0
# run left in this directory, so what lands now is exactly this tree.
#
# ~/.config/bash is where upstream's own bashrc looks for the payload, so
# it is installed at that path rather than inside the xfcemlg dir.
BB_SRC_DIR="$SCRIPT_DIR/../configs/butterbash"
BB_CONF_DIR="$HOME/.config/bash"
if [ -d "$BB_SRC_DIR/bash" ]; then
	mkdir -p "$BB_CONF_DIR/functions" || log_warn "Cannot create $BB_CONF_DIR/functions"
	bb_deployed=0
	for seed in "$BB_SRC_DIR"/bash/*.bash; do
		[ -f "$seed" ] || continue
		deploy_seed_file "$seed" "$BB_CONF_DIR/$(basename "$seed")" && bb_deployed=$((bb_deployed + 1))
	done
	for seed in "$BB_SRC_DIR"/bash/functions/*.bash; do
		[ -f "$seed" ] || continue
		deploy_seed_file "$seed" "$BB_CONF_DIR/functions/$(basename "$seed")" && bb_deployed=$((bb_deployed + 1))
	done
	# The licence travels with the code, as it must.
	for doc in LICENSE README.md DOCUMENTATION.md; do
		[ -f "$BB_SRC_DIR/$doc" ] && deploy_seed_file "$BB_SRC_DIR/$doc" "$BB_CONF_DIR/$doc"
	done
	log_ok "Vendored shell framework deployed to $BB_CONF_DIR ($bb_deployed source files, GPL-2.0)."
	log_info "rc.sh loads it after the xfcemlg parts, so its prompt and aliases win."
	log_info "99-xfcemlg-overrides.sh then corrects its bare-sudo apt aliases and its netstat-based ports alias."
else
	log_warn "configs/butterbash/bash is missing — the vendored payload was not deployed."
fi

# Hook into ~/.bashrc: one append-only marker block, never rewrites any
# other content of the file. Idempotent — a re-run is a no-op.
XB_BEGIN="# BEGIN xfcemlg-shell"
XB_END="# END xfcemlg-shell"
XB_LINE='[ -r "$HOME/.config/xfcemlg/bash/rc.sh" ] && source "$HOME/.config/xfcemlg/bash/rc.sh"'
if [ -f "$HOME/.bashrc" ] && grep -qF "$XB_BEGIN" "$HOME/.bashrc"; then
	log_ok "$HOME/.bashrc already sources the xfcemlg shell config."
else
	if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.bashrc.xfcemlg.bak" ]; then
		cp -p "$HOME/.bashrc" "$HOME/.bashrc.xfcemlg.bak" &&
			log_info "Pre-append copy of your .bashrc saved to $HOME/.bashrc.xfcemlg.bak"
	fi
	printf '\n%s\n%s\n%s\n' "$XB_BEGIN" "$XB_LINE" "$XB_END" >>"$HOME/.bashrc"
	log_ok "Added the xfcemlg-shell hook to $HOME/.bashrc (append-only)."
fi

log_ok "Shell config deployed to $SHELL_CONF_DIR — open a new terminal to see it."
log_info "The new terminal also prints the fastfetch summary (19-fastfetch.sh);"
log_info "XFCONF_FASTFETCH=0 in ~/.bashrc turns that off."

# ── Summary ────────────────────────────────────────────────────
log_head "Shell config summary"
log_info "Leftovers found:   $N_FOUND"
log_info "Removed:           $N_REMOVED"
log_info "Left alone:        $N_LEFT"
log_info "The shell framework is vendored again as of 0.9.0 (docs/PROVENANCE.md):"
log_info "upstream-verbatim in configs/butterbash/ (GPL-2.0), deployed to"
log_info "~/.config/bash/. The xfcemlg parts live at ~/.config/xfcemlg/bash/ and"
log_info "load first; the audit phases keep no-op'ing on a clean tree."
log_ok "18-shell-config.sh done — prompt, aliases and hooks are live in new terminals."
