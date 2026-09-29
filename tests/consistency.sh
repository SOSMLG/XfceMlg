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

# ── C1: step-script headers (XMLG_DESC + XMLG_DEFAULT) ────────────────
echo "  [consistency] step-script headers"
BAD_HDR=0
for f in scripts/[0-9][0-9]-*.sh; do
	[ -f "$f" ] || continue
	NAME="$(basename "$f")"
	DESC="$(grep -m1 '^# XMLG_DESC:' "$f" 2>/dev/null | sed 's/^# XMLG_DESC: *//')"
	DEFLT="$(grep -m1 '^# XMLG_DEFAULT:' "$f" 2>/dev/null | sed 's/^# XMLG_DEFAULT: *//')"

	if [ -z "$DESC" ]; then
		t_fail "$NAME missing XMLG_DESC header"
		BAD_HDR=1
	fi
	if [ -z "$DEFLT" ]; then
		t_fail "$NAME missing XMLG_DEFAULT header"
		BAD_HDR=1
	elif [ "$DEFLT" != "Y" ] && [ "$DEFLT" != "N" ]; then
		t_fail "$NAME XMLG_DEFAULT is '$DEFLT' (must be Y or N)"
		BAD_HDR=1
	fi
done
[ "$BAD_HDR" -eq 0 ] && t_ok "all step scripts have valid XMLG_DESC/DEFAULT headers"

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

# A `RENAMED` alias in run.sh that points at a file which no longer exists is
# a silent no-op: `./run.sh --only <oldname>` prints "was renamed to X" and
# then runs nothing at all. That is exactly what happened when
# 18-butterbash.sh became 18-shell-reset.sh (0.8.0) and then
# 18-shell-config.sh (0.8.1, when the step grew a from-scratch deploy half),
# so pin every target to a real file.
echo "  [consistency] run.sh RENAMED aliases resolve"
renamed_stale=0
while IFS=$'\t' read -r _alias _target; do
	[ -n "$_target" ] || continue
	if [ ! -f "scripts/$_target" ]; then
		t_fail "run.sh RENAMED[$_alias] points at scripts/$_target which does not exist"
		renamed_stale=$((renamed_stale + 1))
	fi
done < <(sed -n '/declare -A RENAMED=(/,/^)/p' run.sh |
	grep -oE '\[[a-zA-Z]+\]=[0-9A-Za-z_.-]+\.sh' |
	tr -d '[]' | tr '=' '\t')
[ "$renamed_stale" -eq 0 ] && t_ok "every run.sh RENAMED alias resolves to a real step"

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
if [ -f "configs/share/xfcemlg/xfce-menu.py" ]; then
	t_assert_not_grep "xfce-menu has no Theme-List entry" 'xfce-theme-list' \
		"configs/share/xfcemlg/xfce-menu.py"
fi
if [ -f "scripts/24-power-user.sh" ]; then
	t_assert_not_grep "24-power-user does not reference the engine" 'theme-apply|theme_set' \
		"scripts/24-power-user.sh"
fi

# ── C11: 24-power-user.sh deploys bin scripts ────────────────────────────────
echo "  [consistency] 24-power-user.sh deploys expected bins"
PUSER="scripts/24-power-user.sh"
if [ -f "$PUSER" ]; then
	for bin in xfce-update-check xfce-menu xfce-update-gui xfce-lock xfce-suspend \
		xfce-record xfce-scratch xfce-raise xfce-battery-warn xfce-temp-warn \
		xfcemlg-health xfcemlg; do
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
for doc in AGENTS.md docs/FIXES.md docs/BUILDING.md scripts/skills/xfcemlg-SKILL.md; do
	t_assert "file exists: $doc" [ -f "$doc" ]
done

# ── C14: deb packaging wired ─────────────────────────────────────────────────
echo "  [consistency] deb packaging wired"
for req in 'DEB_NAME  :=' 'DEB_VER   :=' 'pkg-deb:' 'check-deb:' 'dpkg-deb --build'; do
	t_assert_grep "Makefile has $(echo "$req" | sed 's/[:= ].*//')" "$req" Makefile
done
for art in packages/xfcemlg-assets/DEBIAN/control \
	packages/xfcemlg-assets/DEBIAN/postinst \
	packages/xfcemlg-assets/usr/share/doc/xfcemlg-assets/copyright \
	packages/xfcemlg-assets/usr/share/doc/xfcemlg-assets/changelog; do
	t_assert "deb tree has $art" [ -f "$art" ]
done
t_assert_grep 'Makefile .gitignore covers build output' '/build/' .gitignore
if grep -q 'cp -a themes' Makefile; then
	t_fail "Makefile still stages the deleted themes/ palette tree"
