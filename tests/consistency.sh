#!/usr/bin/env bash
# tests/consistency.sh — tier 3: cross-file regression guards.
# Ensures version strings, palettes, templates, step-script headers,
# README table, .gitignore, and bin-deployment references stay in sync.
# All read-only — no writes, no apt, no X required.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"
. "$SCRIPT_DIR/lib/test-helpers.sh"

# ── C1: step-script headers (DEBSWAY_DESC + DEBSWAY_DEFAULT) ────────────────
echo "  [consistency] step-script headers"
BAD_HDR=0
for f in scripts/[0-9][0-9]-*.sh; do
    [ -f "$f" ] || continue
    NAME="$(basename "$f")"
    DESC="$(grep -m1 '^# DEBSWAY_DESC:' "$f" 2>/dev/null | sed 's/^# DEBSWAY_DESC: *//')"
    DEFLT="$(grep -m1 '^# DEBSWAY_DEFAULT:' "$f" 2>/dev/null | sed 's/^# DEBSWAY_DEFAULT: *//')"

    if [ -z "$DESC" ]; then
        t_fail "$NAME missing DEBSWAY_DESC header"
        BAD_HDR=1
    fi
    if [ -z "$DEFLT" ]; then
        t_fail "$NAME missing DEBSWAY_DEFAULT header"
        BAD_HDR=1
    elif [ "$DEFLT" != "Y" ] && [ "$DEFLT" != "N" ]; then
        t_fail "$NAME DEBSWAY_DEFAULT is '$DEFLT' (must be Y or N)"
        BAD_HDR=1
    fi
done
[ "$BAD_HDR" -eq 0 ] && t_ok "all step scripts have valid DEBSWAY_DESC/DEFAULT headers"

# ── C2: VERSION == latest RELEASE.md heading ─────────────────────────────────
echo "  [consistency] VERSION / RELEASE.md version match"
VERSION="$(cat VERSION 2>/dev/null)"
RELEASE_VER="$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' RELEASE.md 2>/dev/null | awk '{print $2}')"
if [ -z "$VERSION" ] || [ -z "$RELEASE_VER" ]; then
    t_fail "could not read VERSION or RELEASE.md heading"
else
    t_assert_eq "VERSION == latest RELEASE.md heading" "$VERSION" "$RELEASE_VER"
fi

# ── C3: palette validity — required vars + hex format ────────────────────────
echo "  [consistency] palette validity"
REQUIRED_VARS="THEME_NAME THEME_BG THEME_BG_ALT THEME_FG THEME_ACCENT THEME_ACCENT_ALT"
HEX_VARS="THEME_BG THEME_BG_ALT THEME_FG THEME_ACCENT THEME_ACCENT_ALT"
ALACRITTY_NAMES="BG FG BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE"
BRIGHT_NAMES="BRIGHT_BLACK BRIGHT_RED BRIGHT_GREEN BRIGHT_YELLOW BRIGHT_BLUE BRIGHT_MAGENTA BRIGHT_CYAN BRIGHT_WHITE"
HEX_RE='^[0-9a-fA-F]{6}$'

# Build the complete list of palette vars we need to capture via declare -p
ALL_PALETTE_VARS="$REQUIRED_VARS $HEX_VARS FASTFETCH_COLOR GTK_THEME_NAME XFWM_THEME_NAME"
for suffix in $ALACRITTY_NAMES $BRIGHT_NAMES; do
    ALL_PALETTE_VARS="$ALL_PALETTE_VARS ALACRITTY_${suffix}"
done

