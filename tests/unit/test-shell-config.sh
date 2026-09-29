#!/usr/bin/env bash
# tests/unit/test-shell-config.sh — sandbox tests for 18-shell-config.sh
# (the from-scratch xfcemlg shell config):
#   - the step end-to-end in a scratch HOME (fake doas/sudo, no root, no apt)
#   - deploy idempotency: the .bashrc hook appears exactly once across two runs
#   - interactive shells get aliases + prompt; non-interactive shells get neither
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$SCRIPT_DIR/../lib/test-helpers.sh"

TMP="$(make_tmp test-shell-config)"
trap 'cleanup_dirs "$TMP"' EXIT

# Fake escalators so install_pkgs' priv() succeeds without root/apt.
FAKE_BIN="$TMP/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/doas" <<EOF
#!/usr/bin/env bash
echo "doas \$*" >> "$TMP/priv.log"
EOF
cat >"$FAKE_BIN/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$*" >> "$TMP/priv.log"
EOF
chmod +x "$FAKE_BIN/doas" "$FAKE_BIN/sudo"

# ── run the whole step in the scratch HOME ─────────────────────────────
HOME="$TMP" PATH="$FAKE_BIN:$PATH" XMLG_SKIP_APT_UPDATE=1 \
	bash "$REPO_ROOT/scripts/18-shell-config.sh" >"$TMP/run1.log" 2>&1
RC=$?

t_assert_eq "18-shell-config.sh exits 0 on a clean sandbox" 0 "$RC"
t_assert "payload dir created" [ -d "$TMP/.config/xfcemlg/bash" ]
for f in rc.sh aliases.sh prompt.sh hooks.sh; do
	t_assert "payload $f deployed" [ -s "$TMP/.config/xfcemlg/bash/$f" ]
done
t_assert "bashrc hook present after run 1" grep -qF "# BEGIN xfcemlg-shell" "$TMP/.bashrc"
t_assert "bashrc hook source line correct" \
	grep -qF '[ -r "$HOME/.config/xfcemlg/bash/rc.sh" ] && source "$HOME/.config/xfcemlg/bash/rc.sh"' "$TMP/.bashrc"

# ── idempotency: second run must not duplicate the hook ────────────────
HOME="$TMP" PATH="$FAKE_BIN:$PATH" XMLG_SKIP_APT_UPDATE=1 \
	bash "$REPO_ROOT/scripts/18-shell-config.sh" >"$TMP/run2.log" 2>&1
RC2=$?
t_assert_eq "second run also exits 0" 0 "$RC2"
HITS="$(grep -cF '# BEGIN xfcemlg-shell' "$TMP/.bashrc" 2>/dev/null || echo 0)"
t_assert_eq "bashrc hook occurs exactly once" 1 "$HITS"

# ── interactive shell sees the config ──────────────────────────────────
if HOME="$TMP" bash -ic 'type ll >/dev/null 2>&1 && echo ALIAS_OK' 2>/dev/null |
	grep -q ALIAS_OK; then
	t_ok
else
	t_fail "interactive bash defines ll"
fi
if HOME="$TMP" bash -ic '[[ "$PROMPT_COMMAND" == *__xfc_ps1* ]] && echo PROMPT_OK' 2>/dev/null |
	grep -q PROMPT_OK; then
	t_ok
else
	t_fail "interactive bash has the xfcemlg prompt wired in"
fi

# ── non-interactive shells must be unaffected (rc.sh returns early) ───
NONINT="$(HOME="$TMP" bash -c 'source "$HOME/.config/xfcemlg/bash/rc.sh"; echo NOISE' 2>&1)"
t_assert_eq "non-interactive rc.sh is a silent early return" "NOISE" "$NONINT"

t_summary "shell-config"
