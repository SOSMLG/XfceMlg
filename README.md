# devuan-xfce-setup

A post-install toolkit that turns a fresh **Devuan 6 (Excalibur)** install
(binary-compatible with **Debian 13 (Trixie)**) into a lean, finished
**XFCE** desktop — Catppuccin **Red/Black** themed from boot splash to login
screen to terminal, Firefox ESR hardened, TLP battery-capped, Thunar fully
plugged in, and installable with **one command, fully unattended**.

Works from two starting points: a distro installer where **XFCE is already
present**, or a **minimal netinst** with no desktop at all (the toolkit
installs its own lean set and never touches tasksel — so the hated SLiM
login never enters the picture).

```
./install.sh        # everything, unattended, verified — that's it
./run.sh --list     # see every step in order, defaults and all
./run.sh            # pick-and-choose interactively
```

You run it as your **normal user** (never `doas bash install.sh`); each script
escalates itself (`priv()` helper: doas first, sudo fallback) for the parts
that need it.

---

## Quick start

On a fresh Devuan 6 (Excalibur) / Debian 13 (Trixie) install, with network up:

```bash
# 1. Clone + run
git clone <this-repo> && cd devuan-xfce-setup
./install.sh
# ~everything, then a verification report; reboot when it finishes

# 2. Reboot — LightDM gives you a themed login screen, pick "Xfce Session"
```

`install.sh` = `run.sh --full --verify`: every step answers **yes**, including
the optional groups (VSCodium, gaming, chat, PhotoGIMP, dev tools, neovim).
Variants:

| Command | What it does |
|---|---|
| `./install.sh --core` | Core XFCE desktop only, skips optional groups |
| `./run.sh --yes` | Everything, but only the default-Y steps (no optional groups) |
| `./run.sh --phase core,desktop` | Only the core + desktop phases |
| `./run.sh --only firefox,useful-apps` | Just those steps (short names work) |
| `./run.sh --no-update` | Skip the runner's single `apt-get update` |

Install with `bash -x ./install.sh` to watch every step, if you're curious or
something looks off.

### Minimal netinst notes

Two things a bare netinst often lacks — the toolkit handles both, but order
matters:

* **Privilege for your user.** Either leave the root password **empty** during
  install (Debian then puts your user in `sudo`), or afterwards as root:
  ```bash
  apt install -y sudo opendoas && usermod -aG sudo <you>
  printf 'permit persist <you> as root\n' > /etc/doas.conf
  ```
  then **relogin**. The toolkit refuses to run as root and warns early if
  escalation can't work — `12-user-groups.sh` sets up the doas persist rule
  so the rest of the run asks for your password once.
* **No desktop at all.** That's fine — `10-xfce-core.sh` installs a lean
  `--no-install-recommends` XFCE set (session, xfwm4, panel, xfce4-terminal,
  Thunar base, LightDM + gtk-greeter, polkit, gvfs) directly, deliberately
  bypassing `task-xfce-desktop`: tasksel prefers **SLiM** as its DM and
  bundles Parole/QuodLibet/Mousepad that would only be purged again. If SLiM
  is found anyway, it gets purged and LightDM takes the console.

---

## What you get

