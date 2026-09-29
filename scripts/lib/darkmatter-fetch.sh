#!/usr/bin/env bash
# =======================================================
# darkmatter-fetch.sh — fetch + build + tweak the Darkmatter
# theme and Zafiro icons at INSTALL time (nothing is bundled
# in git — that was ~29 MB of payload this toolkit no longer
# carries).
# -------------------------------------------------------
# Sourced by scripts/21-theme.sh (and by the sandboxed unit
# tests). Pure Bash + curl + tar + sed + optional ImageMagick;
# deliberately has NO common.sh dependency so tests can source
# it in a sandbox without any side effects.
#
# Upstreams (both GPL-3.0):
#   themes: https://github.com/stevedylandev/darkmatter-linux
#           root gtk-3.0 / gtk-4.0 / assets / index.theme plus
#           xfwm4 ← xfwm4/Darkmatter{,hdpi,xhdpi}/xfwm4
#   icons:  https://github.com/zayronxio/Zafiro-icons  (Dark/ dir)
#
# The "tweak"s applied here (what used to be done by hand in 0.6.0):
#   * orange accent #e78a53 -> red #e75353 in EVERY text asset
#     (css/scss/svg) and every PNG pixel (ImageMagick, if present)
#   * per-variant index.theme: Name=<variant>, IconTheme=Zafiro-icons-Dark
#     (upstream's root index.theme only knows "Zafiro-icons")
#   * icons: upstream "Dark/" -> "Zafiro-icons-Dark", drop the heavy
#     apps/scalable SVG subtree (1553 files) + previews/
#
# Env overrides:
#   DM_FETCH_DIR      cache dir                     (~/.cache/xfcemlg)
#   DM_SKIP_FETCH=1   reuse previously fetched sources (offline/dev/tests)
#   DM_THEME_URL      darkmatter-linux tarball URL override
#   DM_ICONS_URL      Zafiro tarball URL override
#   DM_THEME_SHA256   require this sha256 for the theme tarball (empty = skip)
#   DM_ICONS_SHA256   require this sha256 for the icon tarball (empty = skip)
#   DM_KEEP_TARBALL=1 keep the downloaded tarballs (default: cache them)
# =======================================================

# Recorded checksums of the tarballs this toolkit was built against.
#
# The default URLs below are immutable commit SHAs, so these are the checksums
# of a fixed artefact and should not need recomputing — if a fetch ever fails on
# a checksum mismatch with an unmodified env, that is a *tampered or substituted
# download*, not an upstream move, and it should be investigated rather than
# papered over by pasting in the hash the download actually produced. Guard C18
# in tests/consistency.sh enforces that the pairing stays intact.
#
# To move to a different upstream commit on purpose: change the URL, download it
# once, and update the matching default in scripts/21-theme.sh.
#   themes:  b68f6c190e4e71fe57bd4eccd9c4a2ea639c1b56588f9c74d5f1f15a58807eee
#   icons:   58e4b8f312abbc4a8513c813adbbfbc0ae6bb634ad034594ffd7c34378818c38

# ---- fetch ----------------------------------------------------------------

# dm_fetch_tarball <url> <dest> <expected_sha256> [<min_bytes>]
#   Downloads <url> to <dest> and validates it: sane size, valid tar.gz,
#   optional sha256. Prints nothing on success; errors to stderr + returns 1.
dm_fetch_tarball() {
	local url="$1" dest="$2" sha="$3" min_bytes="${4:-100000}"
	local tmp
	tmp="${dest}.part"
	rm -f "$tmp"
	if ! curl -fsSL --connect-timeout 15 --max-time 300 -o "$tmp" "$url"; then
		echo "[darkmatter] download failed: $url" >&2
		rm -f "$tmp"
		return 1
	fi
	local size
	size="$(stat -c %s "$tmp" 2>/dev/null || echo 0)"
	if [ "$size" -lt "$min_bytes" ]; then
		echo "[darkmatter] suspiciously small download ($size bytes) from $url" >&2
		rm -f "$tmp"
		return 1
	fi
	if ! tar -tzf "$tmp" >/dev/null 2>&1; then
		echo "[darkmatter] '$tmp' is not a valid tar.gz (got an error page?)" >&2
		rm -f "$tmp"
		return 1
	fi
	if [ -n "$sha" ] && ! echo "$sha" | grep -qE '^skip$'; then
		local actual
		actual="$(sha256sum "$tmp" | cut -d' ' -f1)"
		if [ "$actual" != "$sha" ]; then
			echo "[darkmatter] sha256 MISMATCH for $(basename "$tmp")" >&2
			echo "            expected $sha" >&2
			echo "            actual   $actual" >&2
			echo "            update DM_THEME_SHA256 / DM_ICONS_SHA256, or pass via env" >&2
			rm -f "$tmp"
			return 1
		fi
	fi
	mv "$tmp" "$dest"
}

