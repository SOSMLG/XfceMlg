# System context: Devuan (excalibur) + XFCE

This machine was set up with `xfcemlg`, a post-install toolkit for a
ThinkPad-class laptop running Devuan 6 (excalibur) — binary-compatible with
Debian 13 (Trixie) — with a lean **XFCE** desktop (X11, floating) on a dark
**Graphite-Amber** rice (background `#16181D`, amber accent `#E8A33D`). Keep the
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
  Graphite-Amber desktop). SLiM and greetd must NOT be enabled alongside it —
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
  - Terminal is **Alacritty** (GPU-composited, Graphite-Amber colorscheme) and
    is THE default: `x-terminal-emulator` alternative +
    `~/.config/xfce4/helpers.rc` (`TerminalEmulator=alacritty`) — covers
    Thunar "Open Terminal Here", Whisker Menu, and panel launchers.
  - File manager is **Thunar** with the full plugin set (`volman`,
    `archive-plugin` + `xarchiver`, `media-tags`, `vcs`, `gtkhash`,
    `font-manager`) plus `gvfs-backends` (Trash/MTP) and `tumbler`
    thumbnails. Custom actions live in `~/.config/Thunar/uca.xml`.
  - Notifications are **xfce4-notifyd** (stock), screenshots are
    **Flameshot** (`Print` = `flameshot full`, `Super+Print` = `flameshot gui`, `Super+S` shortcuts via
    `23-input-fix.sh`), clipboard history is
    **xfce4-clipman**, night-light is **Redshift**, compositor is **xfwm4's
    built-in compositor** (picom is gone): subtle window/popup shadows,
    inactive dim and move/resize fade, all handled by the xfwm4.xml seed —
    no extra daemon.
  - System info in the terminal/login is **fastfetch** with the Devuan
    ASCII logo (not neofetch).
  - Panel + window-manager rice is a static seed in
    `configs/xfce4/xfconf/xfce-perchannel-xml/` (`xfce4-panel.xml`,
    `xfwm4.xml`) — item layout, decorations and the JetBrainsMono Nerd
    Font clock/title fonts. `21-theme.sh` copies it into
    `~/.config/xfce4/xfconf/` (backing up) then restarts `xfce4-panel`
    and `xfwm4`. No genmon — the old update-indicator widget is gone;
    updates are handled by the power-user commands + notifier in
    `24-power-user.sh`.
- The Graphite-Amber rice is **built at install time**, not bundled:
  `scripts/lib/graphite-amber-fetch.sh` pulls a pinned **legacy upstream base**
  from a pinned legacy upstream base (assembling the plain/hdpi/xhdpi
  variants as Graphite-Amber) and the icons from `zayronxio/Zafiro-icons` (renamed to
  **Zafiro-icons-Dark**, `apps/scalable` trimmed), auto-applies the
  amber-accent remap (`#e78a53`→`#E8A33D`) and deploys to
  `/usr/share/themes/` + `/usr/share/icons/` via `21-theme.sh`; there is
  **no theme engine** and no palette switcher — `Graphite-Amber` is the GTK +
  xfwm4 theme, period. Wallpapers are the curated graphite/amber set in
  `configs/wallpapers/graphite-amber/` (deployed to
  `/usr/share/backgrounds/xfce/devuan-graphite-amber/`). The static
  `~/.config/xfcemlg/picker.colors` file carries the palette for
  the Python menu/update-gui widgets. Plymouth, GRUB and the LightDM greeter
  are themed to match.

## This toolkit's own conventions (for consistency if extending it)
- Scripts live in `scripts/`, numbered `??-*.sh` (1x core, 2x desktop,
  3x apps, 4x optional, 5x utils), each independently runnable
  (`bash scripts/<name>.sh`), all sourcing `scripts/lib/common.sh` for
  shared `ask()`/`log_*`/`install_pkgs`/`priv()` helpers. Metadata comes
  from `# XMLG_DESC:` / `# XMLG_DEFAULT:` headers read by `install.sh`.
- `install.sh` discovers steps automatically (`--list/--phase/--only/--yes/
  --full/--no-update/--verify`); `install.sh` is the fully-unattended
  one-command wrapper. Env vars honored: `XMLG_ASSUME_YES=1`,
  `XMLG_SKIP_APT_UPDATE=1`, plus upstream pins `XFCE_GTK_REF=`,
  `XFCE_CURSOR_TAG=v2.0.0`, `NERD_FONT_TAG=3.4.0`, `BETTERFOX_TAG=150.0`
    and the theme fetch pins `DM_THEME_URL=` / `DM_ICONS_URL=` (immutable
    commit SHAs, not branch refs) plus `DM_THEME_SHA256=` / `DM_ICONS_SHA256=`
    over those tarballs, and `DM_SKIP_FETCH=1`.
  State log:
  `~/.local/state/xfcemlg/last-run.log`.
  Notable steps: `21-theme.sh` applies the rice — it fetches the Graphite-Amber
  GTK/xfwm4 themes + Zafiro icons via `scripts/lib/graphite-amber-fetch.sh`
  (nothing bundled in git), writes the Graphite-Amber
  `alacritty.toml`, seeds the rounded panel and the xfwm4 compositor, writes
  the static
  `picker.colors`, and cleans up any old palette-engine leftovers.
  `22-theme-boot.sh` themes Plymouth/GRUB/LightDM to match (near-black
  `#16181D` + red `#E8A33D`). Most steps now default to **Y**, including the
  4x optional phase (`43-photogimp`, `44-gaming`, `45-chat`,
  `46-heavy-optins` — Thunderbird, LibreOffice, OBS) and the 5x utils.
  `24-power-user.sh` deploys the power-user commands (xfce-menu,
  xfce-update-gui/check, xfce-lock/xfce-suspend + cron notifier).
- Root escalation goes through the `priv()` helper (`scripts/lib/common.sh`):
  **doas** first, sudo fallback, override with `XMLG_PRIV=doas|sudo`.
  Never write bare `sudo` in new code.
- Every apt action checks what's actually installed first — nothing is
  blindly force-purged, so scripts are safe to re-run. Backups
  (`*.bak.<timestamp>`) precede any destructive config write.
- Runtime verification: `./install.sh --verify` or `bash scripts/verifySetup.sh`.
  Release gate: `make release-preflight` checks VERSION/RELEASE.md agreement.
  When adding a new `scripts/##-*.sh`, give it XMLG_DESC/DEFAULT headers
  and a README row.
- Content deb: `make pkg-deb` builds the single data-only asset package
  (`build/xfcemlg-assets_*.deb`, ~7 MB, installed under
  `/usr/share/xfcemlg-assets/`); `make check-deb` verifies it with
  dpkg-deb + lintian (zero errors). `packages/xfcemlg-assets/` holds
  the metadata; the ~7 MB payload (configs/ — the Graphite-Amber themes/icons
  are fetched at install, not shipped) is staged from the repo at build time.