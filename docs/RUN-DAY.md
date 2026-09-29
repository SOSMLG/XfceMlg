# Run-day checklist — xfcemlg on a pre-installed Devuan XFCE laptop

The maintainer's main target scenario: a **pre-installed Devuan 6 (excalibur)
+ XFCE** ThinkPad-class laptop, polished by this toolkit with a **full
Darkmatter takeover**. This page is the run-day clipboard: exact commands and
the output to expect at each step. Everything here is read-only except the
"Install" phase itself, and every destructive write the toolkit makes is
backed up first (`*.bak.<timestamp>`, `deploy_seed_file` stamps).

Payload: the local `v0.8.2` tag of this repository (nothing is published;
the target machine gets this tree as-is via `rsync`).

## 0. Scope, locked

- **Full takeover is the point.** The stock XFCE panel, window-manager
  decor, GTK theme and power settings are replaced by the Darkmatter seed.
  Originals are preserved as `.bak.<timestamp>` copies next to each file, so
  the pre-run desktop is restorable per-file (see Rollback).
- Never-clobber discipline still applies to *user* content: `~/.bashrc`
  only ever gets an append-only marker block, Thunar view defaults are
  create-only, and any config the toolkit installed then you hand-edited is
  left alone once it carries a `.xfcemlg.sha256` stamp.
- On a fresh box the 44-gaming.sh Flatpak-Heroic orphan check is a harmless
  no-op (there is no Flatpak Heroic to purge) — by design.

## 1. Preflight — on the target laptop (read-only)

```sh
cat /etc/os-release          # expect: Devuan GNU/Linux 6, codename excalibur
echo "$XDG_SESSION_TYPE"     # x11 (XFCE is X11, not Wayland)
xfce4-session --version      # XFCE 4.x (4.20 on excalibur/trixie)
rc-update show | grep -iE 'lightdm|slim|gdm|greetd'   # lightdm only — exactly one DM
groups                       # the user must be in sudo (doas gets wired by 12-user-groups)
df -h / /home                # headroom for timeshift(31) + the ~1 GB HOME backup(51) + apt
ip -4 addr show              # LAN reachable for rsync + the install's downloads
```

Nothing else to prepare: `contrib`/`non-free` apt components and backports
pinning are added by the toolkit itself.

## 2. Deliver — the repo to the laptop

Run from the dev box (either over the LAN or via USB stick):

```sh
rsync -a --exclude .git ~/XfceMlg/ <laptop>:~/xfcemlg/
```

Confirm the payload on the laptop:

```sh
cat ~/xfcemlg/VERSION        # 0.8.2
./run.sh --list              # must show 31 steps in core→desktop→apps→optional→utils
```

No `git`, no build step, no deb required — the scripts run in place.
(`make pkg-deb` is optional and assets-only; it is not part of this install.)

## 3. Preview + the one scope decision

```sh
cd ~/xfcemlg && ./run.sh --list
```

Decide the **optional** phase before the big run:

| Command                       | What runs                                                     |
|-------------------------------|---------------------------------------------------------------|
| `./install.sh`                | `--full`: everything, *including* optional 40-VSCodium, 41-dev toolchains, 43-PhotoGIMP, 44-gaming, 45-chat, 46-heavy (Thunderbird/LibreOffice/OBS) |
| `./install.sh --core`         | core + desktop + apps only (no optional, no utils)            |
| `./install.sh --only 10,13,..`| just the listed steps, unattended                             |

Full takeover is the default expectation of this checklist; trim with
`--core`/`--only` if the laptop should stay lean.

## 4. Install — the run

```sh
cd ~/xfcemlg && ./install.sh
```

Unattended (`XMLG_ASSUME_YES=1 run.sh --full --verify`). Typical wall time
**20–60 minutes**, dominated by apt + the GitHub fetch (Darkmatter + Zafiro
icons) + Nerd Fonts + VSCodium + dev toolchains. Run it from the target's
desktop session (the panel and xfwm4 restart once during 21-theme — a brief
blink) or over SSH (restarts skipped, which is fine).

**True zero-prompt (recommended):** root auth is the one remaining
interaction — `permit persist` (wired by 12-user-groups) re-asks your
password every ~5 minutes. One idempotent command up front makes the whole
run input-free:

```sh
printf 'permit nopass %s as root\n' "$USER" | doas tee -a /etc/doas.conf
```

Last line wins in doas.conf, so the nopass rule takes effect; 12 detects an
existing nopass rule and keeps it as-is. Without it, expect to type your
password every few minutes. apt itself is debconf-proof on this run:
`install.sh` exports `DEBIAN_FRONTEND=noninteractive` and installs keep
existing configs (`--force-confdef`/`--force-confold`).

Step highlights that matter on a pre-installed laptop:

- **12-user-groups** — wires a `doas` rule (sudo stays as fallback).
- **13-hardware** — firmware/microcode/fwupd, boot params, TLP, ThinkPad
  charge threshold to **80%** (`/etc/tlp.d/70-maxbattery.conf`), suspend
  resume hook. `power-profiles-daemon` is purged so it cannot fight TLP.
  thinkfan + powertop (auto-tune) are the only *optional* installs there,
  and on a full run they install themselves — their `ask_no_full` prompts
  default to **Y**.
