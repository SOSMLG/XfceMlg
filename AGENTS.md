# xfcemlg — Project Instructions (for AI coding agents)

Devuan 6 (Excalibur) + XFCE post-install polish toolkit. Binary-compatible
with Debian trixie, but Devuan ships **OpenRC or sysvinit, never systemd**.
Follow these conventions when extending, debugging, or reviewing this repo.

## What this toolkit does

Ten-ish numbered, independently runnable shell scripts (`scripts/01?.sh`
…) that turn a bare Devuan Excalibur XFCE install into a themed, powered-up
desktop: Darkmatter theme (fetched at install, engine-free), ThinkPad extras, Power-user
commands (menu/update GUI), update notifier, CLI stack + xfcemlg shell config, Firefox ESR
hardening, first-run wizard, dev toolchains, AI agents + VSCodium.

`run.sh` is the ordered runner (discovers `scripts/??-*.sh`, groups into
phases by leading digit, reads per-script `# XMLG_DESC:` / `#
XMLG_DEFAULT:` headers). `install.sh` wraps it as `--full --verify`.
Every step is idempotent and re-runnable.

## Init system: OpenRC/sysvinit — never systemd

- **No `systemctl` / `journalctl` / unit files.** Nothing in this repo calls
  them (must never start).
- Control services via `start_service <svc>` from `scripts/lib/common.sh`
  (it detects the live init: systemd / OpenRC (`rc-update`/`rc-service`) /
  sysvinit (`update-rc.d`/`service`)).
- Logs live under `/var/log/` (rsyslog/syslogd), not a journal.

## Root escalation: `priv()`, never bare sudo

- `priv()` (in `scripts/lib/common.sh`): prefers **doas**, falls back to
  **sudo**. Override with `XMLG_PRIV=doas|sudo`. Flags pass through
  (`priv -n true`, `priv apt-get install -y foo`).
- **Never write bare `sudo`/`doas` in new code.**
- Every apt action checks `is_installed` / `command_exists` first; nothing
  is force-purged blindly. `apt_update()` refreshes lists exactly once per
  run (`XMLG_SKIP_APT_UPDATE=1` flip).

## Package management

- `apt`/`apt-get`/`dpkg` only — never pacman/dnf/nix.
- Check install state with `is_installed <pkg>`, not assumptions.
- Packages are added via `priv apt-get install -y ...` or
  `install_pkgs "label" pkg1 pkg2 ...`. Both are parsed by the test suite's
  apt-checks (see Testing below).
- Devuan Excalibur tracks Debian trixie. `contrib`/`non-free` components are
  added by the toolkit itself (`scripts/lib/common.sh` `ensure_repo_component`,
  `11-backports.sh`) — so a bare sources.list may legitimately miss
  `libdvd-pkg`, `winetricks`, etc. See `tests/lib/known-miss.list`.

## Theme (Darkmatter — fetched at install, engine-free, fixed)

- The look is **fixed**, not swappable. There is **no palette engine** and no
  `themes/<id>/palette.sh` / `theme-apply.sh` / `xfce-theme-set|list`
  anything — those were removed in 0.6.0. Do not reintroduce them.
- The Darkmatter GTK3/GTK4 + xfwm4 theme and the Zafiro icons are **not
  bundled in git** (that was ~29 MB of payload). `scripts/lib/darkmatter-fetch.sh`
  fetches them at install time from `stevedylandev/darkmatter-linux` (root
  `gtk-3.0`/`gtk-4.0`/`assets` + `xfwm4/Darkmatter{,-hdpi,-xhdpi}/xfwm4`)
  and `zayronxio/Zafiro-icons` (`Dark/` dir), then auto-tweaks:
  red-accent remap `#e78a53`→`#e75353` (text + PNG), per-variant
  `index.theme` (`IconTheme=Zafiro-icons-Dark`), `Dark/`→`Zafiro-icons-Dark`
  rename + `apps/scalable` + `previews/` trim.
    Fetch backends: codeload tarballs at **immutable commit SHAs**, never
    `refs/heads/...` — darkmatter-linux `822d163c` (2026-08-22) and
    Zafiro-icons `5c7f38ca`. A branch ref is a moving target that either
    changes the theme under the user silently or trips the sha256 and fails
    the install outright, and those two failure modes look alike. The sha256
    is a second layer (`DM_THEME_SHA256` / `DM_ICONS_SHA256`, env overridable;
    `DM_SKIP_FETCH=1` reuses whatever `~/.cache/xfcemlg/` already holds).
    Consistency guard C18 keeps each URL and its recorded hash from drifting
    apart, which is the failure that would break a fresh install.
