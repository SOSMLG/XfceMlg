#!/usr/bin/env bash
# extract-packages.sh — shared helpers for pulling the package-name list out
# of the toolkit's scripts. Sourced by tests/apt-checks.sh.
#
# The scripts use two install idioms:
#   * priv apt-get install -y PKG1 PKG2 ...      (real apt lines)
#   * install_pkgs "Description" PKG1 PKG2 ...   (label + args)
# Both may span backslash continuation lines. This extractor joins those
# continuations first, then only keeps tokens that look like real package
# names (lowercase letter, [a-z0-9+.-], >=2 chars) — description labels,
# flags, paths, and shell syntax are all rejected by that shape check.
extract_packages_from() {
    local f
    for f in "$@"; do
        [ -f "$f" ] || continue
        # 1. Join backslash-continuation lines so each logical install
        #    statement is on a single line (POSIX-safe sed loop).
        sed -e ':a' -e '/\\$/ { N; s/\\\n/ /g; ba }' "$f" | awk '
            function emit(str,   out, n, i, w) {
                n = split(str, out, /[[:space:]]+/)
                for (i = 1; i <= n; i++) {
                    w = out[i]
                    if (w ~ /^[a-z][a-z0-9+.-]*$/ && length(w) >= 2) print w
                }
            }
            /install_pkgs/ {
                line = $0
                sub(/#.*/, "", line)
                # stop at shell operators (||, &&, |, ;) so log_warn and
                # log_info strings after || do not leak words as packages
                sub(/[|;&].*$/, "", line)
                sub(/.*install_pkgs[ \t]*/, "", line)
                # strip the first quoted "Description" argument (double-quoted;
                # single-quoted labels start uppercase → emit() already rejects)
                if (match(line, /^"[^"]*"/))  line = substr(line, RLENGTH + 1)
                emit(line)
                next
            }
            /apt(-get)?[ \t]+install[ \t]/ {
                line = $0
                sub(/#.*/, "", line)
                # stop at shell operators before extracting install args
                sub(/[|;&].*$/, "", line)
                sub(/.*apt(-get)?[ \t]+install[ \t]*/, "", line)
                emit(line)
            }
        ' 2>/dev/null
    done
}