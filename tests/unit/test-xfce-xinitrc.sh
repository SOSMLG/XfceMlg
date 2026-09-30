#!/usr/bin/env bash
# tests/unit/test-xfce-xinitrc.sh — unit tests for the user-xinitrc helper
# (xfce_xinitrc_path / _handoff / _repair / _append in scripts/lib/common.sh).
#
# Why this needs a test: startxfce4 runs ~/.config/xfce4/xinitrc *instead of*
# /etc/xdg/xfce4/xinitrc, and only the stock file runs `exec xfce4-session`.
# So a user xinitrc that reaches EOF without handing back leaves the session
# with nothing to run — LightDM starts it, it returns instantly, and you get
# no panel, no wallpaper and no window manager, with nothing in the logs to
# say why. Both snippets the toolkit seeds there are covered here.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/test-helpers.sh"

TMP="$(make_tmp test-xfce-xinitrc)"
trap 'cleanup_dirs "$TMP"' EXIT

. "$REPO_ROOT/scripts/lib/common.sh"

# log_* are defined by common.sh and would spam the output.
log_ok() { :; }
log_warn() { :; }
log_info() { :; }
log_err() { printf '    (log_err) %s\n' "$1" >&2; }

HOMEDIR="$TMP/home"
mkdir -p "$HOMEDIR"
export HOME="$HOMEDIR"
F="$HOMEDIR/.config/xfce4/xinitrc"

seed_touchpad() {
	xfce_xinitrc_append 'xfcemlg: touchpad natural scroll' <<'XEOF'
# -- xfcemlg: touchpad natural scroll (libinput) --
export XFCE_XINITRC_TEST_TOUCHPAD=1
XEOF
}
seed_qt() {
	xfce_xinitrc_append 'xfcemlg: Qt apps follow the Darkmatter GTK theme' <<'XEOF'
# -- xfcemlg: Qt apps follow the Darkmatter GTK theme --
export QT_QPA_PLATFORMTHEME=gtk3
XEOF
}
# The handoff must be the last executable statement, or later snippets are
# dead code behind an exec that never returns.
exec_line_no() { grep -nE '^[[:space:]]*exec[[:space:]]+/etc/xdg/xfce4/xinitrc' "$F" | cut -d: -f1; }
stmt_line_no() { grep -nF "$1" "$F" | head -1 | cut -d: -f1; }

# ── path helper ───────────────────────────────────────────────────────────
t_assert_eq "xinitrc path is under \$HOME" \
	"$(xfce_xinitrc_path)" "$HOMEDIR/.config/xfce4/xinitrc"

# ── first seed creates the file and the handoff together ──────────────────
seed_touchpad
t_assert "seed created the xinitrc" test -f "$F"
t_assert "handoff present after first seed" xfce_xinitrc_handoff
t_assert "snippet is executable" test -x "$F"

# ── second snippet lands ABOVE the handoff, never behind the exec ─────────
# This is the subtle one: a plain append puts the new snippet after the
# `exec`, where it can never run.
seed_qt
t_assert "handoff still present" xfce_xinitrc_handoff
t_assert_eq "exactly one handoff after two seeds" "$(grep -cE '^[[:space:]]*exec[[:space:]]+/etc/xdg/xfce4/xinitrc' "$F")" "1"
t_assert "Qt snippet is above the exec" \
	test "$(stmt_line_no QT_QPA_PLATFORMTHEME)" -lt "$(exec_line_no)"
t_assert "touchpad snippet is above the exec" \
	test "$(stmt_line_no XFCE_XINITRC_TEST_TOUCHPAD)" -lt "$(exec_line_no)"
t_assert "result is valid shell" sh -n "$F"

# ── idempotent: re-running seeds nothing twice ────────────────────────────
before="$(cat "$F")"
seed_touchpad
seed_qt
t_assert_eq "re-run leaves the file byte-identical" "$(cat "$F")" "$before"
t_assert_eq "one touchpad snippet" "$(grep -cF 'XFCE_XINITRC_TEST_TOUCHPAD' "$F")" "1"
t_assert_eq "one Qt snippet" "$(grep -cF 'QT_QPA_PLATFORMTHEME' "$F")" "1"

# ── a legacy xinitrc that lost the handoff gets repaired ──────────────────
# This is the shipped failure: 23-input-fix.sh and 33-useful-apps.sh wrote
# here directly and never handed back, so XFCE would not start at all.
rm -f "$F"
mkdir -p "$(dirname "$F")"
printf '# -- xfcemlg: touchpad natural scroll (libinput) --\nexport XFCE_XINITRC_TEST_TOUCHPAD=1\n' >"$F"
t_assert "legacy file reports no handoff" test -z "$(xfce_xinitrc_handoff && echo yes)"
xfce_xinitrc_repair >/dev/null
t_assert "repair restores the handoff" xfce_xinitrc_handoff
t_assert "repair preserves the original snippet" \
	grep -qF 'XFCE_XINITRC_TEST_TOUCHPAD' "$F"
t_assert "repaired file is valid shell" sh -n "$F"
# A seed on a repaired file must still land above the handoff.
seed_qt
t_assert "Qt snippet above the exec after repair" \
	test "$(stmt_line_no QT_QPA_PLATFORMTHEME)" -lt "$(exec_line_no)"
t_assert_eq "repair+seed still yields one handoff" \
	"$(grep -cE '^[[:space:]]*exec[[:space:]]+/etc/xdg/xfce4/xinitrc' "$F")" "1"

# ── a hand-written handoff is respected, user content preserved ───────────
rm -f "$F"
mkdir -p "$(dirname "$F")"
printf '# my own tweak\nexport XFCE_XINITRC_TEST_OWN=1\nexec /etc/xdg/xfce4/xinitrc "$@"\n' >"$F"
seed_qt
t_assert "hand-written handoff kept" xfce_xinitrc_handoff
t_assert_eq "no duplicate handoff comment" "$(grep -cF 'xfcemlg: hand off' "$F")" "0"
t_assert "user tweak preserved" grep -qF 'XFCE_XINITRC_TEST_OWN' "$F"
t_assert "Qt snippet above the hand-written exec" \
	test "$(stmt_line_no QT_QPA_PLATFORMTHEME)" -lt "$(exec_line_no)"

# ── repair is a no-op when there is nothing to repair ────────────────────
rm -f "$F"
t_assert "repair on a missing file does not create one" test ! -f "$F"
xfce_xinitrc_repair >/dev/null
t_assert "repair still did not create it" test ! -f "$F"

# ── every seed path the toolkit actually uses ─────────────────────────────
# Mirrors the two callers: 23-input-fix.sh and 33-useful-apps.sh. Both must
# leave a launchable file behind.
for step in touchpad qt; do
	rm -rf "$HOMEDIR/.config"
	seed_touchpad
	[ "$step" = qt ] && seed_qt
	t_assert "$step: handoff present" xfce_xinitrc_handoff
	t_assert "$step: valid shell" sh -n "$F"
done

t_summary "xfce-xinitrc"
