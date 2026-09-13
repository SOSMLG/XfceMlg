# System context: Devuan (excalibur) + XFCE

This machine was set up with `devuan-xfce-setup`, a post-install toolkit for a
ThinkPad-class laptop running Devuan 6 (excalibur) — binary-compatible with
Debian 13 (Trixie) — with a lean **XFCE** desktop (X11, floating) themed
Catppuccin Mocha/Red. Keep the following in mind when suggesting commands or
diagnosing issues on this system:

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
  desktop). SLiM and greetd must NOT be enabled alongside it — exactly one
  DM owns the console. Default session: `Xfce Session`.

## Desktop environment
- **XFCE 4.20 on X11** (floating, traditional panel), not a tiling WM and not
  GNOME/KDE. This changes how you configure things:
  - Settings live in **xfconf** — query/set with
    `xfconf-query -c <channel> -p <property>` (channels: `xfce4-panel`,
    `xfce4-keyboard-shortcuts`, `xfwm4`, `xsettings`, `thunar-volman`,
    `thunar`, `xfce4-notifyd`, `xfce4-power-manager`).
  - Keyboard shortcuts are `/commands/custom/<keysym>` properties in the
    `xfce4-keyboard-shortcuts` channel — there is no sway-style config file
    with `bindsym` lines.
  - Terminal is **xfce4-terminal** (X11-native; `foot` is Wayland-only and
    absent, Alacritty deliberately removed). Default terminal is wired via
    `x-terminal-emulator` alternative + `~/.config/xfce4/helpers.rc`
    (`TerminalEmulator=xfce4-terminal`) — covers Thunar "Open Terminal
    Here", Whisker Menu, and panel launchers.
  - File manager is **Thunar** with the full plugin set (`volman`,
    `archive-plugin` + `xarchiver`, `media-tags`, `vcs`, `gtkhash`,
    `font-manager`) plus `gvfs-backends` (Trash/MTP) and `tumbler`
    thumbnails. Custom actions live in `~/.config/Thunar/uca.xml`.
  - Notifications are **xfce4-notifyd** (stock), screenshots are
    **xfce4-screenshooter** (`Print` key), clipboard history is
    **xfce4-clipman**, night-light is **Redshift**, compositor is **picom**
    (fades only; xfwm4's built-in compositing stays off so the two don't
    fight).
  - Panel plugins used: genmon (update indicator), clipman, pulseaudio,
    power-manager, cpugraph/netload (optional graphs).
- Theming is Catppuccin Mocha/Red (Black variant): GTK/xfwm4 from
  Fausto-Korpsvart, `Catppuccin-SE-Local` icons, mocha-red cursors, panel
  `gtk.css` override, matching LightDM greeter + Plymouth + GRUB.

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
- Root escalation goes through the `priv()` helper (`scripts/lib/common.sh`):
  **doas** first, sudo fallback, override with `DEBSWAY_PRIV=doas|sudo`.
  Never write bare `sudo` in new code.
- Every apt action checks what's actually installed first — nothing is
  blindly force-purged, so scripts are safe to re-run. Backups
  (`*.bak.<timestamp>`) precede any destructive config write.
