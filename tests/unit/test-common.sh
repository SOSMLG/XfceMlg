#!/usr/bin/env bash
# tests/unit/test-common.sh — unit tests for scripts/lib/common.sh:
#   - priv() routing with controlled fake doas/sudo
#   - command_exists() correctness
#   - PATH /usr/sbin export guard
#   - is_installed() read-only real check (if dpkg-query present)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/test-helpers.sh"

TMP="$(make_tmp test-common)"
trap 'cleanup_dirs "$TMP"' EXIT

# ── C1: source common.sh (adds sbin to PATH, exports priv) ──────────────────
. "$REPO_ROOT/scripts/lib/common.sh"

# ── C2: PATH contains /usr/sbin (added by common.sh on first source) ────────
t_assert_grep "PATH has /usr/sbin" '/usr/sbin' <<<"${PATH:-}"

# ── C3: command_exists — positive + negative ────────────────────────────────
# helper: assert that a command does NOT exist / does not run
assert_not() {
	local desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		t_fail "$desc"
	else
		t_ok
	fi
}

t_assert "command_exists bash" command_exists bash
t_assert "command_exists true" command_exists true
assert_not "nonexistent-tool-xyz absent" command_exists nonexistent-tool-xyz

# ── C4: priv() routing with stub doas and sudo ──────────────────────────────
# Create fake doas that logs invocation to a file
FAKE_BIN="$TMP/bin"
mkdir -p "$FAKE_BIN"

DOAS_LOG="$TMP/doas.log"
SUDO_LOG="$TMP/sudo.log"

# Fake doas/sudo log their invocation to a file. Use an UNQUOTED heredoc so
# the concrete paths from $DOAS_LOG/$SUDO_LOG are baked in at write time
# (the fake runs as a subprocess; it can't see the caller's shell vars).
cat >"$FAKE_BIN/doas" <<EOF
#!/usr/bin/env bash
# shellcheck disable=SC2154
echo "doas \$*" >> "$DOAS_LOG"
EOF
chmod +x "$FAKE_BIN/doas"

cat >"$FAKE_BIN/sudo" <<EOF
#!/usr/bin/env bash
# shellcheck disable=SC2154
echo "sudo \$*" >> "$SUDO_LOG"
EOF
chmod +x "$FAKE_BIN/sudo"

# Prepend fake bin so our stubs shadow any system doas/sudo
export PATH="$FAKE_BIN:$PATH"

# C4a: XMLG_PRIV=doas forces doas
unset XMLG_PRIV
priv apt-get install -y bar 2>/dev/null
if [ -f "$DOAS_LOG" ]; then
	t_assert_eq "XMLG_PRIV=doas → doas called" \
		"doas apt-get install -y bar" \
		"$(cat "$DOAS_LOG")"
else
	t_fail "DOAS_LOG not written (priv routing broken)"
fi

# C4b: clear logs; XMLG_PRIV=sudo forces sudo
rm -f "$DOAS_LOG" "$SUDO_LOG"
XMLG_PRIV=sudo
priv apt-get install -y foo 2>/dev/null
if [ -f "$SUDO_LOG" ]; then
	t_assert_eq "XMLG_PRIV=sudo → sudo called" \
		"sudo apt-get install -y foo" \
		"$(cat "$SUDO_LOG")"
else
	t_fail "SUDO_LOG not written (priv routing broken)"
fi

# C4c: XMLG_PRIV unset + both stubs present → doas preferred (default path)
rm -f "$DOAS_LOG" "$SUDO_LOG"
unset XMLG_PRIV
priv apt-get install -y baz 2>/dev/null
if [ -f "$DOAS_LOG" ]; then
	t_assert_eq "XMLG_PRIV unset + both present → doas wins" \
		"doas apt-get install -y baz" \
		"$(cat "$DOAS_LOG")"
else
	t_fail "DOAS_LOG not written (prefer-doas default path broken)"
fi