| Layer | Choice |
|---|---|
| Desktop | **XFCE 4.20 on X11** (floating, traditional panel) via **LightDM + gtk-greeter** login, themed to match |
| Theme | Catppuccin **Mocha/Black + Red** (ThinkPad chassis + TrackPoint nub): GTK2/3/4 + xfwm4, mocha-red cursors, `Catppuccin-SE-Local` lean icons, panel CSS, matching Plymouth + GRUB + LightDM |
| Terminal | **xfce4-terminal** (X11-native; foot is Wayland-only, Alacritty removed) themed Catppuccin Red, wired as THE terminal via `x-terminal-emulator` + exo `helpers.rc` |
| Shortcuts | Super-based set (terminal, files, appfinder, screenshots, clipman, tiling, workspaces) + `Ctrl+Alt+L` lock via **light-locker** |
| First login | Welcome wizard (update + Timeshift check, once) + wallpaper seeder (new monitors only, never overwrites) |
| Files | **Thunar, full set**: volman automount, archive-plugin + xarchiver, media-tags, vcs, gtkhash, font-manager, `gvfs-backends` (Trash/MTP), tumbler thumbnails, custom actions (Terminal Here, Open as Root) |
| Media/docs | **VLC** (Parole removed), **Ristretto** images, **Atril** PDFs, GNOME Disks for USB writes |
| Editor | **VSCodium** (primary GUI editor; Mousepad/Geany removed — no TUI-editor detour) |
| Browser | **Firefox ESR** hardened with Betterfox-derived system defaults + locked `policies.json` |
| Shell | **ButterBash**: saner bash (aliases, `eza`/`bat`, fzf/zoxide, starship) + XFCE additions block |
| Compositor | **picom** (fades only, unredirects fullscreen; xfwm4 compositing stays off) |
| Notifications | **xfce4-notifyd** stock (Dunst stays opt-in) |
| Capture | **xfce4-screenshooter** on `Print` (Flameshot stays opt-in) |
| Clipboard | **xfce4-clipman** panel plugin |
| Night light | **Redshift** (geoclue-located, 6500K→4500K) |
| Battery | **TLP** + 80% charge cap on supporting ThinkPads |
| Bluetooth | **Blueman** applet (A2DP bridge auto-detected for Pulse/PipeWire) |
| Updates | genmon panel indicator (hourly check, click to upgrade in a terminal) |
| Snapshots | **Timeshift** |

### Scripts — phases in run order (`./run.sh --list` is authoritative)

| Phase | Script | Default |
|---|---|---|
| core | `10-xfce-core.sh` — lean XFCE + LightDM, SLiM purge, no tasksel | Y |
| core | `11-backports.sh` — backports + apt pinning (priority 100) | Y |
| core | `12-user-groups.sh` — `input`/`video`/`render`/`plugdev` + doas persist | Y |
| core | `13-hardware.sh` — WiFi/BT/AMD firmware, microcode, fwupd, TLP | Y |
| core | `14-bluetooth.sh` — Bluetooth stack + Blueman | Y |
| core | `15-codecs.sh` — audio/video codecs + DVD | Y |
| core | `16-firefox.sh` — Firefox ESR + Betterfox hardening | Y |
| core | `17-fonts.sh` — Noto, Font Awesome, JetBrainsMono Nerd Font | Y |
| core | `18-butterbash.sh` — ButterBash + XFCE shell additions | Y |
| core | `19-fastfetch.sh` — fastfetch presets + optional btop theme | Y |
| desktop | `20-xfce-debloat.sh` — trim task apps, keep XFCE-native, silence beep | Y |
| desktop | `21-theme-catppuccin.sh` — Catppuccin Red/Black + picom + terminal theme | Y |
| desktop | `22-theme-boot.sh` — Plymouth + GRUB + LightDM greeter theming | Y |
| desktop | `23-input-fix.sh` — input fixes + light-locker + Super shortcuts | Y |
| apps | `30-desktop-essentials.sh` — Flatpak, CUPS, firewall, Thunar full, Clipman, Redshift | Y |
| apps | `31-timeshift.sh` — Timeshift snapshots | Y |
| apps | `32-time-sync.sh` — chrony NTP time sync | N |
| apps | `33-useful-apps.sh` — base tools, Python stack, Ristretto, Atril, Disks | Y |
| apps | `34-opencode-agent.sh` — OpenCode AI agent + Super+A hotkey + skill file | Y |
| apps | `35-first-run.sh` — welcome wizard + wallpaper seeder (autostart) | Y |
| optional | `40-vscodium.sh` — VSCodium (primary editor) | Y |
| optional | `41-dev-essentials.sh` — C/C++ + Python toolchains | Y |
| optional | `43-photogimp.sh` — GIMP + PhotoGIMP layout | N |
| optional | `44-gaming.sh` — Heroic/Steam/Wine | N |
| optional | `45-chat.sh` — Vesktop (Discord) / Telegram | N |
| optional | `46-neovim.sh` — Neovim (Debian apt 0.10) + LazyVim v14 pinned config | N |
| utils | `50-maintenance.sh` — apt cleanup + dead symlink tidy | N |
| utils | `51-backup.sh` — timestamped HOME config backup/restore | N |
| utils | `52-skel-export.sh` — per-user defaults into `/etc/skel` | N |

