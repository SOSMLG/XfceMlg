# System context: Devuan (excalibur) + XFCE

This machine was set up with `devuan-xfce-setup`, a post-install toolkit for a
ThinkPad-class laptop running Devuan 6 (excalibur) — binary-compatible with
Debian 13 (Trixie) — with a lean **XFCE** desktop (X11, floating) on a dark
**Tokyo Night** rice (background `#1a1b26`, accent `#bf616a`). Keep the
following in mind when suggesting commands or diagnosing issues on this
system:

## Package management
- **APT-based** (Devuan/Debian), not Arch/Fedora/Nix. Use `apt`/`apt-get`, never
  `pacman`, `dnf`, or `nix-env`.
- `apt-get install -y <pkg>` for installs, `apt-get purge -y <pkg>` to
  remove, `apt-get autoremove --purge -y` to clean up orphaned deps.
- Minimal installs skip tasksel (`task-xfce-desktop` prefers SLiM) — the
  desktop is a curated `--no-install-recommends` set plus `lightdm`.
- **Backports pinning** lives in `/etc/apt/preferences.d/backports`
  (priority 100). Install newer versions deliberately with
  `doas apt install -t excalibur-backports <pkg>` — never bare `apt upgrade`.
- Flatpak/Flathub is a secondary source. Browser is Firefox **ESR**
  (hardened with Betterfox + enterprise policies). Primary GUI editor is
  **VSCodium** (Geany deliberately not installed).

## Init system & services
- **OpenRC on sysvinit** (Devuan default), PID 1 is `/sbin/init`. There is
  **no `systemctl`/systemd** — enable/start services with
  `rc-update add <svc> default` and `rc-service <svc> start`, list with
  `rc-status`.
- Display manager is **LightDM + lightdm-gtk-greeter** (themed to match the
  Tokyo Night desktop). SLiM and greetd must NOT be enabled alongside it —
  exactly one DM owns the console. Default session: `Xfce Session`.

## Desktop environment
- **XFCE 4.20 on X11** (floating, single bottom panel), not a tiling WM and
  not GNOME/KDE. This changes how you configure things:
  - Settings live in **xfconf** — query/set with
    `xfconf-query -c <channel> -p <property>` (channels: `xfce4-panel`,
    `xfce4-keyboard-shortcuts`, `xfwm4`, `xsettings`, `thunar-volman`,
    `thunar`, `xfce4-notifyd`, `xfce4-power-manager`).
  - Keyboard shortcuts are `/commands/custom/<keysym>` properties in the
    `xfce4-keyboard-shortcuts` channel — there is no sway-style config file
    with `bindsym` lines.
  - Terminal is **Alacritty** (GPU-composited, Tokyo Night colorscheme) and
    is THE default: `x-terminal-emulator` alternative +
    `~/.config/xfce4/helpers.rc` (`TerminalEmulator=alacritty`) — covers
    Thunar "Open Terminal Here", Whisker Menu, and panel launchers.
  - File manager is **Thunar** with the full plugin set (`volman`,
    `archive-plugin` + `xarchiver`, `media-tags`, `vcs`, `gtkhash`,
    `font-manager`) plus `gvfs-backends` (Trash/MTP) and `tumbler`
    thumbnails. Custom actions live in `~/.config/Thunar/uca.xml`.
  - Notifications are **xfce4-notifyd** (stock), screenshots are
    **Flameshot** (`Print` = `flameshot gui`, `Super+S` shortcuts via
    `23-input-fix.sh`), clipboard history is
    **xfce4-clipman**, night-light is **Redshift**, compositor is **picom**
    (fades only; xfwm4's built-in compositing stays off so the two don't
    fight).
  - System info in the terminal/login is **fastfetch** with bundled anime
    ascii art (not neofetch).
  - Panel: one rounded bottom panel with **genmon** widgets — the update
    indicator (hourly `check-apt-updates.sh`), clipman, pulseaudio,
    power-manager, optional cpugraph/netload.
