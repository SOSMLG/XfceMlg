# devuan-xfce-setup — Release Notes

Tag a release with: `git tag -a "v$(cat VERSION)" -m "v$(cat VERSION)" && git push --tags`

## 0.6.0 — Darkmatter rice (engine removed), VSCodium key fix, leaner desktop

The theme layer was replaced wholesale. The palette-driven engine is gone:
Darkmatter ships **bundled** (offline, version-pinned) with a red accent, a
matching Zafiro icon theme and a curated dark/red wallpaper set. This release
also hardens the VSCodium repo key path, removes xfce4-terminal /
xfce4-screenshooter / genmon, and flips the "optional" groups and utils to
default-Y so `install.sh` really does give you everything.

### What's New
- **Darkmatter GTK + xfwm4 theme, bundled** in `configs/themes/` (plain,
  hdpi and xhdpi variants; `gtk-3.0`, `gtk-4.0`, `xfwm4`, `assets`,
  `index.theme`), deployed to `/usr/share/themes/` by the new
  `scripts/21-theme.sh`. The old Tokyo Night themes are purged on re-run.
- **Red accent** — the upstream orange `#e78a53` is remapped to `#e75353`
  across every bundled CSS/PNG asset (1548 CSS swaps + 143 429 pixels over
  366 images) and is the accent used by the theme, Dunst, rofi, the greeter
  shim and the widgets.
- **Zafiro icons bundled** — `configs/icons/Zafiro-icons-Dark` (PNG variant,
  17 directories; the SVG `apps/scalable` subtree is trimmed), deployed to
  `/usr/share/icons/` and set as the active icon theme.
- **Curated wallpapers** — `configs/wallpapers/darkmatter/` (5 dark/red
  images) replaces the old numbered set, deployed to
  `/usr/share/backgrounds/xfce/devuan-darkmatter/`; the greeter and GRUB
  backgrounds now come from this same directory.
- **`21-theme.sh`** (renamed from `21-theme-tokyonight.sh`): deploys the
  themes/icons, writes a native **`~/.config/alacritty/alacritty.toml`**
  (0.13+ TOML, no more YAML), seeds the rounded panel + the xfwm4 built-in
  compositor, deploys the
  wallpapers, writes the static `picker.colors`, and removes the old engine
  leftovers (`~/.config/devuan-xfce-setup/lib|themes|current`,
  `xfce-theme-set/list`, per-user `~/.config/gtk-3.0/gtk.css`,
  `alacritty.yml`).
- **`22-theme-boot.sh`** recolors the Plymouth spinner theme to the red
  accent, points GRUB/LightDM at `devuan-darkmatter`, and writes a
  Darkmatter greeter CSS (`#121113` / `#e75353`).
- **Defaults are now Y across the board**: `32`, `43`, `44`, `45`, `46`,
  `50`, `51`, `52` (and the network-manager, libinput, gaming and heavy
  opt-in sub-prompts) — a plain `run.sh --yes` installs the full stack.
- **VSCodium repo key fix** — `40-vscodium.sh` fetches the signing key from
  GitLab (with `repo.vscodium.dev` fallback), validates it with
  `gpg --dearmor` + `gpg --batch --show-keys` (2256 B rsa4096), overwrites
  any stale empty keyring, and refuses to add the repo unless Debian's
  common trusted keyring is already present.
- **Battery maximizer** — `13-hardware.sh` writes
  `/etc/tlp.d/70-maxbattery.conf` (CPU EPP=power + PCIe ASPM=powersave on
  battery, CPU boost kept), appends `pcie_aspm=force` to GRUB, applies a
  battery-first XFCE power profile (blank 3/10 min, suspend after 30 min,
  brightness 55% on battery, lid= suspend on battery / nothing on AC,
  presentation-mode off) in the seed + live xfconf, and enables the
  powertop auto-tune service init-agnostically via `start_service`.
  `verifySetup.sh` checks the battery config, GRUB param and profile.