- `scripts/21-theme.sh` deploys the assembled variants to `/usr/share/themes/`
  (purging stale `Darkmatter*` and the old Tokyo Night themes first), writes
  the native `~/.config/alacritty/alacritty.toml`, seeds the panel + the
  built-in xfwm4 compositor, deploys `configs/wallpapers/darkmatter/` to
  `/usr/share/backgrounds/xfce/devuan-darkmatter/`, and writes the static
  `~/.config/xfcemlg/picker.colors` (bg0/bg1/bg3/fg0).
- Palette: near-black `#121113` (`bg`/`dark`), `#1c1b1d` base, red accent
  `#e75353` (upstream orange `#e78a53` was remapped across all CSS + PNGs),
  teal `#5f8787`, cream `#fbcb97`, fg `#ffffff`.
- Icons: **Zafiro-icons-Dark** (fetched, trimmed). `22-theme-boot.sh` and
  `verifySetup.sh` assume the `Darkmatter` / `Zafiro-icons-Dark` /
  `devuan-darkmatter` names — keep them in sync if you rename anything.
- `scripts/22-theme-boot.sh` themes Plymouth/GRUB/LightDM to match
  (near-black + red; see `configs/lightdm/gtk.css`).

## Power-user commands

`scripts/24-power-user.sh` deploys `xfce-menu`, `xfce-update-check`,
`xfce-update-gui`, `xfce-lock`, `xfce-suspend`, `xfce-record`,
`xfce-scratch` (+ a cron-based update notifier), and autostarts the
`xfce-battery-warn` / `xfce-temp-warn` daemons (dunst warnings, each
flock-guarded and env-overridable for headless tests). Python widgets
(GTK/VTE) live in `configs/share/xfcemlg/` and read
`picker.colors` for theming.

## Testing (mandatory before commit)

- `make check` — three read-only tiers (see `tests/README`-ish comments in
  `tests/run.sh`): **lint** (bash -n + shellcheck-if-present +
  py_compile), **unit** (sandboxed Darkmatter fetch/tweak pipeline + common.sh
  tests), and **consistency + apt-checks** (cross-file guards; package-existence
  vs the local apt cache via one bulk `apt-cache dumpavail`).
- `make release-preflight` — the version gate (lint + unit + consistency +
  VERSION/RELEASE.md agreement) used before tagging.
- After adding a `scripts/##-*.sh`: it must carry `# XMLG_DESC:` and
  `# XMLG_DEFAULT: Y|N` headers, source `scripts/lib/common.sh`, have a
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
  `build/xfcemlg-assets_$(cat VERSION)_all.deb`. `make check-deb`
  runs `dpkg-deb --info/--contents` and lintian (no errors expected).
- The package tree lives in `packages/xfcemlg-assets/` — only the
  DEBIAN metadata (control/postinst) and `usr/share/doc/` copyright +
  changelog are committed there; the full `configs/` payload (~7 MB:
  wallpapers, power-user bins, agent skill, Firefox policy, vesktop/vscodium
  themes; the Darkmatter themes + Zafiro icons are fetched at install time,
  not shipped in the deb) is staged with
  `cp -a` at build time, never duplicated in git. `@VERSION@` in the
  control/copyright/changelog templates is substituted from `VERSION`.
- content deb = assets under `/usr/share/xfcemlg-assets/` when
  installed. No APT repo, no publish.
- Prefer additive repo changes that keep `make check` and `make pkg-deb`
  green.

## Blend / ISO

- `blend/xfcemlg-thinkpad/sync-overlay.sh` regenerates the overlay
  (and its own HOME rendering) by copying the `configs/` assets
  (wallpapers, alacritty.toml, panel seed and dunst/vesktop/vscodium configs
  — the Darkmatter themes/icons are fetched at install time by
  `scripts/lib/darkmatter-fetch.sh`, not copied from a bundle), with
  `XMLG_SKIP_XFCONF=1`. The overlay tree is derived — never hand-edit it.