# ── C5: is_installed — read-only real check (skip if dpkg absent) ────────────
if command -v dpkg-query >/dev/null 2>&1; then
	t_assert "is_installed bash (real)" is_installed bash
	assert_not "not is_installed nonexistent-xyz-abc" is_installed nonexistent-xyz-abc
else
	echo "  [unit] dpkg-query not found, skipping is_installed check"
fi

# ── C6: have_priv — true on this box (doas or sudo present) ─────────────────
t_assert "have_priv true on system with sudo/doas" have_priv

# ── C7: ini_dedup_key — sandboxed, SECTION-AWARE INI edits ──────────────────
# priv() is temporarily overridden to run commands directly — the edits below
# only ever touch $TMP files, so no escalation (and no root) is needed.
priv() { "$@"; }
_ini_log=/dev/null

# C7a (regression): key exists in a DIFFERENT non-matching section; must NOT
# be overwritten there — the old code rewrote the first `key=` line regardless
# of section. The key must land inside [Seat:*] instead.
INI_MULTI="$TMP/ini-multi.ini"
cat >"$INI_MULTI" <<'EOF'
[Top]
greeter-setup-script=/usr/bin/wrong-section

[Seat:*]
greeter-session=lightdm-gtk-greeter

[Seat:x]
greeter-setup-script=/usr/bin/stale-setup
EOF
ini_dedup_key "$INI_MULTI" "Seat:*" "greeter-setup-script" "/usr/bin/custom-setup" >"$_ini_log" 2>&1
t_assert_grep "C7a key landed inside [Seat:*]" 'greeter-setup-script=/usr/bin/custom-setup' "$INI_MULTI"
t_assert_grep "C7a foreign section [Top] untouched" 'greeter-setup-script=/usr/bin/wrong-section' "$INI_MULTI"
t_assert_grep "C7a foreign section [Seat:x] untouched" 'greeter-setup-script=/usr/bin/stale-setup' "$INI_MULTI"

# C7b: header present WITH matching key → updated in place, no duplicate key.
INI_SINGLE="$TMP/ini-single.ini"
printf '[Seat:*]\ngreeter-setup-script=/usr/bin/old\n' >"$INI_SINGLE"
ini_dedup_key "$INI_SINGLE" "Seat:*" "greeter-setup-script" "/usr/bin/new" >"$_ini_log" 2>&1
t_assert_not_grep "C7b old value replaced in place" '/usr/bin/old' "$INI_SINGLE"
t_assert_grep "C7b new value present exactly once" 'greeter-setup-script=/usr/bin/new' "$INI_SINGLE"

# C7c: header present but key absent in THAT section → inserted under it,
# keeping exactly one header line.
INI_INS="$TMP/ini-insert.ini"
printf '[Core]\ncolor=red\n' >"$INI_INS"
ini_dedup_key "$INI_INS" "Core" "size" "12" >"$_ini_log" 2>&1
t_assert_eq "C7c no duplicate [Core] header" "$(grep -c '^\[Core\]' "$INI_INS")" "1"
t_assert_grep "C7c inserted under header" '^size=12$' "$INI_INS"

# C7d: no header anywhere → appended as a fresh section, originals intact.
INI_APP="$TMP/ini-append.ini"
printf '[Existing]\nx=1\n' >"$INI_APP"
ini_dedup_key "$INI_APP" "NewSection" "y" "2" >"$_ini_log" 2>&1
t_assert_eq "C7d exactly one [NewSection]" "$(grep -c '^\[NewSection\]' "$INI_APP")" "1"
t_assert_grep "C7d key under new section" '^y=2$' "$INI_APP"
t_assert_grep "C7d existing section intact" '^x=1$' "$INI_APP"
unset _ini_log