else
	t_ok "Makefile no longer copies themes/ (payload ships inside configs/)"
fi

# ── C15: XFPM property names are real, and the seed matches the script ───────
# 13-hardware.sh used to write `brightness-on-ac`/`brightness-on-battery`.
# Those names do not exist in xfce4-power-manager (the real ones are
# `brightness-level-on-*`), and `xfconf-query -n` creates any key and returns
# success — so the script created two dead properties and logged success while
# battery brightness was never actually applied. The seed XML shipped the same
# dead names, so a fresh install inherited them too.
#
# Two things are asserted here because both are needed to stop a regression:
#   1. every property the script writes is a real XFPM property, and
#   2. the script and the seed agree on names AND values.
# The name list is a guard, not a source of truth: the authoritative check was
# done against the xfce4-power-manager-4.20.0 tag (settings/xfpm-settings.c
# and common/xfpm-enum-glib.h).
echo "  [consistency] XFPM property names + seed/script agreement"
XFPM_SEED="configs/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml"
XFPM_SCRIPT="scripts/13-hardware.sh"

# Properties the script manages, as "name type value" triples from pm_set calls.
xfpm_script_props() {
	sed -n -E 's/^[[:space:]]*pm_set[[:space:]]+([a-z0-9-]+)[[:space:]]+([a-z]+)[[:space:]]+([a-z0-9-]+)[[:space:]]*$/\1 \2 \3/p' \
		"$XFPM_SCRIPT" | sort -u
}
# Properties in the seed, as "name type value" triples.
xfpm_seed_props() {
	sed -n -E 's/.*<property name="([a-z0-9-]+)" type="(bool|int|uint|string|double)" value="([a-z0-9-]+)"\/>.*/\1 \2 \3/p' \
		"$XFPM_SEED" | sort -u
}

script_props="$(xfpm_script_props)"
seed_props="$(xfpm_seed_props)"
if [ -z "$script_props" ]; then
	t_fail "could not extract any pm_set property from $XFPM_SCRIPT (regex drift?)"
else
	t_ok "extracted $(printf '%s\n' "$script_props" | wc -l) pm_set properties"
fi

# The dead names must never come back.
for dead in brightness-on-ac brightness-on-battery; do
	if printf '%s\n%s\n' "$script_props" "$seed_props" | grep -q "^$dead "; then
		t_fail "dead XFPM property '$dead' is back (real name is brightness-level-*)"
	else
		t_ok "no dead XFPM property '$dead'"
	fi
done

# The allowlist in the script must cover every property it writes, so a typo
# is refused by pm_set at runtime instead of silently creating a corpse.
# Strip the XFPM_PROPS=" ... " wrapper and pad with spaces, so the first and
# last entries can be matched with the same " $p " test as the middle ones.
allowlist=" $(sed -n '/XFPM_PROPS="/,/"$/p' "$XFPM_SCRIPT" |
	sed -e '1s/.*XFPM_PROPS="//' -e '$s/"[[:space:]]*$//' |
	tr -s ' \t\n' ' ') "
if printf '%s' "$allowlist" | grep -q 'XFPM_PROPS='; then
	t_fail "could not extract the XFPM_PROPS allowlist from $XFPM_SCRIPT (regex drift?)"
fi
allowlist_gaps=0
while read -r p _t _v; do
	[ -n "$p" ] || continue
	case "$allowlist" in
	*" $p "*) ;;
	*)
		allowlist_gaps=$((allowlist_gaps + 1))
		t_fail "pm_set writes '$p' but it is missing from the XFPM_PROPS allowlist"
		;;
	esac
done <<<"$script_props"
[ "$allowlist_gaps" -eq 0 ] && t_ok "every pm_set property is in the XFPM_PROPS allowlist"

# Script and seed must agree on both name and value, or a re-run and a fresh
# install would configure the machine differently.
seed_gaps=0
while read -r name type value; do
	[ -n "$name" ] || continue
	if ! printf '%s\n' "$seed_props" | grep -qx "$name $type $value"; then
		seed_gaps=$((seed_gaps + 1))
		t_fail "seed/script disagree on $name: script has type=$type value=$value"
		sed -n "/<property name=\"$name\"/p" "$XFPM_SEED" | sed 's/^/      seed: /'
	fi
done <<<"$script_props"
[ "$seed_gaps" -eq 0 ] && t_ok "seed XML and script agree on every managed XFPM property"

