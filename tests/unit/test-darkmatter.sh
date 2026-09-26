#!/usr/bin/env bash
# tests/unit/test-darkmatter.sh — sandboxed tests of the bundled
# Darkmatter-theme payload (configs/themes, icons, wallpapers, dunst,
# rofi) and the engine-free 21/22-theme scripts. No root, no apt, no X.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../lib/test-helpers.sh"

cd "$REPO_ROOT"

DM_THEMES="$REPO_ROOT/configs/themes"
DM_ICONS="$REPO_ROOT/configs/icons"
DM_WALLS="$REPO_ROOT/configs/wallpapers/darkmatter"

echo "  [unit] Darkmatter theme bundle structure"
if [ -d "$DM_THEMES/Darkmatter" ]; then
    for variant in Darkmatter Darkmatter-hdpi Darkmatter-xhdpi; do
        t_assert "theme dir: $variant" [ -f "$DM_THEMES/$variant/index.theme" ]
        t_assert "theme gtk-3.0: $variant" [ -d "$DM_THEMES/$variant/gtk-3.0" ]
        t_assert "theme gtk-4.0: $variant" [ -d "$DM_THEMES/$variant/gtk-4.0" ]
        t_assert "theme xfwm4: $variant" [ -d "$DM_THEMES/$variant/xfwm4" ]
        t_assert "theme assets: $variant" [ -d "$DM_THEMES/$variant/assets" ]
    done
else
    t_fail "bundled theme dir missing: $DM_THEMES/Darkmatter"
fi

echo "  [unit] Darkmatter accent is the red #e75353 (remapped everywhere)"
t_assert_grep "Darkmatter gtk css uses red accent" '#e75353' \
    "$DM_THEMES/Darkmatter/gtk-3.0/gtk.css"

echo "  [unit] legacy palette must be gone site-wide"
if grep -rIl '#e78a53' \
        "$DM_THEMES" "$DM_ICONS" configs/dunst configs/rofi configs/lightdm \
        scripts/21-theme.sh scripts/22-theme-boot.sh 2>/dev/null | grep -q .; then
    t_fail "stale #e78a53 (old orange accent) found in shipped config"
else
    t_ok
fi
t_assert "old engine dir themes/ removed" [ ! -e "$REPO_ROOT/themes" ]
t_assert "old engine lib removed" [ ! -e "$REPO_ROOT/scripts/lib/theme-apply.sh" ]
t_assert "xfce-theme-set removed" [ ! -e "$REPO_ROOT/configs/bin/xfce-theme-set" ]
t_assert "xfce-theme-list removed" [ ! -e "$REPO_ROOT/configs/bin/xfce-theme-list" ]

echo "  [unit] Zafiro icon theme (dark, PNG variant)"
if [ -d "$DM_ICONS/Zafiro-icons-Dark" ]; then
    t_assert "zafiro index.theme present" [ -f "$DM_ICONS/Zafiro-icons-Dark/index.theme" ]
    t_assert "zafiro has a status dir" [ -d "$DM_ICONS/Zafiro-icons-Dark/status" ]
    t_assert "zafiro has a mimetypes dir" [ -d "$DM_ICONS/Zafiro-icons-Dark/mimetypes" ]
else
    t_fail "bundled icon theme missing: $DM_ICONS/Zafiro-icons-Dark"
fi

echo "  [unit] wallpapers — curated dark/red set present"
if [ -d "$DM_WALLS" ]; then
    for wp in black-leaves.jpg andromeda-2.png night-dunes.jpg cozy-red.jpg fog-forest.jpg; do
        t_assert "wallpaper: $wp" [ -f "$DM_WALLS/$wp" ]
    done
else
    t_fail "wallpaper dir missing: $DM_WALLS"
fi

echo "  [unit] 21-theme.sh — engine-free Darkmatter installer"
T21="$REPO_ROOT/scripts/21-theme.sh"
t_assert "21-theme.sh exists" [ -f "$T21" ]
t_assert_not_grep "no engine usage (only cleanup)" 'theme_seed|theme_set[^_]|source.*theme-apply' "$T21"
t_assert_not_grep "genmon is only purged, never installed" 'install_pkgs[^#]*genmon' "$T21"
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

echo "  [unit] verifySetup matches the new end state"
TV="$REPO_ROOT/scripts/verifySetup.sh"
t_assert_not_grep "verifySetup has no tokyonight checks" 'Tokyonight|devuan-tokyonight' "$TV"
t_assert_grep "verifySetup checks Darkmatter theme" '"/usr/share/themes/Darkmatter"' "$TV"
t_assert_grep "verifySetup checks alacritty.toml" 'alacritty.toml' "$TV"

t_summary "darkmatter bundle"