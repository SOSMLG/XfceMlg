#!/usr/bin/env bash
# tests/unit/test-darkmatter.sh — sandboxed tests of the fetched-at-install
# Darkmatter pipeline (scripts/lib/darkmatter-fetch.sh: build + red-accent
# remap + Zafiro dark trim) plus the engine-free 21/22-theme scripts and the
# curated payloads that remain bundled. No root, no apt, no X, no network.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../lib/test-helpers.sh"

cd "$REPO_ROOT"

# A 1x1 #e78a53 PNG (fixture for the pixel remap test, no ImageMagick needed
# to create it). The remap must CHANGE its bytes and leave a valid PNG.
ORANGE_1x1_PNG="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExUReeKU////4x2vJgAAAABYktHRAH/Ai3eAAAAB3RJTUUH6gkaFw4TSuueawAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAldEVYdGRhdGU6Y3JlYXRlADIwMjYtMDktMjZUMjM6MTQ6MTkrMDA6MDDqcMoYAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI2LTA5LTI2VDIzOjE0OjE5KzAwOjAwmy1ypAAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNi0wOS0yNlQyMzoxNDoxOSswMDowMMw4U3sAAAAASUVORK5CYII="

FETCH_LIB="$REPO_ROOT/scripts/lib/darkmatter-fetch.sh"
t_assert "darkmatter-fetch lib exists" [ -f "$FETCH_LIB" ]
. "$FETCH_LIB"

TMP="$(make_tmp darkmatter-test)"
trap 'cleanup_dirs "$TMP"' EXIT
OUT="$TMP/out"

echo "  [unit] no heavy theme/icon bundles remain in the repo"
t_assert "configs/themes removed" [ ! -e "$REPO_ROOT/configs/themes" ]
t_assert "configs/icons removed" [ ! -e "$REPO_ROOT/configs/icons" ]
t_assert "configs/rofi removed" [ ! -e "$REPO_ROOT/configs/rofi" ]

echo "  [unit] theme build assembles the upstream layout into 3 variants"
SRC="$TMP/theme-src"
mkdir -p "$SRC/gtk-3.0" "$SRC/gtk-4.0" "$SRC/assets" \
	"$SRC/xfwm4/Darkmatter-hdpi/xfwm4" "$SRC/xfwm4/Darkmatter-xhdpi/xfwm4"
cat >"$SRC/index.theme" <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Darkmatter
Comment=fixture
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Darkmatter
IconTheme=Zafiro-icons
ButtonLayout=:minimize,maximize,close
EOF
echo 'button { color: #e78a53; }' >"$SRC/gtk-3.0/gtk.css"
cp "$SRC/gtk-3.0/gtk.css" "$SRC/gtk-4.0/gtk.css"
echo '<svg><path fill="#e78a53"/></svg>' >"$SRC/assets/acc.svg"
printf '%s' "$ORANGE_1x1_PNG" | base64 -d >"$SRC/assets/on.png"
printf '%s' "$ORANGE_1x1_PNG" | base64 -d >"$TMP/orange-before.png"
echo 'themerc-fixture' >"$SRC/xfwm4/themerc"
printf '%s' "$ORANGE_1x1_PNG" | base64 -d >"$SRC/xfwm4/title-1-active.png"
printf 'hdpi marker' >"$SRC/xfwm4/Darkmatter-hdpi/xfwm4/inactive.png"
printf 'xhdpi marker' >"$SRC/xfwm4/Darkmatter-xhdpi/xfwm4/inactive.png"

if dm_build_theme_variants "$SRC" "$OUT/themes" && dm_remap_accent "$OUT/themes"; then
	t_ok
else
	t_fail "dm_build_theme_variants / dm_remap_accent failed"
fi
for V in Darkmatter Darkmatter-hdpi Darkmatter-xhdpi; do
	for piece in index.theme gtk-3.0 gtk-4.0 xfwm4 assets; do
		t_assert "built $V has $piece" [ -e "$OUT/themes/$V/$piece" ]
	done
