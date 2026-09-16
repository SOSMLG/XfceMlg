#!/usr/bin/env bash
# tests/unit/test-theme-apply.sh — sandboxed end-to-end test of
# lib/theme-apply.sh (seed → render → switch palette).
# Run as user, no X session, no root needed.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/test-helpers.sh"

TMP="$(make_tmp test-theme-apply)"
trap 'cleanup_dirs "$TMP"' EXIT

# sandbox env: never touch live X or real config dirs
export DEVX_CONFIG="$TMP/devuan-xfce-setup"
export DEVX_THEMES="$DEVX_CONFIG/themes"
export DEVX_OUT="$TMP/out"
export DEVX_HOME="$TMP/home"
export DEVX_SKIP_XFCONF=1

# source the engine from the repo (same file 24-power-user.sh deploys)
. "$REPO_ROOT/scripts/lib/theme-apply.sh"

# ── C1: seed into a clean tree ──────────────────────────────────────────────
echo "  [unit] theme_seed → tokyonight (default)"
theme_seed "$REPO_ROOT" tokyonight

t_assert_eq "current file written" \
    "tokyonight" \
    "$(cat "$DEVX_CONFIG/current")"

t_assert_eq "picker.colors has 4 keys" \
    "4" \
    "$(wc -l < "$DEVX_CONFIG/picker.colors")"

# ── C2: rendered outputs exist ────────────────────────────────────────────────
for out in alacritty/alacritty.yml gtk-3.0/gtk.css fastfetch/config.jsonc; do
    t_assert "output exists: $out" test -f "$DEVX_OUT/$out"
done

# ── C3: no leftover @TOKEN@ in rendered alacritty.yml ────────────────────────
t_assert_not_grep "no leftover @TOKEN@ in alacritty.yml" \
    '@[A-Z_]*@' \
    "$DEVX_OUT/alacritty/alacritty.yml"

# ── C4: alacritty 0x values are lowercase 6-hex ──────────────────────────────
ALAC_BG="$(sed -n "s/.*background: '0x\([0-9a-f]*\)'.*/\1/p" "$DEVX_OUT/alacritty/alacritty.yml")"
t_assert_eq "alacritty bg 0x matches tokyonight palette" \
    "1a1b26" "$ALAC_BG"

# ── C5: gtk.css references the accent hex from tokyonight ────────────────────
t_assert_grep "gtk.css contains accent hex #bf616a" \
    '#bf616a' \
    "$DEVX_OUT/gtk-3.0/gtk.css"

# ── C6: fastfetch color is named (not hex) ──────────────────────────────────
t_assert_grep "fastfetch config has color key 'blue'" \
    '"blue"' \
    "$DEVX_OUT/fastfetch/config.jsonc"

# ── C7: picker.colors values parse correctly ────────────────────────────────
PICKER="$DEVX_CONFIG/picker.colors"
BG0="$(grep '^bg0=' "$PICKER" | cut -d= -f2)"
BG1="$(grep '^bg1=' "$PICKER" | cut -d= -f2)"
BG3="$(grep '^bg3=' "$PICKER" | cut -d= -f2)"
FG0="$(grep '^fg0=' "$PICKER" | cut -d= -f2)"

t_assert_eq "picker.bg0 is #1a1b26F2"  "#1a1b26F2" "$BG0"
t_assert_eq "picker.bg1 is #16161e"    "#16161e"   "$BG1"
t_assert_eq "picker.bg3 is #bf616aF2"  "#bf616aF2" "$BG3"
t_assert_eq "picker.fg0 is #efefef"    "#efefef"   "$FG0"

# ── C8: theme_list lists all three installed palettes ────────────────────────
LIST="$(theme_list)"
for palette in tokyonight catppuccin-mocha nord; do
    t_assert_grep "theme_list includes $palette" "$palette" <<< "$LIST"
done

# ── C9: render all palettes in a loop → no @TOKEN@ in any output ────────────
echo "  [unit] rendering all palettes in sandbox loop"
for palette in tokyonight catppuccin-mocha nord; do
    theme_set "$palette" >/dev/null 2>&1 || { t_fail "theme_set $palette"; continue; }
    for out in alacritty/alacritty.yml gtk-3.0/gtk.css fastfetch/config.jsonc; do
        f="$DEVX_OUT/$out"
        [ -f "$f" ] || { t_fail "output missing: $out (palette $palette)"; continue; }
        HAS_TOKEN="$(grep -cE '@[A-Z_]*@' "$f" 2>/dev/null || true)"
        t_assert_eq "no @TOKEN@ in $out (palette $palette)" "0" "$HAS_TOKEN"
    done
    # picker.colors hex validation
    THIS_BG0="$(grep '^bg0=' "$DEVX_CONFIG/picker.colors" | cut -d= -f2)"
    if echo "$THIS_BG0" | grep -qE '^#[0-9a-fA-F]{8}$'; then
        t_ok  # bg0 is valid #hex + F2 suffix
    else
        t_fail "picker.bg0 invalid hex for palette $palette: $THIS_BG0"
    fi
done

# ── C10: theme_set with bad id exits 2 ──────────────────────────────────────
RC=0; theme_set "definitely-not-a-palette-xyz" >/dev/null 2>&1 || RC=$?
t_assert_eq "theme_set bad id exits 2" "2" "$RC"

# ── C11: xfce-theme-list script deployed to bin ──────────────────────────────
THEME_BIN="$DEVX_HOME/.local/bin"
t_assert "xfce-theme-list deployed" test -f "$THEME_BIN/xfce-theme-list"
t_assert "xfce-theme-set  deployed" test -f "$THEME_BIN/xfce-theme-set"

echo
t_summary "unit: theme-apply (sandbox)"