# ── C8: start_service must detect OpenRC ───────────────────────────────────
# /run/openrc/softlevel is a REGULAR FILE on OpenRC, not a directory. A
# `-d` test therefore always failed, so every start_service call silently
# took the sysvinit branch on an OpenRC box. Guard the source text.
COMMON_SH="$REPO_ROOT/scripts/lib/common.sh"
t_assert_grep "C8a OpenRC detected with -e (softlevel is a file)" \
	'\[ -e /run/openrc/softlevel \]' "$COMMON_SH"
t_assert_not_grep "C8b no -d softlevel test left behind" \
	'\[ -d /run/openrc/softlevel \]' "$COMMON_SH"

# ── C9: ensure_doas_persist widens a command-scoped rule ────────────────────
# `permit persist u as root command apt-get` authorizes one binary. Treating
# it as "already effective" left the user stuck on a rule that fails on the
# next command. It must be normalized to the toolkit's full rule.
_doas_case() { # <desc> <input> <expected-substring-must-be-present>
	local desc="$1" input="$2" expect="$3"
	local conf="$TMP/doas-$RANDOM.conf"
	printf '%s\n' "$input" >"$conf"
	# stub priv as a passthrough: this exercises the pure text logic only
	(
		priv() { "$@"; }
		export -f priv 2>/dev/null || true
		DOAS_CONF="$conf" ensure_doas_persist tester
	) >/dev/null 2>&1
	if grep -qF "$expect" "$conf" 2>/dev/null; then
		t_ok
	else
		t_fail "$desc (got: $(tr '\n' '|' <"$conf" 2>/dev/null))"
	fi
	rm -f "$conf"
}
_doas_case "C9a command-scoped persist is widened" \
	"permit persist tester as root command apt-get" "permit persist tester as root"
_doas_case "C9b command-scoped nopass is widened" \
	"permit tester as root command doas" "permit persist tester as root"
_doas_case "C9c a full persist rule is left alone" \
	"permit persist tester as root" "permit persist tester as root"
_doas_case "C9d a full nopass rule is left alone" \
	"permit nopass tester as root" "permit nopass tester as root"
_doas_case "C9e another user's rule is not clobbered" \
	"permit persist someoneelse as root" "permit persist someoneelse as root"

# ── C10: migrate_legacy_paths moves pre-0.8.0 state, never clobbers ────────
_mig() { (XMLG_ASSUME_YES=1 migrate_legacy_paths) >/dev/null 2>&1; }
MIGROOT="$TMP/mig"
mkdir -p "$MIGROOT/.config/devuan-xfce-setup" \
	"$MIGROOT/.local/state/devuan-xfce-setup" \
	"$MIGROOT/.cache/devuan-xfce-setup"
echo 'bg0=#121113' >"$MIGROOT/.config/devuan-xfce-setup/picker.colors"
echo 'historic' >"$MIGROOT/.local/state/devuan-xfce-setup/last-run.log"
echo 'tarball' >"$MIGROOT/.cache/devuan-xfce-setup/theme.tgz"
(
	export HOME="$MIGROOT"
	_mig
)
t_assert "C10a legacy config migrated" test -f "$MIGROOT/.config/xfcemlg/picker.colors"
t_assert "C10b legacy state migrated (keeps last-run.log)" \
	test -f "$MIGROOT/.local/state/xfcemlg/last-run.log"
t_assert "C10c legacy cache migrated" test -f "$MIGROOT/.cache/xfcemlg/theme.tgz"
assert_not "C10d legacy config removed" test -d "$MIGROOT/.config/devuan-xfce-setup"
t_assert_grep "C10e migrated content preserved" 'bg0=#121113' \
	"$MIGROOT/.config/xfcemlg/picker.colors"
# idempotent: a second run has nothing to do and must not error
(
	export HOME="$MIGROOT"
	_mig
) && t_ok || t_fail "C10f second run is idempotent"
# never clobber: when the new path already exists, both survive
mkdir -p "$MIGROOT/.config/devuan-xfce-setup"
echo 'hand-edited' >"$MIGROOT/.config/devuan-xfce-setup/picker.colors"
echo 'new-wins' >"$MIGROOT/.config/xfcemlg/picker.colors"
(
	export HOME="$MIGROOT"
	_mig
)
t_assert_grep "C10g existing new path not clobbered" 'new-wins' \
	"$MIGROOT/.config/xfcemlg/picker.colors"
