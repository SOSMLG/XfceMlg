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
t_assert_grep "PATH has /usr/sbin" '/usr/sbin' <<< "${PATH:-}"

# ── C3: command_exists — positive + negative ────────────────────────────────
# helper: assert that a command does NOT exist / does not run
assert_not() {
    local desc="$1"; shift
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
cat > "$FAKE_BIN/doas" << EOF
#!/usr/bin/env bash
# shellcheck disable=SC2154
echo "doas \$*" >> "$DOAS_LOG"
EOF
chmod +x "$FAKE_BIN/doas"

cat > "$FAKE_BIN/sudo" << EOF
#!/usr/bin/env bash
# shellcheck disable=SC2154
echo "sudo \$*" >> "$SUDO_LOG"
EOF
chmod +x "$FAKE_BIN/sudo"

# Prepend fake bin so our stubs shadow any system doas/sudo
export PATH="$FAKE_BIN:$PATH"

# C4a: DEBSWAY_PRIV=doas forces doas
unset DEBSWAY_PRIV
priv apt-get install -y bar 2>/dev/null
if [ -f "$DOAS_LOG" ]; then
    t_assert_eq "DEBSWAY_PRIV=doas → doas called" \
        "doas apt-get install -y bar" \
        "$(cat "$DOAS_LOG")"
else
    t_fail "DOAS_LOG not written (priv routing broken)"
fi

# C4b: clear logs; DEBSWAY_PRIV=sudo forces sudo
rm -f "$DOAS_LOG" "$SUDO_LOG"
DEBSWAY_PRIV=sudo
priv apt-get install -y foo 2>/dev/null
if [ -f "$SUDO_LOG" ]; then
    t_assert_eq "DEBSWAY_PRIV=sudo → sudo called" \
        "sudo apt-get install -y foo" \
        "$(cat "$SUDO_LOG")"
else
    t_fail "SUDO_LOG not written (priv routing broken)"
fi

# C4c: DEBSWAY_PRIV unset + both stubs present → doas preferred (default path)
rm -f "$DOAS_LOG" "$SUDO_LOG"
unset DEBSWAY_PRIV
priv apt-get install -y baz 2>/dev/null
if [ -f "$DOAS_LOG" ]; then
    t_assert_eq "DEBSWAY_PRIV unset + both present → doas wins" \
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
cat > "$INI_MULTI" << 'EOF'
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
printf '[Seat:*]\ngreeter-setup-script=/usr/bin/old\n' > "$INI_SINGLE"
ini_dedup_key "$INI_SINGLE" "Seat:*" "greeter-setup-script" "/usr/bin/new" >"$_ini_log" 2>&1
t_assert_not_grep "C7b old value replaced in place" '/usr/bin/old' "$INI_SINGLE"
t_assert_grep "C7b new value present exactly once" 'greeter-setup-script=/usr/bin/new' "$INI_SINGLE"

# C7c: header present but key absent in THAT section → inserted under it,
# keeping exactly one header line.
INI_INS="$TMP/ini-insert.ini"
printf '[Core]\ncolor=red\n' > "$INI_INS"
ini_dedup_key "$INI_INS" "Core" "size" "12" >"$_ini_log" 2>&1
t_assert_eq "C7c no duplicate [Core] header" "$(grep -c '^\[Core\]' "$INI_INS")" "1"
t_assert_grep "C7c inserted under header" '^size=12$' "$INI_INS"

# C7d: no header anywhere → appended as a fresh section, originals intact.
INI_APP="$TMP/ini-append.ini"
printf '[Existing]\nx=1\n' > "$INI_APP"
ini_dedup_key "$INI_APP" "NewSection" "y" "2" >"$_ini_log" 2>&1
t_assert_eq "C7d exactly one [NewSection]" "$(grep -c '^\[NewSection\]' "$INI_APP")" "1"
t_assert_grep "C7d key under new section" '^y=2$' "$INI_APP"
t_assert_grep "C7d existing section intact" '^x=1$' "$INI_APP"
unset _ini_log

echo
t_summary "unit: common.sh"