for pal_dir in themes/*/palette.sh; do
    [ -f "$pal_dir" ] || continue
    PAL="$(basename "$(dirname "$pal_dir")")"

    # Capture palette variables via declare -p (works under set -u;
    # if any required var is unset, declare -p fails → PALETTE_DECLS empty).
    PALETTE_DECLS="$(bash -c ". '$pal_dir'; declare -p $ALL_PALETTE_VARS" 2>/dev/null \
        | sed 's/^declare -- /export /')"
    if [ -z "$PALETTE_DECLS" ]; then
        t_fail "$PAL: palette could not be sourced or is missing required vars"
        continue
    fi
    eval "$PALETTE_DECLS" 2>/dev/null

    for var in $REQUIRED_VARS; do
        eval "val=\"\${$var:-}\""
        if [ -z "$val" ]; then
            t_fail "$PAL: required var $var is empty"
        fi
    done

    for var in $HEX_VARS; do
        eval "val=\"\${$var:-}\""
        if [ -n "$val" ] && ! echo "$val" | grep -qE "$HEX_RE"; then
            t_fail "$PAL: $var = '$val' is not 6-digit hex"
        fi
    done

    # Alacritty vars are always lowercase in palette files
    for suffix in $ALACRITTY_NAMES $BRIGHT_NAMES; do
        var="ALACRITTY_${suffix}"
        eval "val=\"\${$var:-}\""
        if [ -z "$val" ]; then
            t_fail "$PAL: $var is empty"
        elif ! echo "$val" | grep -qE '^[0-9a-f]{6}$'; then
            t_fail "$PAL: $var = '$val' is not lowercase 6-hex"
        fi
    done

    # FASTFETCH_COLOR non-empty and a named color (not hex)
    if [ -z "${FASTFETCH_COLOR:-}" ]; then
        t_fail "$PAL: FASTFETCH_COLOR is empty"
    elif echo "$FASTFETCH_COLOR" | grep -qE '^[0-9a-fA-F]{6}$'; then
        t_fail "$PAL: FASTFETCH_COLOR is hex '$FASTFETCH_COLOR' (expected named color)"
    fi

    # GTK_THEME_NAME, XFWM_THEME_NAME non-empty
    for var in GTK_THEME_NAME XFWM_THEME_NAME; do
        eval "val=\"\${$var:-}\""
        [ -z "$val" ] && t_fail "$PAL: $var is empty"
    done

    # All palette vars set OK = implicit pass per pal (counted above)
done

# ── C4: template / renderer token sync ───────────────────────────────────────
echo "  [consistency] template tokens ↔ theme-apply.sh renderer"
# Tokens used in _t_render sed expressions (the real renderer contract).
# "@TOKEN@" in the file header comment is documentation, not a token.
RENDER_TOKENS="$(grep -oE '@[A-Z_]+@' scripts/lib/theme-apply.sh \
    | sed -n 's/@//gp' \
    | grep -v '^TOKEN$' \
    | sort -u)"
# Tokens present in tpl files
TPL_TOKENS="$(grep -ohE '@[A-Z_]+@' themes/_base/tpl/* 2>/dev/null \
    | sed 's/@//g' | sort -u)"

if [ -z "$RENDER_TOKENS" ]; then
    t_fail "no @TOKEN@ found in theme-apply.sh — is _t_render empty?"
elif [ -z "$TPL_TOKENS" ]; then
    t_fail "no @TOKEN@ found in templates under themes/_base/tpl/"
else
    # Every template token must have a matching sed line
    ORPHAN_TOKENS="$(comm -23 <(echo "$TPL_TOKENS") <(echo "$RENDER_TOKENS"))"
    if [ -n "$ORPHAN_TOKENS" ]; then
        t_fail "template tokens not handled by _t_render: $(echo "$ORPHAN_TOKENS" | tr '\n' ' ')"
    else
        t_ok "every template @TOKEN@ has a matching _t_render sed line"
    fi

    # Every renderer token must appear in at least one template
    UNUSED_TOKENS="$(comm -13 <(echo "$TPL_TOKENS") <(echo "$RENDER_TOKENS"))"
    if [ -n "$UNUSED_TOKENS" ]; then
        t_fail "renderer sed lines for tokens missing from all templates: $(echo "$UNUSED_TOKENS" | tr '\n' ' ')"
    else
        t_ok "every _t_render sed token appears in at least one template"
    fi
fi

# ── C5: palette vars / token mapping: every mapped var exists in every pal ───
echo "  [consistency] palette vars ↔ template token mapping"
# Tokens with non-obvious variable names
declare -A TOKEN_TO_VAR=(
    [ACCENT_HEX]="THEME_ACCENT"
    [ACCENT_ALT_HEX]="THEME_ACCENT_ALT"
    [FASTFETCH_COLOR]="FASTFETCH_COLOR"
)

for pal_dir in themes/*/palette.sh; do
    PAL="$(basename "$(dirname "$pal_dir")")"

    PAL_DECLS="$(bash -c ". '$pal_dir'; declare -p THEME_NAME THEME_BG THEME_BG_ALT THEME_FG THEME_ACCENT THEME_ACCENT_ALT FASTFETCH_COLOR GTK_THEME_NAME XFWM_THEME_NAME $(
        for suffix in $ALACRITTY_NAMES; do printf 'ALACRITTY_%s ' "$suffix"; done
    )" 2>/dev/null | sed 's/^declare -- /export /')"
    if [ -z "$PAL_DECLS" ]; then
        continue  # already flagged in C3
    fi
    eval "$PAL_DECLS" 2>/dev/null

    # Direct-name tokens: @ALACRITTY_FOO@ → $ALACRITTY_FOO
    for suffix in $ALACRITTY_NAMES; do
        var="ALACRITTY_${suffix}"
        eval "val=\"\$$var\""
        [ -z "${val:-}" ] && t_fail "$PAL: palette missing $var for template @${var}@"
    done

    # Non-obvious mappings
    for token in "${!TOKEN_TO_VAR[@]}"; do
        var="${TOKEN_TO_VAR[$token]}"
        eval "val=\"\$$var\""
        [ -z "${val:-}" ] && t_fail "$PAL: palette missing $var for template @${token}@"
    done
done