# The lid enum is easy to get backwards, so pin the two values we rely on.
# XfpmLidTriggerAction: 0=DPMS 1=SUSPEND 2=HIBERNATE 3=LOCK_SCREEN 4=NOTHING
for expect in "lid-action-on-battery 1" "lid-action-on-ac 4"; do
	set -- $expect
	if printf '%s\n' "$script_props" | grep -qx "$1 uint $2"; then
		t_ok "lid enum: $1 = $2"
	else
		t_fail "lid enum wrong: expected $1 = $2 (3 is LOCK_SCREEN, 0 is DPMS)"
	fi
done

# ── C16: retired project names stay retired ────────────────────────────────
#
# This repo absorbed the tree of a different project, and absorbed code from
# more than one source. Their names must not survive where a user, a bug
# report or a package list would show them, because "why does my installed
# config mention another project" is a support question this repo cannot
# answer coherently.
#
# The allowlist is deliberately small, and each entry is a case where the old
# name is the *point*:
#
#   RELEASE.md, docs/PROVENANCE.md  the historical record. Rewriting what a
#       past release actually shipped would be falsifying it, and PROVENANCE
#       exists precisely to record what was retired and why.
#   run.sh     its RENAMED map holds old --only names so someone who typed
#       the old step name still lands on the right step. The key is the
#       feature; C7's sibling guard proves every target still exists.
#   scripts/18-shell-config.sh  the shell step (retirement + from-scratch
#       deploy), which by definition names what it retires.
#   README.md  the step table row describing that step.
#
# Note what is NOT here: the legacy on-disk paths (~/.config/devuan-xfce-setup)
# and the DEVX_* environment prefix. Those are not branding, they are paths
# and variables that real machines still have, and the migration code is
# required to recognise them. Purging them would break upgrades. The DEVX_*
# check below covers the one thing that is actually wrong with them: which name
# takes precedence.
echo "  [consistency] retired project names stay retired"
FOREIGN_BRANDS="debsway ohmydebn oh-my-deb butterbash catppuccin JustAGuyLinux"
FOREIGN_BRAND_ALLOW="RELEASE.md
docs/PROVENANCE.md
run.sh
scripts/18-shell-config.sh
README.md"
foreign_hits=0
for brand in $FOREIGN_BRANDS; do
	# Exclude this file: it necessarily names the brands it bans.
	while IFS= read -r hit; do
		[ -n "$hit" ] || continue
		file="${hit%%:*}"
		if printf '%s\n' "$FOREIGN_BRAND_ALLOW" | grep -qxF "$file"; then
			continue
		fi
		t_fail "retired name '$brand' still present: $hit"
		foreign_hits=$((foreign_hits + 1))
	done < <(git grep -I -n -i -e "$brand" -- . ':!tests/consistency.sh' 2>/dev/null || true)
done
if [ "$foreign_hits" -eq 0 ]; then
	t_ok "no retired project names outside the allowlist"
fi

# The allowlist must not rot: every file it names has to still exist, otherwise
# the rule silently weakens to nothing.
stale_allow=0
while read -r a; do
	[ -n "$a" ] || continue
	if [ ! -f "$a" ]; then
		t_fail "C16 allowlist names $a, which does not exist (rule is now vacuous)"
		stale_allow=$((stale_allow + 1))
	fi
done <<<"$FOREIGN_BRAND_ALLOW"
[ "$stale_allow" -eq 0 ] && t_ok "allowlist entries all exist"

# ── C17: DEVX_CONFIG is a compatibility fallback, never the primary ────────
#
# The toolkit namespace is XMLG_. DEVX_CONFIG is the 0.7.x name, kept only so
# a profile written against the old tree still resolves its picker.colors. It
# must therefore be the *second* choice: a future edit that drops XMLG_CONFIG
# would silently ignore the current namespace and keep honouring a retired one,
# which is exactly the kind of quiet regression nothing else would catch.
echo "  [consistency] DEVX_CONFIG is fallback-only"
devx_bad=0
for py in configs/share/xfcemlg/xfce-menu.py configs/share/xfcemlg/xfce-update-gui.py; do
	[ -f "$py" ] || continue
	first="$(grep -oE 'os\.environ\.get\("(XMLG|DEVX)_CONFIG"\)' "$py" | head -1)"
	if [ "$first" = 'os.environ.get("XMLG_CONFIG")' ]; then
		t_ok "$(basename "$py"): XMLG_CONFIG primary, DEVX_CONFIG fallback"
	elif [ "$first" = 'os.environ.get("DEVX_CONFIG")' ]; then
		t_fail "$(basename "$py"): DEVX_CONFIG is checked FIRST — the retired name is winning"
		devx_bad=$((devx_bad + 1))
	else
		t_fail "$(basename "$py"): found neither XMLG_CONFIG nor DEVX_CONFIG"
		devx_bad=$((devx_bad + 1))
	fi
