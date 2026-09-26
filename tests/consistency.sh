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

# ── C3: Darkmatter fetched-at-install — no bulky bundles in the repo ─────────
echo "  [consistency] Darkmatter themes/icons fetched-at-install (bundles gone)"
t_assert "fetch lib exists" [ -f scripts/lib/darkmatter-fetch.sh ]
t_assert_grep "lib pins the darkmatter-linux upstream" 'stevedylandev/darkmatter-linux' scripts/lib/darkmatter-fetch.sh
t_assert_grep "lib pins the Zafiro upstream" 'zayronxio/Zafiro-icons' scripts/lib/darkmatter-fetch.sh
t_assert "configs/themes bundle removed" [ ! -e configs/themes ]
t_assert "configs/icons bundle removed" [ ! -e configs/icons ]
t_assert "configs/rofi config removed" [ ! -e configs/rofi ]
t_assert_grep "21-theme.sh fetches the theme" 'dm_fetch_themes' scripts/21-theme.sh
t_assert_grep "21-theme.sh fetches the icons" 'dm_fetch_icons' scripts/21-theme.sh
t_assert_not_grep "21-theme.sh has no rofi deploy remnant" 'configs/rofi' scripts/21-theme.sh

# ── C4: accent remap policy — stale hex stays out of shipped configs ─────────
echo "  [consistency] accent remap policy (#e78a53 → #e75353)"
# The remap happens at install time; the *shipped* configs must stay clean.
for pat in '#e78a53' '#1a1b26'; do
	STALE="$(grep -rIl "$pat" configs/dunst configs/lightdm 2>/dev/null | head -5)"
	if [ -n "$STALE" ]; then
		t_fail "stale palette hex $pat found in: $STALE"
	else
		t_ok
	fi
done
t_assert_grep "lib remaps text assets to the red accent" 's/#e78a53/#e75353/Ig' scripts/lib/darkmatter-fetch.sh
t_assert_grep "lib remaps PNG pixels to the red accent" "-fill '#e75353'" scripts/lib/darkmatter-fetch.sh
t_assert_grep "lib names the dark icon theme" 'IconTheme=Zafiro-icons-Dark' scripts/lib/darkmatter-fetch.sh

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

# ── C9: icon theme bundle + no stale engine references in shipped code ───────
echo "  [consistency] no theme-engine references in shipped config/code"
OLD_ENGINE_REFS="$(grep -rInE '(source|\.)[[:space:]]+[^#]*theme-apply|theme_seed|theme_set[^_]' \
	scripts/ configs/ --include='*.sh' --include='*.py' 2>/dev/null || true)"
if [ -n "$OLD_ENGINE_REFS" ]; then
	t_fail "theme-engine references still in shipped code:"
	echo -e "$OLD_ENGINE_REFS" | sed 's/^/\t/'
else
	t_ok "no theme-engine references remain in scripts/ configs/ tests/"
fi

# ── C10: widgets/24-power-user freed of the engine ───────────────────────────
echo "  [consistency] power-user surface is engine-free"
if [ -f "configs/share/devuan-xfce-setup/xfce-menu.py" ]; then
	t_assert_not_grep "xfce-menu has no Theme-List entry" 'xfce-theme-list' \
		"configs/share/devuan-xfce-setup/xfce-menu.py"
fi
if [ -f "scripts/24-power-user.sh" ]; then
	t_assert_not_grep "24-power-user does not reference the engine" 'theme-apply|theme_set' \
		"scripts/24-power-user.sh"
fi

# ── C11: 24-power-user.sh deploys bin scripts ────────────────────────────────
echo "  [consistency] 24-power-user.sh deploys expected bins"
PUSER="scripts/24-power-user.sh"
if [ -f "$PUSER" ]; then
	for bin in xfce-update-check xfce-menu xfce-update-gui xfce-lock xfce-suspend; do
		t_assert_grep "24-power-user.sh deploys $bin" "$bin" "$PUSER"
	done
fi

# ── C12: Darkmatter stack documented in README ───────────────────────────────
echo "  [consistency] README Darkmatter documentation"
for marker in 'Darkmatter' 'Zafiro-icons-Dark' 'devuan-darkmatter' '21-theme.sh'; do
	t_assert_grep "README mentions $marker" \
		"$marker" README.md
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
if grep -q 'cp -a themes' Makefile; then
	t_fail "Makefile still stages the deleted themes/ palette tree"
else
	t_ok "Makefile no longer copies themes/ (payload ships inside configs/)"
fi

echo
t_summary "consistency"