# ── C6: every step script sources lib/common.sh ─────────────────────────────
echo "  [consistency] step scripts source lib/common.sh"
COMMON_SOURCED=0
for f in scripts/[0-9][0-9]-*.sh; do
    [ -f "$f" ] || continue
    NAME="$(basename "$f")"
    if grep -qE "source.*lib/common\.sh|\. lib/common\.sh|\\..*lib/common\.sh" "$f"; then
        COMMON_SOURCED=$((COMMON_SOURCED + 1))
    else
        t_fail "$NAME does not source lib/common.sh"
    fi
done
t_assert_eq "step scripts sourcing lib/common.sh" \
    "$(ls scripts/[0-9][0-9]-*.sh 2>/dev/null | wc -l)" \
    "$COMMON_SOURCED"

# ── C7: README documents every step script ───────────────────────────────────
echo "  [consistency] README parity"
mapfile -t ACTUAL_STEPS < <(ls scripts/[0-9][0-9]-*.sh 2>/dev/null | xargs -I{} basename {} | sort)
README_SCRIPTS="$(grep -oE '[0-9]{2}-[a-z0-9-]+\.sh' README.md 2>/dev/null | sort -u)"

for step in "${ACTUAL_STEPS[@]}"; do
    if ! echo "$README_SCRIPTS" | grep -qF "$step"; then
        t_fail "step $step not documented in README.md"
    fi
done

# Dead rows: scripts referenced in README that don't exist
for step in $README_SCRIPTS; do
    [ -f "scripts/$step" ] || t_fail "README references $step but file does not exist"
done

# ── C8: .gitignore covers key artifacts ──────────────────────────────────────
echo "  [consistency] .gitignore coverage"
for pattern in 'live-sdk/' 'live-build.log' '__pycache__' 'rootfs-overlay/' 'build/' 'dist/'; do
    t_assert_grep ".gitignore covers $pattern" "$pattern" .gitignore
done

# ── C9: sync-overlay uses theme engine ───────────────────────────────────────
echo "  [consistency] blend sync-overlay theme engine integration"
OVERLAY="blend/devuan-xfce-thinkpad/sync-overlay.sh"
if [ -f "$OVERLAY" ]; then
    t_assert_grep "sync-overlay sources theme-apply.sh" \
        'theme-apply\.sh' "$OVERLAY"
    t_assert_grep "sync-overlay calls theme_seed" \
        'theme_seed' "$OVERLAY"
else
    t_fail "sync-overlay.sh not found at expected path"
fi

# ── C10: bin scripts reference the engine ────────────────────────────────────
echo "  [consistency] bin scripts source theme-apply.sh"
for bin in configs/bin/xfce-theme-set configs/bin/xfce-theme-list; do
    if [ -f "$bin" ]; then
        t_assert_grep "$(basename "$bin") sources theme-apply.sh" \
            'theme-apply\.sh' "$bin"
    else
        t_fail "bin script missing: $bin"
    fi
done

# ── C11: 24-power-user.sh deploys bin scripts ────────────────────────────────
echo "  [consistency] 24-power-user.sh deploys expected bins"
PUSER="scripts/24-power-user.sh"
if [ -f "$PUSER" ]; then
    for bin in xfce-update-check xfce-menu xfce-update-gui xfce-lock xfce-suspend; do
        t_assert_grep "24-power-user.sh deploys $bin" "$bin" "$PUSER"
    done
fi

# ── C12: all 3 palette ids documented in README ──────────────────────────────
echo "  [consistency] README palette documentation"
for pal_dir in themes/*/palette.sh; do
    PAL="$(basename "$(dirname "$pal_dir")")"
    t_assert_grep "README mentions palette $PAL" \
        "$PAL" README.md
done

# ── C13: agent/docs files present ────────────────────────────────────────────
echo "  [consistency] AGENTS.md / docs present"
for doc in AGENTS.md docs/FIXES.md docs/BUILDING.md scripts/skills/xfce-setup-SKILL.md; do
    t_assert "file exists: $doc" [ -f "$doc" ]
done

# ── C14: deb packaging wired ─────────────────────────────────────────────────
echo "  [consistency] deb packaging wired"
for req in 'DEB_NAME  :=' 'DEB_VER   :=' 'pkg-deb:' 'check-deb:' 'dpkg-deb --build'; do
    t_assert_grep "Makefile has $(echo "$req" | sed 's/[:= ].*//')" "$req" Makefile
done
for art in packages/devuan-xfce-assets/DEBIAN/control \
           packages/devuan-xfce-assets/DEBIAN/postinst \
           packages/devuan-xfce-assets/usr/share/doc/devuan-xfce-assets/copyright \
           packages/devuan-xfce-assets/usr/share/doc/devuan-xfce-assets/changelog; do
    t_assert "deb tree has $art" [ -f "$art" ]
done
t_assert_grep 'Makefile .gitignore covers build output' '/build/' .gitignore

echo
t_summary "consistency"