- **picom is gone** — removed from the theme deps, `configs/picom/` deleted,
  `21-theme.sh` purges any leftover picom package/autostart/config and kills a
  running instance before the WM seed applies. **xfwm4 owns compositing** — the
  `xfwm4.xml` seed enables the built-in compositor (`use_compositing`,
  `vblank_mode auto`) with soft window/popup/dock shadows (`shadow_opacity 40`),
  inactive-window dim (95%), see-through while move/resize (90%) and
  `wrap_workspaces`; the panel's 75% background-alpha now actually renders.
  `verifySetup.sh` checks `use_compositing` + picom absence.

### Removals
- The whole theme engine: `scripts/lib/theme-apply.sh`, the `themes/`
  palette library + `_base/tpl/` templates, and the `configs/bin/xfce-theme-set`
  / `xfce-theme-list` switchers. `21/22` and all docs are engine-free.
- **genmon**: no `xfce4-genmon-plugin`, no `configs/genmon/`, no panel
  widget. `check-apt-updates.sh` stays as a plain reporting helper;
  updates are covered by the power-user checks + cron notifier.
- **Xfce Terminal** and **xfce4-screenshooter** are purged in
  `20-xfce-debloat.sh`; Alacritty is THE terminal and Flameshot owns `Print`
  (with flameshot Super-shortcuts in `23-input-fix.sh`).

### Fixes
- `23-input-fix.sh` reclaims `Print`/`Ctrl+Print`/`Alt+Print` bindings from
  the purged screenshooter and applies the libinput defaults by default.
- `Makefile`: the content deb no longer stages the deleted `themes/` tree
  (the payload now travels inside `configs/`).
- `xfce-menu` dropped its now-dead "Theme List" entry and both widgets'
  fallback palettes are Darkmatter (even without `picker.colors`).

### Docs & tests
- Test suite reworked for the engine-free world: `tests/unit/test-darkmatter.sh`
  replaces `test-theme-apply.sh`; consistency tier guards the Darkmatter
  bundle/icon/remap and the absence of engine references instead of palette
  tokens.
- README, AGENTS.md, `configs/README.md`, `docs/BUILDING.md`,
  `scripts/skills/xfce-setup-SKILL.md` and `verifySetup.sh` all describe the
  Darkmatter end state.

## 0.5.0 — Theme engine + power-user commands + test suite + Makefile + content deb

The full 0.5.0 feature batch: a palette-driven theme engine with three
seeded themes, a set of power-user launcher/update/lock/suspend commands,
an ohmydebn-style read-only test suite with CI-style gates, and a data-only
asset deb so the toolkit's configs/themes ship as a trackable package.

### What's New
- **Theme engine** (`scripts/lib/theme-apply.sh`): palette-driven renderer
  with three commands (`theme_seed`, `theme_set`, `theme_list`,
  `theme_current`) invoked by every palette-applying script. Templates
  under `themes/_base/tpl/` carry `@TOKEN@` placeholders; the renderer
  writes `~/.cache/devuan-xfce-assets/picker.colors` (bg0/bg1/bg3/fg0)
  so the update GUI and menu stay palette-aware. Env overrides
  (`DEVX_SKIP_XFCONF`, `DEVX_THEME`, `DEVX_CONFIG`, etc.) make headless
  and ISO builds possible.
- **Three themes seeded**: `tokyonight` (default), `catppuccin-mocha`,
  `nord`; each palette declared in `themes/<id>/palette.sh` and rendered
  through the shared `_base/tpl/` templates. Test suite enforces palette
  completeness and hex validity.
- **Power-user commands** (`24-power-user.sh`): `xfce-menu` (GTK menu
  launcher), `xfce-update-check` / `xfce-update-gui` (VTE upgrade
  window), `xfce-lock`, `xfce-suspend`; a root-level cron job launches the
  update checker at 09:00/18:00. All read `picker.colors` for theming.
