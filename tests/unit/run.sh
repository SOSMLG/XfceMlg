#!/usr/bin/env bash
# tests/unit/run.sh — tier 2 harness: runs all tests/unit/test-*.sh files.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS=0
echo "=== tier 2: unit tests ==="
for t in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$t" ] || continue
    echo
    bash "$t" || STATUS=1
done
exit "$STATUS"