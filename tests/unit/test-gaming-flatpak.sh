#!/usr/bin/env bash
# tests/unit/test-gaming-flatpak.sh — unit tests for
# scripts/lib/gaming-flatpak.sh, the "native over Flatpak" Heroic purge
# offered by 44-gaming.sh:
#   - no-op unless the native Heroic AND the Flatpak Heroic both exist
#   - a confirmed purge removes via priv() (doas-first) with --delete-data
#   - ask_no_full discipline: never auto-fires on --full or --yes
#   - gaming_flatpak_uninstall propagates priv()'s exit status
#
# PATH is fully replaced (NOT "fake:$PATH") on every case: the dev box and
# CI hosts may carry a real /usr/bin/heroic that must not leak into the
# native-detection, so the hermetic bin dirs are the ONLY commands visible.
# Real tools the lib legitimately needs (grep) live in FAKE_SYS by explicit
# symlink; any other "command not found" fails loudly instead of passing
# silently.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/test-helpers.sh"

TMP="$(make_tmp test-gaming-flatpak)"
trap 'cleanup_dirs "$TMP"' EXIT

# Deterministic env: no stray --full/--yes/--priv leakage from the harness
unset XMLG_ASSUME_YES XMLG_FULL XMLG_PRIV

# ── hermetic fakes ──────────────────────────────────────────────────────────
# Bin dirs control which commands exist (each case PATH = <bin>:<sys-bin>):
#   FAKE_BIN            everything present (native heroic + flatpak + doas+sudo)
#   FAKE_NO_HEROIC_BIN  no `heroic`   -> "no native install"
#   FAKE_NO_FLATPAK_BIN no `flatpak`  -> "no flatpak at all"
#   FAKE_FAIL_BIN       failing doas  -> priv() failure propagation
#   FAKE_SYS            symlinks to the REAL grep the lib may invoke
FAKE_BIN="$TMP/bin"
FAKE_NO_HEROIC_BIN="$TMP/bin-noh"
FAKE_NO_FLATPAK_BIN="$TMP/bin-nof"
FAKE_FAIL_BIN="$TMP/bin-fail"
FAKE_SYS="$TMP/sys-bin"

DOAS_LOG="$TMP/doas.log"
SUDO_LOG="$TMP/sudo.log"

# install_fakes <dir> — bake doas/sudo/flatpak/heroic into a bin dir. All
# fakes log to the SAME files. Unquoted heredocs bake the concrete log paths
# in at write time (the fakes run as subprocesses).
# NOTE: fakes use the absolute #!/bin/bash shebang, NOT #!/usr/bin/env bash —
# with a fully replaced PATH, env(1) could not find bash.
install_fakes() {
	local d="$1"
	mkdir -p "$d"
	cat >"$d/doas" <<EOF
#!/bin/bash
echo "doas \$*" >> "$DOAS_LOG"
EOF
	cat >"$d/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >> "$SUDO_LOG"
EOF
	# fake flatpak: `list --app` only contains the Heroic app when
	# FAKE_FLATPAK_HEROIC=1; every other invocation is a silent success.
	cat >"$d/flatpak" <<EOF
#!/bin/bash
if [ "\$1" = "list" ] && [ "\${FAKE_FLATPAK_HEROIC:-0}" = "1" ]; then
	printf 'Heroic\tcom.heroicgameslauncher.hgl\tv2.22.3\tstable\tsystem\n'
fi
exit 0
EOF
	cat >"$d/heroic" <<EOF
#!/bin/bash
exit 0
EOF
	chmod +x "$d"/doas "$d"/sudo "$d"/flatpak "$d"/heroic
}

install_fakes "$FAKE_BIN"
install_fakes "$FAKE_NO_HEROIC_BIN"
rm -f "$FAKE_NO_HEROIC_BIN/heroic"
install_fakes "$FAKE_NO_FLATPAK_BIN"
rm -f "$FAKE_NO_FLATPAK_BIN/flatpak"

# failing doas (exit 1) to prove uninstall propagates priv()'s failure
mkdir -p "$FAKE_FAIL_BIN"
cat >"$FAKE_FAIL_BIN/doas" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$FAKE_FAIL_BIN/doas"

# real tools the lib is allowed to use
mkdir -p "$FAKE_SYS"
ln -sf "$(command -v grep)" "$FAKE_SYS/grep"