---

## Verification

```bash
./run.sh --verify        # after an install.sh run
bash scripts/verifySetup.sh   # anytime
```

Prints PASS/FAIL/WARN for groups, lean-core packages, Thunar plugins,
fonts, Firefox policy, Catppuccin markers (GTK/icons/terminalrc), the
LightDM greeter conf, SLiM absence, and services (LightDM, TLP,
Bluetooth, CUPS, chrony…). Exits non-zero on any FAIL — so it can gate CI.

After a run there's a full log at
`~/.local/state/devuan-xfce-setup/last-run.log`, and `scripts/51-backup.sh`
snapshots your config into a timestamped tarball before major operations.

---

## Maintenance & troubleshooting

* **Two login screens / DM fight?** Exactly **one** display manager may own
  the console. This toolkit enables `lightdm` and purges `slim`; if you
  also enabled `greetd`/`sddm`, disable the spare
  (`doas rc-update del greetd default`) and keep LightDM.
* **Thunar Trash does nothing / USB won't mount?** That's the missing
  gvfs/volman stack — re-run `30-desktop-essentials.sh` step 5, then
  `thunar -q` to reload.
* **No network/volume/password dialogs on minimal?** `10-xfce-core.sh`
  covers `network-manager-gnome` (opt-in), `xfce-polkit` and `dbus-x11` —
  re-run it if you skipped it the first time.
* **Beep still there?** Four independent sources are all silenced by
  `20-xfce-debloat.sh` (pcspkr module, X11 bell, XFCE event sounds,
  readline). Anything left is per-app (e.g. the terminal's own bell toggle).
* **Backports**: `doas apt install -t excalibur-backports <pkg>` — the pin
  (priority 100) never auto-upgrades.
* **Firefox locked policy**: `scripts/policies.json` is placed system-wide
  (`/usr/lib/firefox-esr/distribution/`), Betterfox-derived defaults go to
  `/etc/firefox-esr/devuan-xfce-setup.js`. Both idempotent.
* **AI skill**: `34-opencode-agent.sh` drops
  `scripts/skills/xfce-setup-SKILL.md` to `~/.config/opencode/AGENTS.md`
  (and `~/AGENTS.md`) so coding agents know this box.

---

## Layout

```
VERSION / RELEASE.md   toolkit version + changelog (tag: git tag -a "v$(cat VERSION)")
run.sh           ordered runner (phases: core/desktop/apps/optional/utils)
install.sh       one-command unattended wrapper
scripts/
  lib/common.sh  shared helpers (DEBSWAY_* envs, ask, pkgs, priv helper)
  10-*.sh … 52-*.sh  one step each, numbered = run order; runnable standalone
  verifySetup.sh end-state audit (run.sh --verify)
  policies.json  Firefox enterprise policy (used by 16-firefox.sh)
  skills/xfce-setup-SKILL.md   system context for AI agents
configs/         versioned static config (Thunar/uca.xml — deployed by 30-*)
butterbash/      bundled ButterBash, used offline
```

---

## Notes

- Every apt action checks what's *actually installed* first — nothing is
  blindly force-installed or force-purged, so re-running any script is
  safe. Destructive writes (grub, initramfs, greeter confs) are backed up
  first (`*.bak.<timestamp>`).
- Env vars honored: `DEBSWAY_ASSUME_YES=1` (unattended),
  `DEBSWAY_SKIP_APT_UPDATE=1`, `DEBSWAY_PRIV=doas|sudo`, plus upstream
  pins `XFCE_GTK_REF=`, `XFCE_CURSOR_TAG=v2.0.0`, `NERD_FONT_TAG=3.4.0`,
  `BETTERFOX_TAG=150.0`. Resolved theme SHAs land in
  `~/.local/state/devuan-xfce-setup/`.
- Nothing auto-enables a firewall deny rule without the SSH-safe guard in
  `30-desktop-essentials.sh`. Install and get out of the way.
- Reboot (or at least log out/in) after a full run — group membership,
  the mousepoll fix, newly installed firmware/microcode, and theme
  changes all benefit from a fresh session.