done
# No other file may use the DEVX_ prefix for anything executable.
while IFS= read -r hit; do
	[ -n "$hit" ] || continue
	file="${hit%%:*}"
	case "$file" in
	configs/share/xfcemlg/xfce-menu.py | configs/share/xfcemlg/xfce-update-gui.py) continue ;;
	RELEASE.md | tests/consistency.sh) continue ;;
	esac
	t_fail "retired DEVX_ prefix still in use: $hit"
	devx_bad=$((devx_bad + 1))
done < <(git grep -I -n -e 'DEVX_' -- . 2>/dev/null || true)
[ "$devx_bad" -eq 0 ] && t_ok "DEVX_ prefix confined to the two documented fallbacks"

# ── C18: the theme/icon fetch URLs are commit SHAs, and each has a hash ──────
#
# 0.8.0 changed these two URLs from `refs/heads/main` / `refs/heads/master` to
# immutable commit SHAs. That change is exactly the kind that half-lands: edit
# the URL, forget the recorded sha256, and the first person to run a fresh
# install gets a checksum mismatch with no obvious cause. The two live in
# different files, so nothing in the language notices.
#
# The checks are all offline. A hash cannot be *verified* without downloading
# 36 MB, but the pairing can be checked: the URL must be a 40-hex commit (not a
# branch), a hash must exist for each, both must be the right length and hex,
# and the URL's commit must be named in the docs that claim it is pinned.
echo "  [consistency] darkmatter fetch is commit-pinned and hashed"
DM_URLS="$(grep -hoE 'codeload\.github\.com/[^/]+/[^/]+/tar\.gz/[A-Za-z0-9._-]+' \
	scripts/lib/darkmatter-fetch.sh 2>/dev/null | sort -u)"
dm_bad=0
n_urls=0
while IFS= read -r u; do
	[ -n "$u" ] || continue
	n_urls=$((n_urls + 1))
	ref="${u##*/}"
	# A regex, not a 40-character case glob: hand-written hex globs get
	# miscounted, and a miscounted one fails *closed* -- it rejects a
	# correctly pinned URL, which is worse than missing one.
	if printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$'; then
		t_ok "fetch URL pinned to a commit: ${u%%/tar.gz/*} @ ${ref:0:8}"
	else
		t_fail "fetch URL is NOT a 40-hex commit SHA (mutable ref?): $u"
		dm_bad=$((dm_bad + 1))
	fi
done <<<"$DM_URLS"
[ "$n_urls" -ge 2 ] || {
	t_fail "expected 2 codeload URLs, found $n_urls"
	dm_bad=$((dm_bad + 1))
}

# A branch ref must never reappear in a URL, even if the 40-hex check above
# were relaxed later.
if grep -qE 'codeload\.github\.com/[^ ]+/tar\.gz/refs/' scripts/lib/darkmatter-fetch.sh 2>/dev/null; then
	t_fail "a codeload URL uses refs/heads (mutable) again"
	dm_bad=$((dm_bad + 1))
fi

# Each URL must have a recorded hash in the caller, of the right shape.
for var in DM_THEME_SHA256 DM_ICONS_SHA256; do
	h="$(grep -m1 -oE "\\\$\{${var}:-[0-9a-f]{64}\}" scripts/21-theme.sh 2>/dev/null |
		grep -oE '[0-9a-f]{64}')"
	if [ -n "$h" ]; then
		t_ok "$var recorded ($h)"
	else
		t_fail "$var has no 64-hex default in 21-theme.sh (fresh installs would fetch unverified)"
		dm_bad=$((dm_bad + 1))
	fi
done

# The stale hashes from the branch-ref era must be gone: they are the exact
# values that would be copied forward by a careless future edit, and they
# cannot match a commit-ref tarball. (This file is excluded from its own
# search, since it has to name the values to reject them — same trade as C16.)
for stale in c8438ce5f87ed7876773a447ce27c3444fb55b268360ae7951548595fc4b6047 \
	ea09183265b256c8eab1163e79b9203c485b0e299eb1d974a5aa43b76b97398f; do
	# Exclude this file: the check necessarily spells the values out.
	if git grep -q -- "$stale" -- . ':!tests/consistency.sh' 2>/dev/null; then
		t_fail "a branch-ref-era sha256 is still present: ${stale:0:12}..."
		dm_bad=$((dm_bad + 1))
	fi
done
[ "$dm_bad" -eq 0 ] && t_ok "no stale branch-ref hashes, URL+hash pairs intact"

echo
t_summary "consistency"