- **Test suite** (`tests/` + `Makefile`): three read-only tiers —
  **lint** (bash -n + shellcheck-if-present + py_compile across scripts,
  configs/bin, blend, package postinsts), **unit** (sandboxed theme-apply
  end-to-end with no X/root/network, and common.sh `priv()` routing via
  fake doas/sudo stubs), **consistency** (cross-file guards including
  palette hex/template mapping, version/RELEASE.md agreement, README step
  parity, .gitignore coverage, 24-power-user deployment checks, and deb
  packaging wiring) + **apt-checks** (one bulk `apt-cache dumpavail` —
  ~1 s total — verifying every package name referenced by the scripts).
  `make check`, `make lint`, `make test`, `make consistency`,
  `make apt-checks`; `make release-preflight` gates the VERSION/RELEASE.md
  agreement.
- **Content deb** (`make pkg-deb`): single data-only
  `devuan-xfce-assets_0.5.0_all.deb` (~6 MB) shipping the full versioned
  asset bundle under `/usr/share/devuan-xfce-assets/` when installed.
  `make check-deb` runs `dpkg-deb` info + lintian with zero errors.
  `packages/devuan-xfce-assets/` holds the committed DEBIAN metadata;
  the 13 MB `configs/` is staged from the repo at build time.
- **AGENTS.md** (repo-root) and **docs/FIXES.md**: project instructions
  for coding agents and a running issue/resolution record.

### Fixes
- `21-theme-tokyonight.sh`: `xcursor-breeze` renamed to the real
  Debian trixie package `breeze-cursor-theme`; `xfce4-pager` removed
  (built into xfce4-panel, not a separate package).
- `33-useful-apps.sh`: `mate-disk-usage-analyzer` replaced by `baobab`.
- `verifySetup.sh`: dropped the phantom `pkg xfce4-pager` line.
- `.gitignore`: now covers `blend/*/excalibur/rootfs-overlay/`,
  `__pycache__/`, and `*.pyc`.
- `README.md`: palette list updated to `tokyonight/catppuccin-mocha/nord`.

Packing check-in of the post-0.3.0 working tree: the default tool swaps
(xfce4-terminal→Alacritty everywhere, xfce4-screenshooter→Flameshot), picom
as the compositor with a full config, auto-detected ThinkPad extras, the
first ISO blend (live-sdk target + build docs), and a battery of is_installed
guards and verifySetup additions. No new phases were added — this is the
baseline the toolkits 0.5.0+ build on.

### What's New
- **Alacritty end-to-end**: lean core (`10-xfce-core.sh`) now ships alacritty
  instead of xfce4-terminal; ButterBash `term`/`screenshot` aliases,
  Super+A OpenCode hotkey, and the Print Screen binds all target
  alacritty/flameshot. verifySetup drops the xfce4-terminal check.
- **Flameshot is the capture default**: `Print` = `flameshot gui`,
  `Super+S`/`Shift+Super+S`/`Alt+Super+S` = gui/full/screen
  (`20-xfce-debloat.sh` flips xfce4-screenshooter to the opt-in; the Print
  binding is retargeted dynamically when swapped).
- **picom as compositor**: added to theme deps, full `picom.conf`
  (square fades, no shadows, inactive dim, fullscreen unredirect), user
  autostart entry, verifySetup coverage.
- **ThinkPad extras**: `13-hardware.sh` auto-detects ThinkPad hardware and
  offers thinkfan (ask_no_full, default N); `12-user-groups.sh` adds the
  `power` group for powertop/thinkfan/brightnessctl.
- **Firefox**: dark-theme prefs (`ui.systemUsesDarkTheme`, content/toolbar
  theme 0) so new profiles match the desktop; `35-first-run.sh` optionally
  deploys a curated importable `~/bookmarks.html`.
- **Genmon disk/network rewrites**: sudo-free (smartctl temperature with a
  `/sys/class/thermal` fallback, device detection for NVMe/mmcblk/SATA) so
  the panel can never hang on a password dialog.
- **Shared service handling**: `13-hardware.sh`/`14-bluetooth.sh` replace
  hand-rolled enable/restart_service helpers with `start_service()` from
  `lib/common.sh` (no stray systemctl calls).