# dm_fetch_themes → echoes the extracted source dir on success (1 on failure).
#   Downloads the darkmatter-linux tarball once into $DM_FETCH_DIR and
#   extracts it into <cache>/darkmatter-linux-src. With DM_SKIP_FETCH=1 it
#   reuses an existing tree without touching the network.
dm_fetch_themes() {
	local cache="${DM_FETCH_DIR:-$HOME/.cache/xfcemlg}"
	# A commit SHA, not refs/heads/main. The branch is a moving target: an
	# upstream push would either change the theme under the user silently or
	# trip the sha256 below and fail the install outright, and the second is
	# indistinguishable from a compromised mirror. A commit makes the fetch
	# reproducible forever. The tarball differs from the branch ref only in
	# its top-level directory name and gzip framing (gzip mtime is zeroed by
	# codeload, so repeated fetches are byte-identical); the extracted tree is
	# the same 616 files. The locate-glob below matches both dir names.
	local url="${DM_THEME_URL:-https://codeload.github.com/stevedylandev/darkmatter-linux/tar.gz/822d163c0e26751440bacf5d9274f4b9b0ec9030}"
	local sha="${DM_THEME_SHA256:-}"
	local src="$cache/darkmatter-linux-src"
	mkdir -p "$cache"
	if [ "${DM_SKIP_FETCH:-0}" = "1" ]; then
		[ -d "$src" ] || {
			echo "[darkmatter] DM_SKIP_FETCH=1 but $src is missing" >&2
			return 1
		}
		echo "$src"
		return 0
	fi
	local tar="$cache/darkmatter-linux.tar.gz"
	if [ ! -f "$tar" ]; then
		dm_fetch_tarball "$url" "$tar" "$sha" 3000000 || return 1
	fi
	rm -rf "$src"
	tar -xzf "$tar" -C "$cache"
	if [ "${DM_KEEP_TARBALL:-0}" != "1" ]; then
		rm -f "$tar"
	fi
	# locate the single top-level dir
	local top
	top="$(find "$cache" -maxdepth 1 -type d -name 'darkmatter-linux-*' | head -1)"
	[ -n "$top" ] || {
		echo "[darkmatter] could not locate extracted theme tree" >&2
		return 1
	}
	mv "$top" "$src"
	echo "$src"
}

# dm_fetch_icons → echoes the extracted source dir on success (1 on failure).
#   Same story for zayronxio/Zafiro-icons (Dark/ variant on master).
dm_fetch_icons() {
	local cache="${DM_FETCH_DIR:-$HOME/.cache/xfcemlg}"
	# Commit SHA, not refs/heads/master — same reasoning as the theme above.
	local url="${DM_ICONS_URL:-https://codeload.github.com/zayronxio/Zafiro-icons/tar.gz/5c7f38ca3b01194104481ffb803111e31851cf5d}"
	local sha="${DM_ICONS_SHA256:-}"
	local src="$cache/zafiro-icons-src"
	mkdir -p "$cache"
	if [ "${DM_SKIP_FETCH:-0}" = "1" ]; then
		[ -d "$src" ] || {
			echo "[darkmatter] DM_SKIP_FETCH=1 but $src is missing" >&2
			return 1
		}
		echo "$src"
		return 0
	fi
	local tar="$cache/zafiro-icons.tar.gz"
	if [ ! -f "$tar" ]; then
		dm_fetch_tarball "$url" "$tar" "$sha" 1000000 || return 1
	fi
	rm -rf "$src"
	tar -xzf "$tar" -C "$cache"
	if [ "${DM_KEEP_TARBALL:-0}" != "1" ]; then
		rm -f "$tar"
	fi
	local top
	top="$(find "$cache" -maxdepth 1 -type d -name 'Zafiro-icons-*' | head -1)"
	[ -n "$top" ] || {
		echo "[darkmatter] could not locate extracted icon tree" >&2
		return 1
	}
	mv "$top" "$src"
	echo "$src"
}