t_assert "C10h legacy left intact when new exists" \
	test -f "$MIGROOT/.config/devuan-xfce-setup/picker.colors"
# fresh install: no legacy paths -> silent no-op
FRESH="$TMP/fresh"
mkdir -p "$FRESH"
(
	export HOME="$FRESH"
	_mig
) && t_ok || t_fail "C10i fresh install is a clean no-op"

# ── C11: deploy_seed_file never clobbers a hand-edited destination ──────────
# The reason this exists: 21-theme.sh used to back the destination up to a
# timestamped .bak and then `cp` over it unconditionally, so every re-run threw
# away whatever the user had changed in the GUI. The stamp file is what makes
# "nobody touched this since we wrote it" distinguishable from "the user
# edited this".
SEEDROOT="$TMP/seedtest"
SEED="$SEEDROOT/seed.xml"
DEST="$SEEDROOT/home/.config/xfce4/xfce4-panel.xml"
STAMP="$DEST.xfcemlg.sha256"
mkdir -p "$(dirname "$DEST")"

# 1. destination missing -> install, and record the stamp
printf 'seed v1\n' > "$SEED"
deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1
t_assert_grep "C11a dest absent -> seed installed" 'seed v1' < "$DEST"
t_assert "C11b stamp written next to dest" test -s "$STAMP"

# 2. re-run with an unchanged seed -> silent no-op, and crucially NO new
#    timestamped .bak, so a repeated run does not litter the config dir.
BEFORE_BAKS=$(find "$SEEDROOT" -name '*.bak.*' | wc -l)
deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1
AFTER_BAKS=$(find "$SEEDROOT" -name '*.bak.*' | wc -l)
t_assert_eq "C11c unchanged re-run writes no new backup" "$BEFORE_BAKS" "$AFTER_BAKS"

# 3. seed upgraded, destination untouched by the user -> safe in-place update
printf 'seed v2\n' > "$SEED"
deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1
t_assert_grep "C11d seed upgrade updates an untouched dest" 'seed v2' < "$DEST"

# 4. the important one: user edited the destination -> refuse, keep their file
printf 'MY OWN PANEL LAYOUT\n' > "$DEST"
deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1 && RC=0 || RC=$?
t_assert_eq "C11e edited dest -> refuses (rc 1)" "1" "$RC"
t_assert_grep "C11f edited dest -> user content preserved" 'MY OWN PANEL LAYOUT' < "$DEST"
t_assert "C11g edited dest -> user copy backed up" \
	test -n "$(find "$SEEDROOT" -name '*.user.*' -print -quit)"

# 5. ...unless the operator explicitly says the seed wins
XMLG_FORCE_SEEDS=1 deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1
t_assert_grep "C11h XMLG_FORCE_SEEDS=1 overrides the user's copy" 'seed v2' < "$DEST"

# 6. pre-0.8.0 machine: dest exists but there is no stamp yet. Treated as
#    adoptable, because there is no evidence anyone edited it.
rm -f "$DEST" "$STAMP"
printf 'legacy\n' > "$DEST"
deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1
t_assert_grep "C11i no stamp yet -> seed adopted" 'seed v2' < "$DEST"

# 7. source missing -> rc 2 and the destination is left completely alone
rm -f "$SEED"
printf 'precious\n' > "$DEST"
deploy_seed_file "$SEED" "$DEST" >/dev/null 2>&1 && RC=0 || RC=$?
t_assert_eq "C11j missing seed -> rc 2" "2" "$RC"
t_assert_grep "C11k missing seed -> dest untouched" 'precious' < "$DEST"

echo
t_summary "unit: common.sh"
