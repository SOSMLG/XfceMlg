# devuan-xfce-setup — Release Notes

Tag a release with: `git tag -a "v$(cat VERSION)" -m "v$(cat VERSION)" && git push --tags`

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
- Utils: time-sync, OpenCode agent, Neovim pin, maintenance, backup,
  skel-export, `verifySetup.sh`, AI skill file, `configs/` sources
