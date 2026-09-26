---
description: Scaffold a new numbered toolkit step scripts/NN-name.sh with the required headers, common.sh source and a README row.
agent: build
---

Scaffold a new toolkit step. Use the argument as the step name — e.g.
`new-step 47-tiling-wm` — and derive the number + name from it (NN must be a
free two-digit slot in `scripts/`, grouped in the right phase: 1x core, 2x
desktop, 3x apps, 4x optional, 5x utils).

Create `scripts/NN-name.sh` that:

- starts with the two mandatory headers, in this exact shape:
  `# DEBSWAY_DESC: <one-line description>` and `# DEBSWAY_DEFAULT: Y|N` (follow
  the group convention — most steps now default to `Y`)
- uses `#!/usr/bin/env bash` + `set -uo pipefail`, defines
  `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, and sources
  `scripts/lib/common.sh`
- calls `require_not_root`, wraps every package install in
  `install_pkgs "label" pkg...`, every apt status check in `is_installed`,
  every service enable/start in `start_service`, and every privileged call in
  `priv()` — never bare sudo/systemctl
- is idempotent and backs up (`*.bak.$(date +%Y%m%d%H%M%S)`) before any
  destructive config write
- uses `log_head` / `log_info` / `log_ok` / `log_warn` / `ask` / `ask_no_full`

Then add the matching row to the step table in `README.md` following the exact
format of the row above/below it, and run `make check` to confirm the headers
and README parity pass. Report what you created and the make check result.