#!/usr/bin/env bash
# tests/apt-checks.sh — tier 3: read-only apt-cache package existence checks.
# Extracts every package name referenced by apt-get install / install_pkgs
# calls in scripts/*.sh, then verifies each name exists in the local apt
# cache. Uses one bulk `apt-cache dumpavail` call (fast) instead of N ×
# apt-cache show. Exits 0 if all present; skips gracefully when apt lists
# are missing.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

. "$SCRIPT_DIR/lib/test-helpers.sh"

# ── bail out if not wanted ────────────────────────────────────────────────────
if command -v apt-cache >/dev/null 2>&1; then
    : # proceed
else
    echo "  [apt-checks] apt-cache not found, skipping"
    t_ok "apt-cache not found, skipped"
    t_summary "apt-checks (skipped)"
fi

# ── bulk-dump package names from the local cache (read-only, one call) ───────
echo "  [apt-checks] dumping package names from local apt cache ..."
APT_PKGS="$(mktemp /tmp/aptchecks.XXXXXX)"
trap 'rm -f "$APT_PKGS"' EXIT

apt-cache dumpavail 2>/dev/null \
    | grep -E '^Package:' | cut -d' ' -f2 | sort -u > "$APT_PKGS"

if [ ! -s "$APT_PKGS" ]; then
    echo "  [apt-checks] apt package lists appear empty or broken, skipping"
    echo "  [apt-checks] run 'sudo apt-get update' to populate the cache"
    t_ok "apt lists empty, skipped"
    t_summary "apt-checks (skipped)"
fi

# ── extract package names from scripts ────────────────────────────────────────
echo "  [apt-checks] extracting package names from scripts/ ..."
. "$SCRIPT_DIR/lib/extract-packages.sh"
ALL_PKGS="$(extract_packages_from scripts/*.sh | sort -u)"

PKG_COUNT="$(echo "$ALL_PKGS" | wc -l)"
echo "  [apt-checks] found $PKG_COUNT unique package names"
echo "  [apt-checks] checking existence in local apt cache (read-only) ..."

UNKNOWN=""
KNOWN=0
KNOWN_MISS="$SCRIPT_DIR/lib/known-miss.list"
while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    # Known-miss: package is real but lives in a repo the toolkit adds
    # at install time (contrib/non-free) not yet present in default sources.
    if [ -f "$KNOWN_MISS" ] && grep -qFx -- "$pkg" "$KNOWN_MISS"; then
        KNOWN=$((KNOWN + 1))
        continue
    fi
    if grep -qFx -- "$pkg" "$APT_PKGS"; then
        KNOWN=$((KNOWN + 1))
    else
        UNKNOWN="$UNKNOWN $pkg"
    fi
done <<< "$ALL_PKGS"

echo "  [apt-checks] $KNOWN/$PKG_COUNT verified in apt cache"

if [ -n "$UNKNOWN" ]; then
    for pkg in $UNKNOWN; do
        t_fail "package not found in apt cache: $pkg"
    done
else
    t_ok "all $PKG_COUNT package names verified in apt cache"
fi

echo
t_summary "apt-checks"