done
t_assert "base xfwm4 has themerc" [ -f "$OUT/themes/Darkmatter/xfwm4/themerc" ]
t_assert "base xfwm4 does not carry hdpi dir" [ ! -e "$OUT/themes/Darkmatter/xfwm4/Darkmatter-hdpi" ]
t_assert "base xfwm4 has its button asset" [ -f "$OUT/themes/Darkmatter/xfwm4/title-1-active.png" ]
t_assert "hdpi decorations come from xfwm4/Darkmatter-hdpi" [ -f "$OUT/themes/Darkmatter-hdpi/xfwm4/inactive.png" ]
t_assert "xhdpi decorations come from xfwm4/Darkmatter-xhdpi" [ -f "$OUT/themes/Darkmatter-xhdpi/xfwm4/inactive.png" ]

echo "  [unit] index.theme tweak — name per variant + dark icons"
t_assert_grep "base index.theme names the dark icon theme" 'IconTheme=Zafiro-icons-Dark' "$OUT/themes/Darkmatter/index.theme"
t_assert_grep "hdpi index.theme carries the variant name" '^Name=Darkmatter-hdpi' "$OUT/themes/Darkmatter-hdpi/index.theme"
t_assert_grep "xhdpi index.theme carries the variant name" '^Name=Darkmatter-xhdpi' "$OUT/themes/Darkmatter-xhdpi/index.theme"

echo "  [unit] accent remap — orange #e78a53 becomes red #e75353"
t_assert_grep "built gtk css uses the red accent" '#e75353' "$OUT/themes/Darkmatter/gtk-3.0/gtk.css"
t_assert_not_grep "built gtk css has no stale orange" '#e78a53' "$OUT/themes/Darkmatter/gtk-3.0/gtk.css"
t_assert_grep "svg assets remapped too" '#e75353' "$OUT/themes/Darkmatter/assets/acc.svg"
if command_available convert; then
	if [ -f "$TMP/orange-before.png" ] && ! cmp -s "$TMP/orange-before.png" "$OUT/themes/Darkmatter/assets/on.png"; then
		t_ok
	else
		t_fail "PNG pixel bytes did not change after remap"
	fi
	t_assert "remapped png is still a png" bash -c "file '$OUT/themes/Darkmatter/assets/on.png' | grep -q 'PNG image data'"
else
	t_ok # CSS/SVG remap is unconditional; pixel remap is best-effort
fi

echo "  [unit] icon build — Dark/ renamed + heavy subtrees trimmed"
ISRC="$TMP/icon-src"
mkdir -p "$ISRC/Dark/apps/scalable" "$ISRC/Dark/apps/48" "$ISRC/Dark/previews" "$ISRC/Dark/status"
printf '[Icon Theme]\nName=Zafiro-icons-Dark\nInherits=hicolor\n' >"$ISRC/Dark/index.theme"
printf 'scalable svg marker' >"$ISRC/Dark/apps/scalable/app.svg"
printf '48px marker' >"$ISRC/Dark/apps/48/app.png"
printf 'preview marker' >"$ISRC/Dark/previews/banner.png"
printf 'status marker' >"$ISRC/Dark/status/brightness.svg"
if dm_build_icons "$ISRC" "$OUT/icons"; then
	t_ok
else
	t_fail "dm_build_icons failed"
fi
t_assert "icon theme renamed to Zafiro-icons-Dark" [ -f "$OUT/icons/Zafiro-icons-Dark/index.theme" ]
t_assert_grep "built icon index.theme keeps the name" '^Name=Zafiro-icons-Dark' "$OUT/icons/Zafiro-icons-Dark/index.theme"
t_assert "apps/scalable trimmed" [ ! -e "$OUT/icons/Zafiro-icons-Dark/apps/scalable" ]
t_assert "previews trimmed" [ ! -e "$OUT/icons/Zafiro-icons-Dark/previews" ]
t_assert "kept apps/48" [ -f "$OUT/icons/Zafiro-icons-Dark/apps/48/app.png" ]
t_assert "kept status" [ -f "$OUT/icons/Zafiro-icons-Dark/status/brightness.svg" ]