- **16-firefox** — Firefox ESR + Betterfox + enterprise policy.
- **17-fonts** — JetBrainsMono Nerd Font (the PS1 glyphs depend on it).
- **18-shell-config** — clears out leftovers of the previous shell setup,
  then appends the marked hook block to `~/.bashrc`
  (`# BEGIN xfcemlg-shell`), with a pre-append copy saved once to
  `~/.bashrc.xfcemlg.bak`.
- **20-xfce-debloat** — the *only* step that removes preinstalled packages:
  mousepad/geany, parole/quodlibet, xfburn, xfce4-screenshooter,
  xfce4-genmon-plugin, xfce4-terminal(+data) → Alacritty, xfce4-notifyd →
  dunst. Everything else in the toolkit is additive.
- **21-theme** — the takeover: `xfce4-panel.xml`, `xfwm4.xml`,
  `xsettings.xml`, `xfce4-power-manager.xml` get the Darkmatter seed with
  `.bak.<timestamp>` backups; panel launchers likewise; Thunar views are
  create-only.
- **22-theme-boot** — Plymouth+GRUB+LightDM theming; the Plymouth part
  no-ops when Plymouth isn't installed.
- **30-desktop-essentials** — its install question is `ask_no_full`: it
  does **not** auto-fire under `--full` (nothing app-installs without an
  explicit yes on a full run).
- **51-backup** — snapshots the whole `$HOME` first:
  `~/xfce-config-backup-<stamp>.tar.gz` (~1 GB); the same file is where the
  0.8.x bulk-config data lives by design.
- **52-skel-export** — stamps `/etc/skel` including the bash hook, so fresh
  accounts start with the shell config.

State for the whole run: `~/.local/state/xfcemlg/last-run.log` (and the
previous-version paths migrate automatically via `migrate_legacy_paths`).

Useful env overrides, if needed:

```sh
XMLG_SKIP_APT_UPDATE=1     # apt lists already fresh on the target
XMLG_FORCE_SEEDS=1         # re-take a config you later hand-edited (use advisedly)
DM_SKIP_FETCH=1            # reuse ~/.cache/xfcemlg fetched themes instead of re-downloading
```

A reboot (or at least log out/in) after the run picks up group membership,
firmware/microcode, the input fixes and the theme fully.

## 5. Verify — after the run

`install.sh --verify` already runs `scripts/verifySetup.sh` (Darkmatter /
Zafiro-icons-Dark / devuan-darkmatter names, power-user bins). Spot checks:

```sh
tail ~/.local/state/xfcemlg/last-run.log         # all steps, no failures
xfconf-query -c xsettings -p /Gtk/ThemeName      # Darkmatter
xfconf-query -c xsettings -p /Net/IconThemeName  # Zafiro-icons-Dark
xfconf-query -c xfwm4 -p /general/theme          # Darkmatter
grep -n 'BEGIN xfcemlg-shell' ~/.bashrc          # hook present (append-only)
command -v xfce-menu xfce-update-gui xfce-lock xfce-suspend
python3 -m json.tool /etc/firefox/policies/policies.json   # ESR hardening live
doas tlp-stat -s                                 # TLP active, charge cap at 80%
tlp-stat -c                                      # battery tuning (70-maxbattery.conf)
```

Then open a **new** terminal: the two-line Nerd-Font PS1 in Darkmatter
colors (`#e75353`/`#5f8787`/`#fbcb97`) should be there; `fastfetch` shows the
bundled art. If timeshift(31) ran, optionally take the first snapshot now.

## 6. Rollback — full takeover without a reinstall

- **Panel / WM / theme**: the pre-run originals are
  `~/.config/xfce4/xfconf/xfce-perchannel-xml/<file>.xml.bak.<timestamp>` —
  `cp` each back, then `xfce4-panel -r` (and/or `xfwm4 --replace`).
- **Debloat removals**: reinstall the purged list (mousepad, geany, parole,
  quodlibet, xfburn, xfce4-screenshooter, xfce4-genmon-plugin, xfce4-terminal,
  xfce4-notifyd) — or just `apt-get install` the ones you miss.
- **Seeds**: re-running `install.sh` converges forward; `XMLG_FORCE_SEEDS=1`
  makes the shipped seeds win over any hand edits.
- **bash hook**: remove the `# BEGIN xfcemlg-shell` … `# END xfcemlg-shell`
  block, or restore `~/.bashrc.xfcemlg.bak`.
- **Shell config**: `~/.config/xfcemlg/bash/` is the whole of it — delete the
  dir and the hook to go back to a stock prompt.
- **Re-runs are idempotent** and just as unattended as the first run. The
  only prompts with a "no" default are the destructive/restore ones (apt
  full-upgrade, backup restore, purges, pruning); benign installs such as
  thinkfan/powertop are default-**Y**, so a re-run converges to the full
  install without any keypresses.
