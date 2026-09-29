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
#
# Two ways this went wrong before, both now pinned by a case:
#
#  1. A help string that *quotes* a command is not a command. Step 53 ended up
#     with
#         log_info "  Run: apt-get install smartmontools   (then re-run ...)"
#     and a naive /apt-get[ ]+install/ match treated that as a real install
#     site, harvesting `re-run`, `this`, `for`, `the` as package names — so
#     apt-checks failed with four nonsense "package not found" errors. An
#     install keyword therefore only counts in *command position*: the token in
#     front of it must be empty or one of the privilege/run wrappers we use.
#
#  2. Quoted prose after a real package list is not a package list. emit()
#     stops at the first quote, so a trailing `"— takes a while"` cannot leak
#     words in either.
#
# Deliberately NOT an install site: `pkg_absent` in verifySetup.sh, which
# asserts a package is *not* installed. Listing those would be backwards.
extract_packages_from() {
	local f
	for f in "$@"; do
		[ -f "$f" ] || continue
		# 1. Join backslash-continuation lines so each logical install
		#    statement is on a single line (POSIX-safe sed loop).
		sed -e ':a' -e '/\\$/ { N; s/\\\n/ /g; ba }' "$f" | awk '
            BEGIN { SQ = sprintf("%c", 39); CUT = "[\"" SQ "]" }
            # Reject a keyword that sits inside a quoted string.
            #
            # Quote *parity* over the text before the keyword is the precise
            # test, and needs no word allowlist. An earlier attempt at one
            # ("the token in front must be priv/sudo/doas") used a regex that
            # permitted a single intervening word, so `if priv apt-get install`
            # — the most common shape in this repo — was rejected and five
            # real packages fell out of the existence check. The thing worth
            # detecting is a string, and unbalanced quotes are what a string
            # is:
            #     log_info "  Run: apt-get install smartmontools"  -> odd, prose
            #     if priv apt-get install -y firefox-esr; then     -> even, code
            function in_string(pre,   i, c, inq, ins) {
                inq = 0; ins = 0
                for (i = 1; i <= length(pre); i++) {
                    c = substr(pre, i, 1)
                    if (c == "\"") inq = !inq
                    else if (c == SQ) ins = !ins
                }
                return inq || ins
            }
            # Emit only real-looking package names, and stop at the first
            # quote so trailing prose cannot be harvested.
            function emit(str,   out, n, i, w) {
                sub(CUT ".*$", "", str)
                n = split(str, out, /[ \t]+/)
                for (i = 1; i <= n; i++) {
                    w = out[i]
                    if (w ~ /^[a-z][a-z0-9+.-]*$/ && length(w) >= 2) print w
                }
            }
            {
                line = $0
                sub(/#.*/, "", line)          # trailing comment
                sub(/[|;&].*$/, "", line)      # stop at shell operators

                # ── install_pkgs "label" PKG... ──────────────────────────
                if (line ~ /install_pkgs[ \t]/) {
                    pre = line
                    sub(/.*install_pkgs[ \t].*$/, "", pre)
                    if (in_string(pre)) next
                    arg = line
                    sub(/.*install_pkgs[ \t]*/, "", arg)
                    # Drop the human label in either quote style, whatever
                    # case it starts with (a label like "apt cache for this
                    # step" would otherwise donate three fake packages).
                    if (match(arg, /^"[^"]*"/) || match(arg, "^" SQ "[^" SQ "]*" SQ)) {
                        arg = substr(arg, RLENGTH + 1)
                    }
                    emit(arg)
                    next
                }

                # ── apt-get / apt install PKG... ─────────────────────────
                if (line ~ /apt(-get)?[ \t]+install[ \t]/) {
                    pre = line
                    sub(/apt(-get)?[ \t]+install[ \t].*$/, "", pre)
                    if (in_string(pre)) next   # keyword is prose, not a command
                    arg = line
                    sub(/.*apt(-get)?[ \t]+install[ \t]*/, "", arg)
                    emit(arg)
                    next
                }

                # ── pkg <name> [critical|optional] ───────────────────────
                # verifySetup.sh asserts these SHOULD be installed, so they
                # are real requirements and belong in the existence check.
                # The old extractor caught some of them only by accident, when
                # the backslash-join pass happened to glue a pkg line onto an
                # install line; that was luck, not coverage.
                if (line ~ /(^|[;&|(])[ \t]*pkg[ \t]+[a-z]/) {
                    arg = line
                    sub(/.*pkg[ \t]+/, "", arg)
                    # Drop the severity word — `optional` is a valid package
                    # name shape, so it would otherwise be checked as one.
                    sub(/[ \t]+(critical|optional)[ \t]*$/, "", arg)
                    emit(arg)
                }
            }
        ' 2>/dev/null
	done
}