- **Live ISO blend**: `blend/devuan-xfce-thinkpad/` (build-here.sh,
  deploy.sh, sync-overlay.sh, blend lifecycle + excalibur rootfs overlay)
  targeting the Devuan live-sdk, documented in `docs/BUILDING.md`.
  `.gitignore` excludes the 5 GB `live-sdk/` tree and `live-build.log`.

### Fixes
- `15-codecs.sh` no longer aborts when `apt-get update` fails (fails soft,
  continues with cached lists — same as every other step).
- verifySetup additions: font-manager (optional), picom, brightnessctl,
  gufw, gnome-software (optional), update-indicator script, user autostart
  entries, redshift config, and ufw active-state checks.

## 0.3.0 — Tokyo Night rice

Whole-project re-theme from the old Catppuccin/KDE borrowings to a Tokyo Night
XFCE rice (dark `#1a1b26`, accent `#bf616a`), plus a packing/robustness batch.

### What's New
- **Tokyo Night theme end-to-end**: `21-theme-catppuccin.sh` renamed to
  `21-theme-tokyonight.sh`; GTK/xfwm4 relabeled ("Tokyo Night - Bordered"),
  Plymouth + GRUB + LightDM greeter all re-themed, bundled wallpapers +
  genmon wiring, rounded single bottom panel rice, Alacritty becomes the
  default terminal (`helpers.rc` `TerminalEmulator=alacritty`), fastfetch
  draws bundled anime ascii art
- New optional heavy script `46-heavy-optins.sh` (default N): Thunderbird,
  LibreOffice (GTK3-themed with a pre-seeded quiet first-run profile), OBS
  Studio
- Portal + geoclue packaging in `30-desktop-essentials.sh`: installs
  `xdg-desktop-portal-gtk` so Flatpak apps get file dialogs, and writes a
  `[whitelist]` into `/etc/geoclue-2.0/geoclue.conf` so location-aware
  XFCE/GTK apps (Maps, Weather, Firefox, Thunderbird, Zen, Java apps) work
  without a GNOME Location agent
- Debloat additions in `20-xfce-debloat.sh`: orphaned `.desktop` cleanup,
  Xfburn set as the default disc burner

### Fixes
- Dead-code removal (unused helpers/variables stripped)
- `--core` phase now only pulls the core section (previously dragged desktop)
- `/etc/skel` writes now go through `priv()` in `52-skel-export.sh`
- GIMP 2.10 detection now also checks the Flatpak install path in
  `43-photogimp.sh`
- Hardcoded `doas` replaced by the shared `priv()` (doas-first, sudo
  fallback) everywhere it leaked

## 0.2.0 — Butterbian borrowings

Improvements and notes taken from Butterbian-XFCE (live-ISO builder, studied
read-only — BTRFS/systemd/Calamares parts deliberately not ported: this box
is XFS on OpenRC):

### What's New
- Screen locker: `light-locker` in the lean core + `Ctrl+Alt+L` → `xflock4`
  (a shortcut wired to nothing is the exact bug their 0.4.0 fixed)
- Butterbian Super-shortcut set via xfconf (terminal, files, appfinder,
  screenshots, clipman, tiling, workspaces) — create-if-missing, never
  overwrites existing bindings
- Greeter hardening: `user-background = false` (their branded-art fix),
  xft trio, Catppuccin Red login-box CSS shim (`configs/lightdm/gtk.css`,
  lightdm-owned under `/var/lib/lightdm`)
- First-run welcome wizard + wallpaper seeder that only fills monitors with
  no backdrop yet (their 0.4.1 never-overwrite rule)
- Upstream pinning: `XFCE_CURSOR_TAG` (v2.0.0, latest-fallback),
  `XFCE_GTK_REF` override + recorded SHA, `NERD_FONT_TAG` (3.4.0,
  Butterbian-verified), Betterfox BEGIN/END + DIVERGENCE bump markers
