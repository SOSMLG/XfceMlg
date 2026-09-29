#!/usr/bin/env bash
# tests/unit/test-polkit-guard.sh — unit tests for the single-polkit-agent
# guard (ensure_single_polkit_agent in scripts/lib/common.sh):
#   - masks every foreign polkit auth agent autostart with a user-level
#     Hidden=true override
#   - never masks xfce-polkit (the keeper) nor non-polkit entries
#   - idempotent on re-run; clean no-op with no foreign agents / no dir
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/test-helpers.sh"

TMP="$(make_tmp test-polkit-guard)"
trap 'cleanup_dirs "$TMP"' EXIT

. "$REPO_ROOT/scripts/lib/common.sh"

SYS="$TMP/sys-autostart"
USR="$TMP/usr-autostart"
mkdir -p "$SYS" "$USR"

# fixture: the agents that commonly fight each other on a hand-built box
cat >"$SYS/xfce-polkit.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Xfce PolicyKit Agent
Exec=/usr/lib/x86_64-linux-gnu/xfce4/bin/xfce-polkit
OnlyShowIn=XFCE;
EOF
cat >"$SYS/lxpolkit.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/bin/lxpolkit
EOF
cat >"$SYS/polkit-mate-authentication-agent-1.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/polkit-mate/polkit-mate-authentication-agent-1
EOF
cat >"$SYS/redshift.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Redshift
Exec=/usr/bin/redshift-gtk
EOF

autostart_files() { find "$USR" -maxdepth 1 -type f -name '*.desktop' | sort; }

XMLG_POLKIT_SYS_AUTOSTART="$SYS" XMLG_POLKIT_USER_AUTOSTART="$USR" \
	ensure_single_polkit_agent >/dev/null

# ── foreign agents masked with Hidden=true ────────────────────────────────
t_assert "lxpolkit masked" test -f "$USR/lxpolkit.desktop"
t_assert_grep "lxpolkit mask is Hidden=true" '^Hidden=true' "$USR/lxpolkit.desktop"
t_assert "polkit-mate masked" test -f "$USR/polkit-mate-authentication-agent-1.desktop"
t_assert_grep "polkit-mate mask is Hidden=true" '^Hidden=true' "$USR/polkit-mate-authentication-agent-1.desktop"

# ── keeper and unrelated entries untouched ────────────────────────────────
t_assert "xfce-polkit NOT masked" test ! -f "$USR/xfce-polkit.desktop"
t_assert "redshift untouched" test ! -f "$USR/redshift.desktop"
t_assert "only the 2 masks written" test "$(autostart_files | wc -l)" = "2"

# ── idempotent re-run: same files, no clobbering ──────────────────────────
before="$(autostart_files)"
XMLG_POLKIT_SYS_AUTOSTART="$SYS" XMLG_POLKIT_USER_AUTOSTART="$USR" \
	ensure_single_polkit_agent >/dev/null
t_assert "idempotent (file set unchanged)" test "$before" = "$(autostart_files)"

# ── no foreign agents (only keeper) → no new masks ────────────────────────
SYS2="$TMP/sys2"
mkdir -p "$SYS2"
cp "$SYS/xfce-polkit.desktop" "$SYS2/"
XMLG_POLKIT_SYS_AUTOSTART="$SYS2" XMLG_POLKIT_USER_AUTOSTART="$USR" \
	ensure_single_polkit_agent >/dev/null
t_assert "only keeper present, no new masks" test "$before" = "$(autostart_files)"

# ── missing system dir → clean no-op, exit 0 ──────────────────────────────
XMLG_POLKIT_SYS_AUTOSTART="$TMP/nope" XMLG_POLKIT_USER_AUTOSTART="$USR" \
	ensure_single_polkit_agent >/dev/null
t_assert "missing system dir is a no-op" test "$before" = "$(autostart_files)"

t_summary "polkit-guard"
