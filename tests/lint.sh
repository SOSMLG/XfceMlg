#!/usr/bin/env bash
# tests/lint.sh — tier 1: syntax + static checks (all read-only, no root).
#
# 1. bash -n  — every .sh file + every configs/bin/* wrapper
# 2. shellcheck -x -S warning — if present (skippable via DEBTESTS_NO_SHELLCHECK)
# 3. python3 py_compile — configs/share/devuan-xfce-setup/*.py
#    (__pycache__ cleaned up after)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

. "$SCRIPT_DIR/lib/test-helpers.sh"

BAD=0

# ── 1. bash -n (syntax) ─────────────────────────────────────────────────────
echo "  [lint] bash -n ..."

# Every .sh file in the repo (prune live-sdk/.git and overlay rootfs dirs)
mapfile -t SH_FILES < <(find . \
    \( -path './live-sdk' -o -path './.git' -o -path './blend/*/excalibur/rootfs-overlay' \) \
    -prune -o -type f -name '*.sh' -print \
    | sort)

for f in "${SH_FILES[@]}"; do
    t_assert "bash -n $f" bash -n "$f"
done

# configs/bin/* bash wrappers (shebang-prefixed, no .sh suffix)
if [ -d configs/bin ]; then
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        # only lint files whose shebang is bash
        head -1 "$f" 2>/dev/null | grep -qE '^#!.*(ba)?sh$' || continue
        t_assert "bash -n $f" bash -n "$f"
    done < <(find configs/bin -maxdepth 1 -type f | sort)
fi

# blend overlay scripts
find blend \( -path '*/excalibur/rootfs-overlay' \) -prune \
    -o -type f -name '*.sh' -print 2>/dev/null | sort | while read -r f; do
    t_assert "bash -n $f" bash -n "$f"
done

# deb maintainer scripts
find packages -name 'postinst' -o -name 'prerm' -o -name 'postrm' 2>/dev/null \
    | sort | while read -r f; do
    t_assert "bash -n $f" bash -n "$f"
done

# ── 2. shellcheck ────────────────────────────────────────────────────────────
SKIP_SC="${DEBTESTS_NO_SHELLCHECK:-0}"
if [ "$SKIP_SC" -eq 1 ] || ! command -v shellcheck >/dev/null 2>&1; then
    if [ "$SKIP_SC" -eq 1 ]; then
        echo "  [lint] shellcheck skipped (--no-shellcheck)"
    else
        echo "  [lint] shellcheck not installed, skipped (run: apt-get install shellcheck)"
    fi
else
    echo "  [lint] shellcheck ..."
    SC_TARGETS=()
    # step scripts + lib
    while IFS= read -r f; do SC_TARGETS+=("$f"); done \
        < <(find scripts -type f \( -name '*.sh' \) | sort)
    # configs/bin
    while IFS= read -r f; do
        head -1 "$f" 2>/dev/null | grep -qE '^#!.*(ba)?sh$' && SC_TARGETS+=("$f")
    done < <(find configs/bin -maxdepth 1 -type f 2>/dev/null | sort)
    # overlay (pruned rootfs-overlay)
    while IFS= read -r f; do SC_TARGETS+=("$f"); done \
        < <(find blend \( -path '*/excalibur/rootfs-overlay' \) -prune \
            -o -type f -name '*.sh' -print 2>/dev/null | sort)
    # packages DEBIAN maintainer scripts
    while IFS= read -r f; do SC_TARGETS+=("$f"); done \
        < <(find packages -name 'postinst' -o -name 'prerm' -o -name 'postrm' 2>/dev/null | sort)

    if [ "${#SC_TARGETS[@]}" -gt 0 ]; then
        t_assert "shellcheck -x -S warning" shellcheck -x -S warning "${SC_TARGETS[@]}"
    fi
fi

# ── 3. python py_compile ─────────────────────────────────────────────────────
PY_TARGETS="$(find configs/share -name '*.py' 2>/dev/null | sort)"
if [ -n "$PY_TARGETS" ]; then
    echo "  [lint] py_compile ..."
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        t_assert "py_compile $f" python3 -m py_compile "$f"
    done <<< "$PY_TARGETS"
fi
# clean up __pycache__ dirs under configs/
find configs -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

echo
t_summary "lint"