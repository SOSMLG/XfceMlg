# devuan-xfce-setup — Project Instructions (for AI coding agents)

Devuan 6 (Excalibur) + XFCE post-install polish toolkit. Binary-compatible
with Debian trixie, but Devuan ships **OpenRC or sysvinit, never systemd**.
Follow these conventions when extending, debugging, or reviewing this repo.

## What this toolkit does

Ten-ish numbered, independently runnable shell scripts (`scripts/01?.sh`
…) that turn a bare Devuan Excalibur XFCE install into a themed, powered-up
desktop: theme engine + palette layer, ThinkPad extras, Power-user commands
(menu/update GUI), update notifier, CLI stack, Firefox ESR hardening,
first-run wizard, dev toolchains, AI agents + VSCodium.

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

## Theme engine (the palette system)

- `scripts/lib/theme-apply.sh` — self-contained engine, sourced by
  `scripts/21-theme-tokyonight.sh`, deployed bins and blend overlay.
- Palettes: `themes/<id>/palette.sh` (hex WITHOUT `#`, lowercase; keys:
  `THEME_*`, `FASTFETCH_COLOR`, `GTK_THEME_NAME`, `XFWM_THEME_NAME`,
  `ALACRITTY_*`). Templates: `themes/_base/tpl/*` use `@TOKEN@`
  placeholders that `theme_set` substitutes via sed.
- Rendering writes alacritty.yml, gtk-3.0/gtk.css (panel accent),
  fastfetch config + `picker.colors` (bg0/bg1/bg3/fg0, `F2` alpha suffix).
  Live xfconf only when a session is present; `DEVX_SKIP_XFCONF=1` for
  headless/ISO.
- Env overrides: `DEVX_CONFIG`, `DEVX_THEMES`, `DEVX_OUT`, `DEVX_HOME`,
  `DEVX_SKIP_XFCONF`, `DEVX_THEME`.
- **Adding a palette** = add `themes/<id>/palette.sh` + mention it in the
  README — the test suite (consistency) enforces both.

## Power-user commands

`scripts/24-power-user.sh` deploys `xfce-menu`, `xfce-update-check`,
`xfce-update-gui`, `xfce-lock`, `xfce-suspend` (+ a cron-based update
notifier). Python widgets (GTK/VTE) live in
`configs/share/devuan-xfce-setup/` and read `picker.colors` for theming.

## Testing (mandatory before commit)

- `make check` — three read-only tiers (see `tests/README`-ish comments in
  `tests/run.sh`): **lint** (bash -n + shellcheck-if-present +
  py_compile), **unit** (sandboxed theme-apply + common.sh tests), and
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
  changelog are committed there; the 13 MB `configs/` is staged with
  `cp -a` at build time, never duplicated in git. `@VERSION@` in the
  control/copyright/changelog templates is substituted from `VERSION`.
- content deb = assets under `/usr/share/devuan-xfce-assets/` when
  installed. No APT repo, no publish.
- Prefer additive repo changes that keep `make check` and `make pkg-deb`
  green.

## Blend / ISO

- `blend/devuan-xfce-thinkpad/sync-overlay.sh` regenerates the overlay
  (and its own HOME rendering) via the theme engine
  (`DEVX_SKIP_XFCONF=1 DEVX_OUT=<overlay home>`). The overlay tree is
  derived — never hand-edit it.