# ---- build + tweak (pure, offline, unit-testable) -------------------------

# dm_build_theme_variants <src> <out>
#   Assembles Darkmatter / Darkmatter-hdpi / Darkmatter-xhdpi from the
#   upstream layout (root gtk-3.0+gtk-4.0+assets shared; xfwm4 decorations
#   under xfwm4/<variant>/xfwm4) and writes a per-variant index.theme that
#   points at Zafiro-icons-Dark. <out> must not exist yet.
dm_build_theme_variants() {
	local src="$1" out="$2"
	[ -d "$src/gtk-3.0" ] || {
		echo "[darkmatter] theme src missing gtk-3.0 at $src" >&2
		return 1
	}
	[ -d "$src/xfwm4" ] || {
		echo "[darkmatter] theme src missing xfwm4 at $src" >&2
		return 1
	}
	mkdir -p "$out"
	for V in Darkmatter Darkmatter-hdpi Darkmatter-xhdpi; do
		local D="$out/$V"
		mkdir -p "$D"
		cp -a "$src/gtk-3.0" "$src/gtk-4.0" "$src/assets" "$D/"
		# per-variant index.theme: correct Name + point at the dark icons
		sed -e 's/^Name=.*$/Name='"$V"'/' \
			-e 's/^IconTheme=.*$/IconTheme=Zafiro-icons-Dark/' \
			"$src/index.theme" >"$D/index.theme"
		if [ "$V" = "Darkmatter" ]; then
			cp -a "$src/xfwm4/." "$D/xfwm4/"
			rm -rf "$D/xfwm4/Darkmatter-hdpi" "$D/xfwm4/Darkmatter-xhdpi"
		else
			[ -d "$src/xfwm4/$V/xfwm4" ] || {
				echo "[darkmatter] missing $src/xfwm4/$V/xfwm4" >&2
				return 1
			}
			cp -a "$src/xfwm4/$V/xfwm4" "$D/xfwm4"
		fi
	done
}

# dm_remap_accent <dir>
#   Turns the upstream orange accent #e78a53 into the Darkmatter red
#   #e75353 everywhere: text files (css/scss/svg/themerc) via sed, PNG
#   pixels via ImageMagick when available (skipped otherwise with a note).
dm_remap_accent() {
	local dir="$1"
	grep -rlI '#e78a53' "$dir" 2>/dev/null | xargs -r sed -i -E 's/#e78a53/#e75353/Ig'
	if command -v convert >/dev/null 2>&1; then
		local f n=0
		while IFS= read -r -d '' f; do
			if convert "$f" -fill '#e75353' -opaque '#e78a53' "$f.r" >/dev/null 2>&1 &&
				[ -s "$f.r" ] && ! cmp -s "$f" "$f.r"; then
				mv "$f.r" "$f"
				n=$((n + 1))
			else
				rm -f "$f.r"
			fi
		done < <(find "$dir" -name '*.png' -print0)
		echo "[darkmatter] recolored $n PNGs to red accent (#e75353)"
	else
		echo "[darkmatter] ImageMagick absent — PNG assets keep upstream colors (CSS/SVG remapped)" >&2
	fi
}

# dm_build_icons <src> <out>
#   Builds out/Zafiro-icons-Dark from the upstream Dark/ dir: renames the
#   folder, drops the heavy apps/scalable SVG subtree and previews/.
dm_build_icons() {
	local src="$1" out="$2"
	[ -d "$src/Dark" ] || {
		echo "[darkmatter] icon src missing Dark/ at $src" >&2
		return 1
	}
	mkdir -p "$out"
	cp -a "$src/Dark" "$out/Zafiro-icons-Dark"
	rm -rf "$out/Zafiro-icons-Dark/apps/scalable" \
		"$out/Zafiro-icons-Dark/previews"
	[ -f "$out/Zafiro-icons-Dark/index.theme" ] || {
		echo "[darkmatter] built icon tree has no index.theme" >&2
		return 1
	}
}