echo "  [unit] wallpapers — curated dark/red set present"
DM_WALLS="$REPO_ROOT/configs/wallpapers/darkmatter"
if [ -d "$DM_WALLS" ]; then
	for wp in black-leaves.jpg andromeda-2.png night-dunes.jpg cozy-red.jpg fog-forest.jpg; do
		t_assert "wallpaper: $wp" [ -f "$DM_WALLS/$wp" ]
	done
else
	t_fail "wallpaper dir missing: $DM_WALLS"
fi

echo "  [unit] 21-theme.sh — engine-free, network-fetched Darkmatter installer"
T21="$REPO_ROOT/scripts/21-theme.sh"
t_assert "21-theme.sh exists" [ -f "$T21" ]
t_assert_not_grep "no engine usage (only cleanup)" 'theme_seed|theme_set[^_]|source.*theme-apply' "$T21"
t_assert_not_grep "no genmon install" 'install_pkgs[^#]*genmon' "$T21"
t_assert_not_grep "no rofi config deploy" 'configs/rofi' "$T21"
t_assert_grep "21 sources the fetch lib" 'darkmatter-fetch.sh' "$T21"
t_assert_grep "21 deploys from the fetch build dir" 'dm-build' "$T21"
# Validate the versioned alacritty seed (configs/) that 21-theme.sh deploys.
ALAC_TOML="$REPO_ROOT/configs/alacritty/alacritty.toml"
t_assert "alacritty seed exists" [ -f "$ALAC_TOML" ]
if grep -q '^\s*background = "#121113"' "$ALAC_TOML"; then
	t_ok
else
	t_fail "alacritty seed lacks the Darkmatter background"
fi
t_assert_grep "alacritty red index matches accent" 'red     = "#e75353"' "$ALAC_TOML"
t_assert_grep "alacritty fg is white" 'foreground = "#ffffff"' "$ALAC_TOML"
t_assert_grep "alacritty toml is the 0.13+ format" '\[colors.primary\]' "$ALAC_TOML"

echo "  [unit] 22-theme-boot.sh — Darkmatter boot theming"
T22="$REPO_ROOT/scripts/22-theme-boot.sh"
t_assert "22-theme-boot.sh exists" [ -f "$T22" ]
t_assert_not_grep "no tokyonight references in 22" 'tokyonight|Tokyonight' "$T22"
t_assert_grep "22 recolors splash to red accent" '#e75353' "$T22"
t_assert_grep "22 uses Darkmatter GTK theme" 'GTK_THEME_NAME="Darkmatter"' "$T22"
t_assert_grep "22 uses devuan-darkmatter wallpaper dir" 'devuan-darkmatter' "$T22"

echo "  [unit] legacy palette must be gone from shipped configs"
if grep -rIl '#e78a53' configs/dunst configs/lightdm 2>/dev/null | grep -q .; then
	t_fail "stale #e78a53 (old orange accent) found in shipped config"
else
	t_ok
fi
t_assert "old engine dir themes/ removed" [ ! -e "$REPO_ROOT/themes" ]
t_assert "old engine lib removed" [ ! -e "$REPO_ROOT/scripts/lib/theme-apply.sh" ]
t_assert "xfce-theme-set removed" [ ! -e "$REPO_ROOT/configs/bin/xfce-theme-set" ]
t_assert "xfce-theme-list removed" [ ! -e "$REPO_ROOT/configs/bin/xfce-theme-list" ]

echo "  [unit] verifySetup matches the new end state"
TV="$REPO_ROOT/scripts/verifySetup.sh"
t_assert_not_grep "verifySetup has no tokyonight checks" 'Tokyonight|devuan-tokyonight' "$TV"
t_assert_grep "verifySetup checks Darkmatter theme" '"/usr/share/themes/Darkmatter"' "$TV"
t_assert_grep "verifySetup checks alacritty.toml" 'alacritty.toml' "$TV"

t_summary "darkmatter fetch/tweak pipeline"
