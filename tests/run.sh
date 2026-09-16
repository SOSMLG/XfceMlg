#!/usr/bin/env bash
# tests/run.sh — test harness (ohmydebn-style, three tiers, all read-only).
#
#   tier 1  lint        static checks: bash -n, shellcheck-if-present,
#                       python py_compile
#   tier 2  unit        mocked/sandboxed unit tests (no root, no apt, no X)
#   tier 3  consistency cross-file regression guards (VERSION, palettes,
#                       templates, README, step-script headers)
#   tier 3  apt-checks  read-only apt-cache existence checks on every
#                       package name referenced by scripts/*
#                       (skippable when package lists aren't present)
#
# Usage:
#   ./tests/run.sh                 full suite (all tiers)
#   ./tests/run.sh --tier 2        only tier 2
#   ./tests/run.sh --skip-apt-checks
#   ./tests/run.sh --no-shellcheck
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WANT_TIER=""
SKIP_APT=0
NO_SHELLCHECK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --tier) WANT_TIER="$2"; shift 2 ;;
        --skip-apt-checks) SKIP_APT=1; shift ;;
        --no-shellcheck) NO_SHELLCHECK=1; shift ;;
        -h|--help)
            sed -n '2,21p' "$0"
            exit 0
            ;;
        *) echo "[run.sh] unknown option: $1" >&2; exit 2 ;;
    esac
done

run_tier() {
    local label="$1" script="$2"
    echo "--- $label ---"
    bash "$script"
    local rc=$?
    [ "$rc" -eq 0 ] || echo "[run.sh] $label FAILED" >&2
    return "$rc"
}

export DEBTESTS_NO_SHELLCHECK="$NO_SHELLCHECK"

STATUS=0
if [ -z "$WANT_TIER" ] || [ "$WANT_TIER" = "1" ]; then
    run_tier "tier 1: lint" "$SCRIPT_DIR/lint.sh" || STATUS=1
fi
if [ -z "$WANT_TIER" ] || [ "$WANT_TIER" = "2" ]; then
    run_tier "tier 2: unit" "$SCRIPT_DIR/unit/run.sh" || STATUS=1
fi
if [ -z "$WANT_TIER" ] || [ "$WANT_TIER" = "3" ]; then
    run_tier "tier 3: consistency" "$SCRIPT_DIR/consistency.sh" || STATUS=1
    if [ "$SKIP_APT" -eq 0 ]; then
        run_tier "tier 3: apt-checks" "$SCRIPT_DIR/apt-checks.sh" || STATUS=1
    else
        echo "--- tier 3: apt-checks (skipped) ---"
    fi
fi

echo
if [ "$STATUS" -eq 0 ]; then
    echo "== devuan-xfce-setup tests: ALL GREEN =="
else
    echo "== devuan-xfce-setup tests: FAILURES ABOVE ==" >&2
fi
exit "$STATUS"