- The Tokyo Night rice is bundled in `configs/themes/`: `Tokyonight-Dark-BL`
  is the active GTK/general theme, `Tokyo Night - Bordered` is the xfwm4
  window theme, with `Graphite-dark` / `Habiboow` / `Aesthetic` as
  alternates. Genmon definitions live in `configs/genmon`, wallpapers in
  `configs/wallpapers`. Plymouth, GRUB and the LightDM greeter are themed to
  match.

## This toolkit's own conventions (for consistency if extending it)
- Scripts live in `scripts/`, numbered `??-*.sh` (1x core, 2x desktop,
  3x apps, 4x optional, 5x utils), each independently runnable
  (`bash scripts/<name>.sh`), all sourcing `scripts/lib/common.sh` for
  shared `ask()`/`log_*`/`install_pkgs`/`priv()` helpers. Metadata comes
  from `# DEBSWAY_DESC:` / `# DEBSWAY_DEFAULT:` headers read by `run.sh`.
- `run.sh` discovers steps automatically (`--list/--phase/--only/--yes/
  --full/--no-update/--verify`); `install.sh` is the fully-unattended
  one-command wrapper. Env vars honored: `DEBSWAY_ASSUME_YES=1`,
  `DEBSWAY_SKIP_APT_UPDATE=1`, plus upstream pins `XFCE_GTK_REF=`,
  `XFCE_CURSOR_TAG=v2.0.0`, `NERD_FONT_TAG=3.4.0`, `BETTERFOX_TAG=150.0`.
  State log:
  `~/.local/state/devuan-xfce-setup/last-run.log`.
  Notable steps: `21-theme-tokyonight.sh` applies the rice — it seeds the
  palette-driven theme engine (`themes/<id>/palette.sh` + `lib/theme-apply.sh`
  rendered into `~/.config/devuan-xfce-setup/`, with `xfce-theme-set` /
  `xfce-theme-list` commands; palettes: tokyonight, catppuccin-mocha, nord),
  then GTK/xfwm4, rounded panel, Alacritty, genmon. `22-theme-boot.sh` themes
  Plymouth/GRUB/LightDM; the 4x optional phase ends with
  `46-heavy-optins.sh` (Thunderbird, LibreOffice, OBS — all default-N).
  `24-power-user.sh` deploys the power-user commands (xfce-menu,
  xfce-update-gui/check, xfce-lock/xfce-suspend + cron notifier).
- Root escalation goes through the `priv()` helper (`scripts/lib/common.sh`):
  **doas** first, sudo fallback, override with `DEBSWAY_PRIV=doas|sudo`.
  Never write bare `sudo` in new code.
- Every apt action checks what's actually installed first — nothing is
  blindly force-purged, so scripts are safe to re-run. Backups
  (`*.bak.<timestamp>`) precede any destructive config write.
- Test suite (ohmydebn-style, three tiers, all read-only): `make check`
  or `./tests/run.sh`. Tier 1 lint (bash -n/shellcheck/py_compile), tier 2
  sandboxed unit tests (theme-apply + common.sh, no root/no apt/no X),
  tier 3 consistency guards (VERSION↔RELEASE.md, palette hex/tokens,
  step-script headers, README parity, .gitignore) + apt-checks (read-only
  package existence against the local cache; `tests/lib/known-miss.list`
  covers contrib packages the toolkit adds at install time). Release gate:
  `make release-preflight`. When adding a new `scripts/##-*.sh`, run
  `make check` (adds its DEBSWAY_DESC/DEFAULT headers + README row).
- Content deb: `make pkg-deb` builds the single data-only asset package
  (`build/devuan-xfce-assets_*.deb`, ~6 MB, installed under
  `/usr/share/devuan-xfce-assets/`); `make check-deb` verifies it with
  dpkg-deb + lintian (zero errors). `packages/devuan-xfce-assets/` holds
  the metadata; the 13 MB payload is staged from the repo at build time.