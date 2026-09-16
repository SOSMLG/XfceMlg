# devuan-xfce-setup — resolution record

A running record of recurring issues and their current resolution, in the
style of the preceding devuan-kde-setup. The primary documentation lives in
README.md (`docs/BUILDING.md` for the live-ISO path). Verified against v0.5.0.

| Area | Current resolution | Main implementation |
|---|---|---|
| Phantom package names | `xfce4-pager` (workspace pager is built into `xfce4-panel`), `mate-disk-usage-analyzer` (dropped upstream) and `xcursor-breeze` (renamed upstream) do not exist in Debian trixie / Devuan Excalibur. Fixed to `baobab` / `breeze-cursor-theme` and removed the pager; the apt-checks tier verifies every referenced package against the real archive so this class of bug fails `make check`. | `scripts/21-theme-tokyonight.sh`, `scripts/33-useful-apps.sh`, `scripts/verifySetup.sh`, `tests/apt-checks.sh` |
| Theme engine source of truth | The active palette lives in `themes/<id>/palette.sh` (bare lowercase hex). Rendering targets alacritty, GTK panel accent, fastfetch, and `picker.colors`. No per-file hand-edits — re-running a palette apply regenerates them from the templates. | `scripts/lib/theme-apply.sh`, `themes/_base/tpl/` |
| GTK session accent vs. palette | The bundled GTK/xfwm4 themes are shared across all three palettes; the per-palette identity (accent hex) is carried by `~/.config/gtk-3.0/gtk.css` rendered by `theme_set`, keeping the WM theme static. | `themes/_base/tpl/gtk-session.css`, `theme_set` |
| picker.colors format | Key/value with `F2` alpha suffix on `bg0`/`bg3` (`bg0=#<hex>F2`), matching the devuan-cinnamon picker contract the Python menu/update GUI read. | `theme_set`, `configs/share/devuan-xfce-setup/*.py` |
| Update notifier without systemd | A cron job (09:00 + 18:00, marker comment) drives `xfce-update-check`; the .desktop action opens `xfce-update-gui` (VTE window running `apt-get full-upgrade`). No systemd timers. | `scripts/24-power-user.sh`, `configs/bin/xfce-update-*` |
| Update check without git remote | The repo has no remote, so `xfce-update-check` checks apt upgrades, not upstream releases. | `configs/bin/xfce-update-check` |
| DEBSWAY_* env consistency | Escalator and install flags share the `DEBSWAY_` namespace with the older devuan-kde-setup for muscle memory; `DEBSWAY_PRIV` forces the escalator. | `scripts/lib/common.sh` |
| Test noise from derived trees | `live-sdk/` (permission-dense bootstrap), `blend/*/excalibur/rootfs-overlay/` and `__pycache__/` are pruned from lint `find` traversal and gitignored. | `tests/lint.sh`, `.gitignore` |
| Known-miss apt packages | `libdvd-pkg`, `winetricks` live in `contrib`, which the toolkit adds at install time but a bare source list lacks — allowlisted rather than failed. | `tests/lib/known-miss.list`, `scripts/lib/common.sh` `add_sources` |
| Long apt-checks wall time | One bulk `apt-cache dumpavail` (≈0.5 s for 69 k packages) plus `grep -Fx` replaces N × `apt-cache show` (~4 s/12 pkgs). | `tests/apt-checks.sh` |
| awk quoting in extractor | Package-label extraction lives in `tests/lib/extract-packages.sh`; apostrophes inside the awk block break bash single-quoting, so wording avoids contractions. | `tests/lib/extract-packages.sh` |
| Shell-capability of awk | The extractor uses POSIX `awk` (`match`/`RLENGTH`/`split`), which both gawk and mawk provide — no gawk-only extensions. | `tests/lib/extract-packages.sh` |
| Deb with grep-friendly lintian | `check-deb` runs `lintian -E` and drops the definitional `N:` notes; the standard library wants a changelog + python3 dep for the embedded widgets, both now shipped. | `Makefile`, `packages/devuan-xfce-assets/` |
| Deb keeps git clone lean | Only DEBIAN metadata + `usr/share/doc/` are committed under `packages/`; the 13 MB `configs/`/`themes/` payload is staged at build time (`make pkg-deb`), so one git checkout serves both the scripts and the package. | `Makefile` `pkg-deb` |