# ── source the unit under test (pulls in common.sh for priv/log/ask_no_full)
. "$REPO_ROOT/scripts/lib/common.sh"
. "$REPO_ROOT/scripts/lib/gaming-flatpak.sh"

# ── C1: no native Heroic -> silent no-op even though the Flatpak exists ────
rm -f "$DOAS_LOG" "$SUDO_LOG"
GAMING_RC=0
PATH="$FAKE_NO_HEROIC_BIN:$FAKE_SYS" FAKE_FLATPAK_HEROIC=1 \
	gaming_flatpak_orphan_check >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C1 no native heroic -> rc 0 (no-op)" "0" "$GAMING_RC"
t_assert "C1 no purge attempted" test ! -s "$DOAS_LOG"

# ── C2: native + Flatpak present, assume-yes -> default N keeps it ─────────
rm -f "$DOAS_LOG" "$SUDO_LOG"
GAMING_RC=0
PATH="$FAKE_BIN:$FAKE_SYS" FAKE_FLATPAK_HEROIC=1 XMLG_ASSUME_YES=1 \
	gaming_flatpak_orphan_check >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C2 assume-yes answers the default (N) -> kept, rc 0" "0" "$GAMING_RC"
t_assert "C2 no purge under --yes" test ! -s "$DOAS_LOG"

# ── C3: native installed, Flatpak Heroic NOT installed -> no-op ────────────
rm -f "$DOAS_LOG" "$SUDO_LOG"
GAMING_RC=0
PATH="$FAKE_BIN:$FAKE_SYS" FAKE_FLATPAK_HEROIC=0 \
	gaming_flatpak_orphan_check >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C3 no flatpak heroic -> rc 0 (no-op)" "0" "$GAMING_RC"
t_assert "C3 no purge attempted" test ! -s "$DOAS_LOG"

# ── C4: native + Flatpak present, user answers y -> purge via priv/doas ────
printf 'y\n' >"$TMP/yes"
rm -f "$DOAS_LOG" "$SUDO_LOG"
GAMING_RC=0
PATH="$FAKE_BIN:$FAKE_SYS" FAKE_FLATPAK_HEROIC=1 \
	gaming_flatpak_orphan_check <"$TMP/yes" >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C4 confirmed purge -> rc 0" "0" "$GAMING_RC"
t_assert_eq "C4 purge escalates via doas with --delete-data" \
	"doas flatpak uninstall --delete-data -y com.heroicgameslauncher.hgl" \
	"$(cat "$DOAS_LOG" 2>/dev/null)"
t_assert "C4 routed via doas, not sudo" test ! -s "$SUDO_LOG"

# ── C5: --full does NOT force the purge (ask_no_full discipline) ───────────
rm -f "$DOAS_LOG" "$SUDO_LOG"
GAMING_RC=0
PATH="$FAKE_BIN:$FAKE_SYS" FAKE_FLATPAK_HEROIC=1 XMLG_FULL=1 \
	gaming_flatpak_orphan_check </dev/null >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C5 --full leaves the flatpak (rc 0)" "0" "$GAMING_RC"
t_assert "C5 no purge under --full" test ! -s "$DOAS_LOG"

# ── C6: no flatpak binary at all -> no-op ──────────────────────────────────
rm -f "$DOAS_LOG" "$SUDO_LOG"
GAMING_RC=0
PATH="$FAKE_NO_FLATPAK_BIN:$FAKE_SYS" FAKE_FLATPAK_HEROIC=1 \
	gaming_flatpak_orphan_check >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C6 no flatpak binary -> rc 0 (no-op)" "0" "$GAMING_RC"
t_assert "C6 no purge attempted" test ! -s "$DOAS_LOG"

# ── C7: gaming_flatpak_uninstall propagates priv()'s status ────────────────
rm -f "$DOAS_LOG"
GAMING_RC=0
PATH="$FAKE_BIN:$FAKE_SYS" gaming_flatpak_uninstall >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C7a uninstall success -> rc 0" "0" "$GAMING_RC"
t_assert "C7a doas invoked" test -s "$DOAS_LOG"

rm -f "$DOAS_LOG"
GAMING_RC=0
PATH="$FAKE_FAIL_BIN:$FAKE_SYS" gaming_flatpak_uninstall >/dev/null 2>&1 || GAMING_RC=$?
t_assert_eq "C7b uninstall propagates escalation failure (rc 1)" "1" "$GAMING_RC"

echo
t_summary "unit: gaming-flatpak"
