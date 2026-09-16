# devuan-xfce-setup — Project Instructions (for AI coding agents)

Devuan 6 (Excalibur) + XFCE post-install polish toolkit. Binary-compatible
with Debian trixie, but Devuan ships **OpenRC or sysvinit, never systemd**.
Follow these conventions when extending, debugging, or reviewing this repo.

## What this toolkit does

Ten-ish numbered, independently runnable shell scripts (`scripts/01?.sh`
…) that turn a bare Devuan Excalibur XFCE install into a themed, powered-up
desktop: Darkmatter theme (bundled, engine-free), ThinkPad extras, Power-user
commands (menu/update GUI), update notifier, CLI stack, Firefox ESR
hardening, first-run wizard, dev toolchains, AI agents + VSCodium.

`run.sh` is the ordered runner (discovers `scripts/??-*.sh`, groups into
phases by leading digit, reads per-script `# DEBSWAY_DESC:` / `#
DEBSWAY_DEFAULT:` headers). `install.sh` wraps it as `--full --verify`.
Every step is idempotent and re-runnable.

## Init system: OpenRC/sysvinit — never systemd

- **No `systemctl` / `journalctl` / unit files.** Nothing in this repo calls
  them (must never start).
- Control services via `service_enable_now` / `service_start` /
  `service_restart` from `scripts/lib/common.sh` (they wrap `rc-service`,
  falling back to sysvinit `service`).
- Logs live under `/var/log/` (rsyslog/syslogd), not a journal.

## Root escalation: `priv()`, never bare sudo

- `priv()` (in `scripts/lib/common.sh`): prefers **doas**, falls back to
  **sudo**. Override with `DEBSWAY_PRIV=doas|sudo`. Flags pass through
  (`priv -n true`, `priv apt-get install -y foo`).
- **Never write bare `sudo`/`doas` in new code.**
- Every apt action checks `is_installed` / `command_exists` first; nothing
  is force-purged blindly. `apt_update()` refreshes lists exactly once per
  run (`DEBSWAY_SKIP_APT_UPDATE=1` flip).

## Package management

- `apt`/`apt-get`/`dpkg` only — never pacman/dnf/nix.
- Check install state with `is_installed <pkg>`, not assumptions.
- Packages are added via `priv apt-get install -y ...` or
  `install_pkgs "label" pkg1 pkg2 ...`. Both are parsed by the test suite's
  apt-checks (see Testing below).
- Devuan Excalibur tracks Debian trixie. `contrib`/`non-free` components are
  added by the toolkit itself (`scripts/lib/common.sh` `add_sources`,
  `11-backports.sh`) — so a bare sources.list may legitimately miss
  `libdvd-pkg`, `winetricks`, etc. See `tests/lib/known-miss.list`.

## Theme (Darkmatter — bundled, engine-free, fixed)

- The look is **fixed**, not swappable. There is **no palette engine** and no
  `themes/<id>/palette.sh` / `theme-apply.sh` / `xfce-theme-set|list`
  anything — those were removed in 0.6.0. Do not reintroduce them.
- `configs/themes/{Darkmatter,Darkmatter-hdpi,Darkmatter-xhdpi}` is the
  bundled GTK3/GTK4 + xfwm4 theme (`gtk-3.0`, `gtk-4.0`, `xfwm4`, `assets`,
  `index.theme`); `scripts/21-theme.sh` deploys it to `/usr/share/themes/`,
  purges the old Tokyo Night themes, writes the native
  `~/.config/alacritty/alacritty.toml`, seeds the panel + picom, deploys
  `configs/wallpapers/darkmatter/` to
  `/usr/share/backgrounds/xfce/devuan-darkmatter/`, and writes the static
  `~/.config/devuan-xfce-setup/picker.colors` (bg0/bg1/bg3/fg0).
- Palette: near-black `#121113` (`bg`/`dark`), `#1c1b1d` base, red accent
  `#e75353` (upstream orange `#e78a53` was remapped across all CSS + PNGs),
  teal `#5f8787`, cream `#fbcb97`, fg `#ffffff`.
- Icons: bundled **Zafiro-icons-Dark** in `configs/icons/` (PNG variant only
  — the SVG `apps/scalable` tree is intentionally trimmed). `22-theme-boot.sh`
  and `verifySetup.sh` assume the `Darkmatter` / `Zafiro-icons-Dark` /
  `devuan-darkmatter` names — keep them in sync if you rename anything.
- `scripts/22-theme-boot.sh` themes Plymouth/GRUB/LightDM to match
  (near-black + red; see `configs/lightdm/gtk.css`).

## Power-user commands

`scripts/24-power-user.sh` deploys `xfce-menu`, `xfce-update-check`,
`xfce-update-gui`, `xfce-lock`, `xfce-suspend` (+ a cron-based update
notifier). Python widgets (GTK/VTE) live in
`configs/share/devuan-xfce-setup/` and read `picker.colors` for theming.

## Testing (mandatory before commit)

- `make check` — three read-only tiers (see `tests/README`-ish comments in
  `tests/run.sh`): **lint** (bash -n + shellcheck-if-present +
  py_compile), **unit** (sandboxed Darkmatter-bundle + common.sh tests), and
  **consistency + apt-checks** (cross-file guards; package-existence vs the
  local apt cache via one bulk `apt-cache dumpavail`).
- `make release-preflight` — the version gate (lint + unit + consistency +
  VERSION/RELEASE.md agreement) used before tagging.
- After adding a `scripts/##-*.sh`: it must carry `# DEBSWAY_DESC:` and
  `# DEBSWAY_DEFAULT: Y|N` headers, source `scripts/lib/common.sh`, have a
  README row, and pass `make check`.

## Versioning / releases

- `VERSION` (semver, no `v` prefix) and the **latest** `## x.y.z —` heading
  in `RELEASE.md` must agree — `make release-preflight` enforces it.
- Tag with: `git tag -a "v$(cat VERSION)" -m "v$(cat VERSION)"`.
- Generated content is gitignored: `/live-sdk/`, `/build/`, `/dist/`,
  `*.iso`, `*.img`, `blend/*/excalibur/rootfs-overlay/`, `__pycache__/`.
  Never `git add` from those trees.

## Packaging (content deb)

- `make pkg-deb` builds a single data-only `.deb` from the repo tree:
  `build/devuan-xfce-assets_$(cat VERSION)_all.deb`. `make check-deb`
  runs `dpkg-deb --info/--contents` and lintian (no errors expected).
- The package tree lives in `packages/devuan-xfce-assets/` — only the
  DEBIAN metadata (control/postinst) and `usr/share/doc/` copyright +
  changelog are committed there; the full `configs/` payload (~36 MB, incl.
  the Darkmatter theme, Zafiro icons and wallpapers) is staged with
  `cp -a` at build time, never duplicated in git. `@VERSION@` in the
  control/copyright/changelog templates is substituted from `VERSION`.
- content deb = assets under `/usr/share/devuan-xfce-assets/` when
  installed. No APT repo, no publish.
- Prefer additive repo changes that keep `make check` and `make pkg-deb`
  green.

## Blend / ISO

- `blend/devuan-xfce-thinkpad/sync-overlay.sh` regenerates the overlay
  (and its own HOME rendering) by copying the bundled `configs/` assets
  (Darkmatter theme/icons/wallpapers, alacritty.toml and panel seed as
  written by `21-theme.sh`, with `DEVX_SKIP_XFCONF=1`). The overlay tree is
  derived — never hand-edit it.