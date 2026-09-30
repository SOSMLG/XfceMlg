#!/usr/bin/env bash
# zoxide configuration — smarter cd that learns your habits

if command -v zoxide >/dev/null 2>&1; then
    # Provides `z <dir>` to jump and `zi` for an interactive (fzf) picker.
    # Sourced after fzf.bash alphabetically, so `zi` finds fzf on PATH.
    eval "$(zoxide init bash)"
fi
