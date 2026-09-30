# shellcheck shell=bash
# functions.sh — the xfcemlg utility functions. Split out of aliases.sh so
# that aliases.sh stays a flat list of one-liners; this file holds the
# things that need more than one line of logic.
#
# Everything here is a plain shell function defined in the interactive
# shell — no compiled helper, no background daemon, nothing to install.
# The ones that shell out guard the tool they need, so a function that
# cannot work here says so instead of failing with "command not found".

# ── extract <archive> — unpack by extension, in place ──
extract() {
	[ $# -eq 1 ] || {
		printf 'Usage: extract <archive>\n' >&2
		return 1
	}
	case "$1" in
	*.tar.gz | *.tgz) tar -xzf "$1" ;;
	*.tar.bz2 | *.tbz2) tar -xjf "$1" ;;
	*.tar.xz | *.txz) tar -xJf "$1" ;;
	*.tar.zst | *.tzst) tar --zstd -xf "$1" 2>/dev/null || zstd -dc "$1" | tar -x ;;
	*.tar) tar -xf "$1" ;;
	*.zip) unzip "$1" ;;
	*.7z) 7z x "$1" ;;
	*.rar) unrar x "$1" ;;
	*.gz) gunzip -k "$1" ;;
	*.bz2) bunzip2 -k "$1" ;;
	*.xz) xz -dk "$1" ;;
	*.zst) zstd -d "$1" ;;
	*)
		printf 'extract: no rule for %s\n' "$1" >&2
		return 1
		;;
	esac
}

# ── mkcd <dir> — make a directory and enter it ──
# Chained for one-liners: `mkcd ~/src/new-thing`.
mkcd() {
	[ $# -eq 1 ] || {
		printf 'Usage: mkcd <dir>\n' >&2
		return 1
	}
	mkdir -p -- "$1" && cd -- "$1"
}

# ── cfile <filename> — copy a file to the clipboard, or back ──
# xclip is the clipboard mechanism on a lean XFCE session; xfce4-clipman is
# a clipboard *manager* and does not own the X selection by itself.
cfile() {
	if ! command -v xclip >/dev/null 2>&1; then
		printf 'cfile: xclip is not installed (apt install xclip)\n' >&2
		return 1
	fi
	[ $# -eq 1 ] || {
		printf 'Usage: cfile <filename>   # or: cfile - <text>\n' >&2
		return 1
	}
	if [ "$1" = "-" ]; then
		xclip -selection clipboard
	else
		[ -r "$1" ] || {
			printf 'cfile: cannot read %s\n' "$1" >&2
			return 1
		}
		xclip -selection clipboard -i "$1"
	fi
}

# ── reload — re-read the shell configuration in place ──
# Prefer re-sourcing .bashrc over opening a new terminal: it keeps the
# working directory, the history and the running jobs.
reload() {
	[ -r "$HOME/.bashrc" ] || {
		printf 'reload: no readable ~/.bashrc\n' >&2
		return 1
	}
	# shellcheck source=/dev/null
	source "$HOME/.bashrc" && printf 'reload: done\n'
}

# ── ff <pattern> — find files by name, ignoring .git and the usual noise ──
# Uses fd when present, else find + -prune. Prints one path per line, so it
# composes with xargs: `ff '\.conf$' | xargs -r grep -l foo`.
ff() {
	[ $# -eq 1 ] || {
		printf "Usage: ff <name-pattern>\n" >&2
		return 1
	}
	if command -v fd >/dev/null 2>&1; then
		fd --type f --hidden --exclude .git -- "$1"
	elif command -v fdfind >/dev/null 2>&1; then
		fdfind --type f --hidden --exclude .git -- "$1"
	else
		# No fd: match fd's *substring/regex* semantics rather than
		# find's exact `-name`, or `ff conf` would silently stop finding
		# `keep.conf`. `-path '*/.git' -prune` (not `-name .git`) also
		# excludes nested repositories, and sed drops find's `./`
		# prefix so the output is identical to fd's either way. grep
		# exits 1 on no match, which is the conventional result for a
		# filter and is what this returns.
		find . -path '*/.git' -prune -o -type f -print |
			sed 's|^\./||' |
			grep -E -- "$1"
	fi
}

# ── ports <port> — what is listening, and who owns it ──
# `ss -ltnp` shows the socket table; without a port argument it filters down
# to the ones that are actually listening.
ports() {
	command -v ss >/dev/null 2>&1 || {
		printf 'ports: ss is not installed (apt install iproute2)\n' >&2
		return 1
	}
	if [ $# -eq 1 ]; then
		ss -ltnp "sport = :$1"
	else
		ss -ltnp
	fi
}

# ── json <file|-> — colourised, key-sorted JSON ──
# jq is the only dependency; the argument is passed as-is, so `-` reads
# stdin and a file path is read from disk.
json() {
	[ $# -eq 1 ] || {
		printf 'Usage: json <file|->\n' >&2
		return 1
	}
	if ! command -v jq >/dev/null 2>&1; then
		printf 'json: jq is not installed (apt install jq)\n' >&2
		return 1
	fi
	jq --color-output --sort-keys '.' "$1"
}