- System-wide GTK defaults (`/etc/gtk-3.0/settings.ini`, `/etc/gtk-2.0/gtkrc`)
  so root apps match the user session
- Package gaps closed: taskmanager, greeter-settings, pavucontrol,
  smbclient/cifs-utils, VA-API/VDPAU drivers (never the conflicting
  `intel-media-va-driver-non-free`)

### Fixes
- Unbound `${C}`/`${Z}`/`${W}` color refs aborted scripts under `set -u`
  at their final lines (14/17/21/44) — stripped
- `set -e` + lib `install_pkgs` (returns 1) aborted 9 scripts on any single
  package failure — all scripts now `set -uo pipefail` (graceful degradation)
- `40-vscodium` repo refresh silently skipped under runner's update-skip —
  now a direct `priv apt-get update`

## 0.1.0 — DebianSway parity + XFCE-native

- Numbered `??-*.sh` phases, auto-discovering `run.sh`
  (`--list/--phase/--only/--yes/--full/--no-update/--verify`) + `install.sh`
- Shared `scripts/lib/common.sh` (`priv()` doas-first); all scripts migrated
- Lean minimal-install core (`10-xfce-core.sh`, no tasksel/SLiM) + backports
- XFCE-native: xfce4-terminal replaces Alacritty, VSCodium-only editor,
  stock shooter/notifyd, full Thunar plugin set, LightDM look
- Utils: time-sync, OpenCode agent, maintenance, backup,
  skel-export, `verifySetup.sh`, AI skill file, `configs/` sources

## Unreleased — square panel/picom, VSCodium-only, fully automatic --full

- Picom: square (`corner-radius 0`), snappier fades, inactive-window dim
  (0.95) + terminal opacity rule, fullscreen opacity/unredir excludes,
  animated fork auto-built on `--full` (skipped when already present),
  autostart re-resolves `picom` vs `/usr/local/bin/picom` on re-runs
- Panel: single curated layout (whiskermenu part of it), square `gtk.css`
  (no `opacity:` text-fade — transparency via xfconf `background-alpha`),
  30px / full-width / locked geometry + flat labeled tasklist, all
  `--add` calls idempotent (clipman/genmon/whiskermenu/cpugraph/netload
  never duplicate on re-run)
- Neovim retired: `46-neovim.sh` deleted, `40-vscodium.sh` purges the
  package + script-managed shims and moves `~/.config/nvim` aside;
  `v`/`vv`/`EDITOR` retargeted to `codium`
- Automatic: `ask()` answers Yes under `DEBSWAY_FULL=1` (`install.sh`
  never stops); `ask_no_full()` shields `apt full-upgrade`, backup
  restore, battery cap, PhotoGIMP mismatch, Conky/Plank/graphs

## Unreleased — crash fixes + minimal fancy fastfetch

- Fixed `SCRIPT_DIR: unbound variable` fatal in `16-firefox.sh`,
  `18-butterbash.sh`, `41-dev-essentials.sh` (sourced `lib/common.sh`
  before defining `SCRIPT_DIR` under `set -u`); audited all 29 scripts —
  no other instances. `16` now also ensures `curl` before the Betterfox
  fetch instead of dying on minimal systems
- `19-fastfetch.sh` rewritten minimal: one locally-written fancy
  `config.jsonc` (small logo, red keys, essentials only, JSON-validated),
  Mocha-only btop theme, zero hard exits (fetch failures warn and continue)

## Unreleased — doas keeps asking? fixed

- `ensure_doas_persist()` now NORMALIZES `/etc/doas.conf` instead of
  blindly appending: any stale persist-less `permit <user>` line shadowing
  the cached rule (doas is last-match-wins) is replaced by the single
  canonical `permit persist <user> as root`; deliberate `nopass` rules,
  comments, deny lines and other users are preserved; rejected rewrites
  roll back from backup. Also fixed a real `doas -C` syntax rejection on
  files without a trailing newline
- `require_not_root()` no longer cries wolf when privilege is already
  proven (warm `doas -n`/`sudo -n` timestamp short-circuits the heuristic)
