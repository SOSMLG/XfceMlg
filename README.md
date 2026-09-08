# devuan-xfce-setup

Post-install polish for a Devuan (or Debian) box where **XFCE is already
installed** by the distro's own installer. This does *not* install XFCE —
it swaps a couple of defaults (Geany over Mousepad, VLC over Parole — XFCE's
own task install is already fairly lean, unlike KDE's `kde-standard`), then
fills in the rest: a full Catppuccin (Red/Black) theme from boot splash to
login screen to desktop, Bluetooth, TLP battery tuning, codecs, WiFi/BT
firmware, fonts, ButterBash for a proper terminal, and the gvfs/Thunar
plumbing, Flatpak, printing, GUFW, Timeshift, and update-notifier that make
it feel like a finished laptop distro instead of a bare XFCE session.

Built from your `myxfce` and `Butterbian-XFCE` repos the same way the
KDE-side version of this toolkit was built from `DebianSway` — as the seed
to extend with the same process (ordered `run.sh` + flat `scripts/` dir,
granular y/N prompts, backups before anything destructive), while adopting
real improvements found along the way (see "What changed" below).

## An actual bug-hunt pass, not just new features

Asked to do "intense rethinking" of the whole toolkit — so this pass
went back through every script looking for real bugs, not just gaps to
fill. Found and fixed:

- **A real `set -e` bug in the update-notifier step** (`desktopEssentials.sh`).
  `BEFORE_IDS=$(xfconf-query ... | grep ... | sort -u)` — if that pipeline
  came up empty (a real possibility: a fresh panel with no `/plugins`
  property indexed yet), `grep` returns non-zero, `pipefail` propagates
  that to the whole pipeline, and a *plain variable assignment* failing
  under `set -e` kills the script right there — silently, mid-step, no
  error message pointing at why. Same latent bug existed in `fastfetchConfig.sh`'s
  btop version check. Both now end their pipelines with `|| true`.
- **`install_pkgs()` always returned success, even when the install
  genuinely failed** — across 5 of the ~10 files that define it
  (`desktopEssentials.sh`, `gamingSetup.sh`, `hardwareSupport.sh`,
  `usefulApps.sh`, `vscodiumDevSetup.sh`). The function's last line was
  `apt-get install || warn "..."`, and since `warn` (an `echo`) always
  succeeds, the function's return value was always 0 — so anywhere that
  checked `if install_pkgs "Ristretto" ristretto; then set_default ...`
  (there are three such call sites) would run the follow-up step and
  report success even if the package genuinely failed to install.
  `bluetoothSetup.sh` already had this written correctly — that version
  is now what all five match.
- **A compositor fallback that left you with *no* compositor at all.**
  `catppuccinTheme.sh` always disables xfwm4's built-in compositor before
  trying to install picom (so the two don't fight). If picom's install
  then failed, the script warned about it — but never turned xfwm4's
  compositor back on, so a failed picom install silently meant zero
  compositing, not "back to the default." It now re-enables xfwm4 in
  that fallback.
- **A self-inflicted bug from an earlier edit in this same project**,
  caught while re-reading: a `str_replace` that added the Dunst step to
  `xfceDebloat.sh` had accidentally clobbered that step's own header,
  leaving the script's "all done" cleanup block running *before* the
  Dunst step instead of after it. Re-verified against a clean syntax
  pass and step-by-step trace after fixing.

**And the actual ask: the system beep.** `xfceDebloat.sh` gained a 6th
step that addresses all four *independent* sources of "the beep" — which
is exactly why so many "I turned it off but it's still beeping" forum
threads exist, each fix only ever touched one:
1. **PC speaker** (`pcspkr`/`snd_pcsp` kernel modules) — blacklisted and
   unloaded live.
2. **X11 bell** (GTK widgets ring this on backspace-at-start, failed
   tab-complete in a dialog, etc.) — `xset b off`, made to survive reboot
   via an autostart entry instead of just running once.
3. **XFCE's own event-sound bell** — a separate layer from #2, its own
   `xsettings` properties (`EnableEventSounds`, `EnableInputFeedbackSounds`).
4. **readline's bell** — bash's own tab-complete-fail beep, independent
   of X11 entirely (`set bell-style none` in `/etc/inputrc`, system-wide).

## Two more default-app swaps in xfceDebloat.sh

Same pattern as the existing Mousepad→Geany and Parole→VLC swaps —
replacing a stock XFCE component with something clearly better
maintained, not just different:

- **xfce4-screenshooter → [Flameshot](https://github.com/flameshot-org/flameshot).**
  One region-select overlay with annotate/blur/pin-to-screen/upload
  built in, instead of xfce4-screenshooter's multi-dialog flow. Print
  Screen gets rebound via `xfconf-query` (`/commands/custom/<Print>` in
  the `xfce4-keyboard-shortcuts` channel) to `flameshot gui`. If you had
  the screenshooter panel plugin on your panel, it'll show broken after
  this — that's a manual right-click-remove, not something safe to
  automate blindly.
- **xfce4-notifyd → [Dunst](https://github.com/dunst-project/dunst)**
  *(optional, defaults to skip)*. Lighter and far more configurable —
  do-not-disturb rules, per-urgency styling, better multi-monitor
  behavior. Ships with a Catppuccin Red-accented `dunstrc` out of the
  box. Dunst registers itself as the notification D-Bus service on
  install and starts on the first notification — no autostart entry
  needed, and no conflict once xfce4-notifyd's own is purged.

## Closing the "is this actually enough" gaps

Four things that "the desktop looks great" was papering over:

- **Boot → login didn't match the desktop.** New `bootThemeSetup.sh`:
  Catppuccin Plymouth splash ([catppuccin/plymouth](https://github.com/catppuccin/plymouth)),
  GRUB theme ([catppuccin/grub](https://github.com/catppuccin/grub)), and
  the LightDM login screen. The greeter runs as its own system user with
  no access to your `$HOME`, so this step copies your already-installed
  GTK/icon/cursor theme folders from `~/.themes` and `~/.local/share/icons`
  into `/usr/share/` rather than re-downloading anything — run
  `catppuccinTheme.sh` first so there's something to copy. This is the
  most invasive script in the toolkit (edits `/etc/default/grub`, rebuilds
  the initramfs) — every edit is backed up first, and it checks for GRUB
  and LightDM before touching either rather than assuming they're there.

- **No laptop power management, despite the ThinkPad-specific focus
  everywhere else.** `hardwareSupport.sh` now installs TLP, removes
  `power-profiles-daemon` first (the two fight over the same knobs if
  both run), and — only on hardware that actually exposes it — offers to
  cap charging at 80% via `/etc/tlp.d/60-battery-threshold.conf`.

- **The stuff that makes a fresh XFCE session not feel broken was
  missing.** `desktopEssentials.sh` gained: the `gvfs`/`thunar-volman`/
  `tumbler` stack (without this, Thunar's Trash silently does nothing
  and USB drives don't auto-mount — the single most common "XFCE feels
  broken" complaint), `thunar-archive-plugin` + `xarchiver`, and
  `xfce4-clipman` for clipboard history.

- **Eye comfort and update visibility.** Also in `desktopEssentials.sh`:
  Redshift (geoclue-located, gentle 6500K→4500K) and a real update
  path — Devuan has no Mint-style Update Manager, so this configures
  `unattended-upgrades` for periodic list refresh (auto-installing
  security updates stays opt-in) plus an `xfce4-genmon-plugin` panel
  icon that shows the pending-update count and opens an upgrade on click.

## Consolidated: 24 scripts → 19, Alacritty replaces xfce4-terminal

*(One file came back after this — `bootThemeSetup.sh`, added above. It
touches `/etc/default/grub` and rebuilds the initramfs, a genuinely
different risk profile from anything else here, so it stays separate
rather than getting folded into `catppuccinTheme.sh`'s purely-userspace
changes. Current count: 20.)*

Five scripts were folded into the ones they were really extending, not
removed — same functionality, fewer files to keep track of:

| Was | Now lives in |
|---|---|
| `terminalRedTheme.sh` | `catppuccinTheme.sh` (final step) |
| `picomSetup.sh` | `catppuccinTheme.sh` ("Extras" step) |
| `firewallSetup.sh` | `desktopEssentials.sh` (step 4) |
| `mintStyleApps.sh` | `usefulApps.sh` (steps 5–7) |
| `btopSetup.sh` | `fastfetchConfig.sh` (step 3) |

The firewall merge also fixed a real contradiction: `desktopEssentials.sh`
used to install GUFW while explicitly saying "not enabled," but
`firewallSetup.sh` ran later in `run.sh` and enabled ufw anyway — so the
message was already wrong by the time you'd see it. It's one step now,
with the SSH-safe enable logic actually attached to the install.

**`catppuccinTheme.sh` also stopped asking permission for its own point.**
Choosing to run it already means "yes, do the theme" — so the GTK/xfwm4
theme, cursors, icons, panel CSS, picom, and Alacritty setup now just run,
instead of a `Y/n` before each of 8 sub-steps. The only prompts left in it
are genuinely optional extras: Whisker Menu and NumLock-on-login.

**xfce4-terminal is gone, not kept as a fallback.** `catppuccinTheme.sh`'s
last step installs Alacritty with a Catppuccin Red config, sets it as the
default terminal everywhere XFCE looks (`x-terminal-emulator`, `exo`'s
`helpers.rc` — covers Thunar's "Open Terminal Here", Whisker Menu, and any
shortcut that spawns a terminal), then `apt purge`s xfce4-terminal. Kitty
support (previously an option alongside Alacritty) was dropped too —
one well-configured terminal beats a three-way menu nobody needed.
`terminalButterbash.sh`'s `term` alias was updated to launch Alacritty.

## Structure

```
devuan-xfce-setup/
├── run.sh                        # main entry — run this
├── butterbash/                   # bundled ButterBash, used offline
├── scripts/
│   ├── addUserToGroups.sh        # input/video/render groups
│   ├── xfceDebloat.sh            # Mousepad→Geany, Parole→VLC, screenshooter→Flameshot, optional Xfburn/notifyd→Dunst
│   ├── catppuccinTheme.sh        # Catppuccin Red/Black GTK/xfwm4/cursors/icons/panel + picom + Alacritty
│   ├── bootThemeSetup.sh         # Plymouth splash + GRUB theme + LightDM greeter (boot → login)
│   ├── touchpadTrackpointFix.sh  # usbhid mousepoll fix + optional libinput tuning
│   ├── hardwareSupport.sh        # WiFi/BT firmware, CPU microcode, fwupd, TLP + ThinkPad battery thresholds
│   ├── bluetoothSetup.sh         # bluez + Blueman GUI + audio bridge (Pulse/PipeWire) + codec negotiation
│   ├── multimediaCodecs.sh       # ffmpeg/GStreamer codecs, DVD playback, Audacity/Shotcut
│   ├── firefoxHarden.sh          # Firefox ESR + Betterfox, system-wide defaults (see below)
│   ├── policies.json             # firefox enterprise policy used by the above
│   ├── installFonts.sh           # Noto, Font Awesome, JetBrainsMono Nerd Font
│   ├── terminalButterbash.sh     # ButterBash + XFCE-specific shell additions
│   ├── fastfetchConfig.sh        # fastfetch + curated presets, plus optional Catppuccin-themed btop
│   ├── usefulApps.sh             # base tools, Python/data-science stack, Geany, VLC, Ristretto/Atril/GNOME Disks
│   ├── desktopEssentials.sh      # Flatpak, printing, GParted, ufw+GUFW, gvfs/Thunar essentials, Clipman, Redshift, update notifier
│   ├── timeshiftSetup.sh         # Timeshift system snapshot/restore
│   ├── installPhotogimp.sh       # (optional) GIMP + PhotoGIMP layout/theme, fetched live from GitHub
│   ├── installVscodium.sh        # (optional) VSCodium via official APT repo
│   ├── vscodiumDevSetup.sh       # (optional) VSCodium C++/Python dev environment
│   ├── gamingSetup.sh            # (optional) Steam / Heroic Games Launcher / Wine
│   └── vesktopTelegram.sh        # (optional) Vesktop (Discord client) / Telegram
└── README.md
```

## Usage

```bash
cd devuan-xfce-setup
chmod +x run.sh scripts/*.sh
./run.sh
```

Run it as your **normal user**, not as root. Every script calls `sudo`
itself for the parts that need it. `run.sh` walks through each step in
order asking `Y/n` (or `y/N`), same pattern as the KDE-side version. Run
any script standalone too:

```bash
bash scripts/touchpadTrackpointFix.sh
```

- **New `mintStyleApps.sh`** *(since merged into `usefulApps.sh` — see the consolidation table above)*. Covers the everyday Mint conveniences
  without the compatibility risk: Mint's own equivalents (xviewer,
  xreader, mintstick) are XApps distributed via Mint's own APT repo,
  built against Ubuntu package versions — confirmed by checking
  upstream's own docs, which state outright they're "not in the
  official Ubuntu or Debian repositories." Installing those `.deb`s
  on Devuan/Debian risks dependency conflicts; building from source
  pulls in a meson/gtk-doc/libwebkit2gtk toolchain for what's meant
  to stay a thin `apt install` toolkit. So this script gets the same
  job done with packages Debian/Devuan actually carry: **Ristretto**
  (image viewer) set as the default handler for common image types,
  **Atril** (MATE's evince fork — same PDF-viewing job, lighter
  dependency chain than pulling in evince itself) set as the default
  for PDFs, and **GNOME Disks**, whose dedicated "Disk Image Writer"
  launcher is the direct equivalent of Mint's USB Image Writer
  (mintstick) — write an ISO/IMG to a USB stick from a GUI. All three
  package names, their exact `.desktop` file names, and the
  `xdg-mime default` calls were verified by actually installing them
  and checking `dpkg -L` — Ristretto's turned out to be
  `org.xfce.ristretto.desktop`, not the `ristretto.desktop` an
  assumption would've produced.

- **Checked dougburks/ohmydebn in full (all ~150 `bin/` scripts, `config/`,
  `install/config/`).** Most of it doesn't transfer: it's a full Cinnamon/
  Mutter desktop-ricing framework (gTile tiling, its own keybinding system,
  Cinnamon-specific theming) — none of that runs on xfwm4, porting it would
  mean rewriting the tiling/gesture logic against a different window
  manager, not "adding" it. Its `bat`/`eza`/`zoxide`/`starship`/`fzf` setup
  is already covered by `terminalButterbash.sh`. Two pieces were genuinely
  portable, in-scope, and missing, so those got added:
  - **New `btopSetup.sh`** *(since merged into `fastfetchConfig.sh`)*. Installs btop and themes it with Catppuccin —
    sourced directly from catppuccin/btop's own repo (verified by actually
    downloading all four flavor files) rather than reverse-engineered from
    ohmydebn's theme-carousel template. Also carries over a real fix from
    ohmydebn's `theme-set-btop`: btop's SIGUSR2 hot-reload only exists on
    btop ≥ 1.3.1 (confirmed against the installed version, 1.3.0, in
    testing) — on anything older, sending that signal has no handler and
    falls back to SIGUSR2's default action, which terminates the process.
    The script checks the version before ever sending the signal.
  - **New `firewallSetup.sh`** *(since merged into `desktopEssentials.sh`)*. Same ufw deny-incoming/allow-outgoing
    baseline as ohmydebn's `ufw.sh`, tested end-to-end (`ufw allow ssh`,
    `default deny incoming`, `default allow outgoing`, `--force enable` all
    run and verified via `ufw status verbose`), plus a safety check
    ohmydebn doesn't need but this toolkit does: ohmydebn only ever runs on
    a machine you're physically at, so a bare deny-incoming is safe there.
    This toolkit might run over SSH on a headless box, where the same
    command would drop your own session — so it detects an active SSH
    session or listening sshd and allows SSH through first.

## Latest fixes & additions

- **`catppuccinTheme.sh`'s theme step is fixed.** Fausto-Korpsvart/Catppuccin-GTK-Theme
  restructured twice upstream: `install.sh` moved from the repo root into
  `themes/install.sh`, and its CLI flags changed from `-t <accent> -c <color>`
  to `-a <accent> -m <light|dark> --tweaks <black|border|macos|...>`. The
  script now **finds** `install.sh` wherever it actually lives instead of
  assuming a path, tries the current CLI first, falls back to the old CLI,
  then falls back to a full default build — and runs the installer with
  `BATCH_MODE=true` and a `timeout`, because its newest version ends with
  an interactive "Do you want to apply Vague?" arrow-key menu that hangs
  forever with no TTY attached (which is exactly why the run in the
  screenshot got stuck). Verified end-to-end with the installer's own
  `--dry-run` against upstream's current `main` — it now resolves to
  `Catppuccin-Red-Dark-Compact-BK` and exits `0`.
- **New `bluetoothSetup.sh`.** Bluetooth firmware alone (what
  `hardwareSupport.sh` installs) isn't enough to make earbuds work — the
  most common real-world failure is that a device *pairs* but never shows
  up as an audio output, because the PulseAudio/PipeWire ↔ BlueZ bridge
  package was never installed. This script installs the core stack (bluez,
  rfkill), auto-detects whether PulseAudio or PipeWire actually owns audio
  on the box and installs the matching bridge package
  (`pulseaudio-module-bluetooth` or `libspa-0.2-bluetooth` + `wireplumber`),
  adds the GStreamer plugins apps like Rhythmbox/Parole route audio
  through, optionally turns on BlueZ's `Experimental` flag so AAC/aptX/LDAC
  get negotiated instead of falling back to low-quality SBC, and installs
  **Blueman** (XFCE ships no Bluetooth GUI of its own) autostarted in the
  panel tray.
- **Alacritty's config is version-aware** *(this logic now lives in `catppuccinTheme.sh`'s terminal step)*.
  Alacritty changed its config syntax at 0.14 (`[terminal].shell` +
  `[general].import` are unrecognized before that). Debian/Devuan point
  releases ship different Alacritty versions, so the script now checks the
  installed version and rewrites the two syntax-sensitive keys to their
  pre-0.14 form when needed, the same compatibility trick
  [dougburks/ohmydebn](https://github.com/dougburks/ohmydebn) uses for the
  same problem — one config, both syntaxes, instead of two configs to keep
  in sync.

- **New `picomSetup.sh`** *(since merged into `catppuccinTheme.sh`'s "Extras" step)*. Adds "a little bit of animation" the way that
  doesn't cost battery: picom with fades only (window open/close + menus),
  explicitly no shadows and no blur (those, not fades, are what actually
  keep a GPU from idling), the `xrender` backend so it works on old/
  integrated hardware without holding a GLX context open, and
  `unredir-if-possible` — the real battery win, since it makes picom fully
  step aside (zero compositing overhead) whenever a fullscreen window
  (video, a game, a presentation) has focus. It also turns off xfwm4's
  own built-in compositor first, since running two compositors against
  the same display at once causes flicker and doubles the GPU work for
  no benefit. Config syntax verified by installing picom and running it
  against the generated config directly (fails only at "Can't open
  display", i.e. it parses cleanly with no display to attach to).

## What changed — Chicago95 retired for a modern, ThinkPad-red theme

**`chicagofier.sh` (Chicago95 / Windows 95 theme) is gone.** In its place,
`catppuccinTheme.sh` installs a modern look built around the
[Catppuccin](https://github.com/catppuccin) palette — the **Black**
variant with a **Red** accent, so the panel/window chrome echoes a
black ThinkPad chassis with its red TrackPoint nub, without the harsh
contrast a pure-white/red combo would put on your eyes:

- GTK2/3 + xfwm4 theme from
  [Fausto-Korpsvart/Catppuccin-GTK-Theme](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme)
- Cursors from [catppuccin/cursors](https://github.com/catppuccin/cursors)
  (`mocha`/`red`)
- Icons from [ljmill/catppuccin-icons](https://github.com/ljmill/catppuccin-icons)
  (the `Catppuccin-SE` release) — the script also builds a
  **`Catppuccin-SE-Local`** variant afterward: it keeps the small
  "chrome" icon categories (places/status/actions/devices/mimetypes)
  in full, but only copies *app* icons for software you actually have
  installed, then trims that variant's `index.theme` `Inherits=` down
  to `Adwaita,hicolor`. That's the same trick as trimming a bloated
  icon theme's inheritance chain so XFCE isn't indexing the entire
  upstream set at login — full `Catppuccin-SE` stays on disk untouched
  as a fallback, `Catppuccin-SE-Local` is what's actually active.
  Re-run the script after installing new apps to refresh it.
- A red/maroon-accented `~/.config/gtk-3.0/gtk.css` panel override
  (rounded corners, active-window/power-button in Red, battery/volume/
  tray keep their own accent colors for at-a-glance status)
- Optional Whisker Menu, compositor (shadows/transparency), and
  NumLock-on-login — small Mint-XFCE-style laptop touches, all opt-in

**Terminal theming was `terminalRedTheme.sh`; it's now the last step of
`catppuccinTheme.sh`, and it's Alacritty-only** — xfce4-terminal and Kitty
were both dropped in the consolidation above, see that section for why.

## What changed from the first version of this toolkit

**Back to `sudo`.** The first pass adopted `doas` from your reference
files' style. You asked for `sudo` throughout instead — done, mechanically,
across all 18 scripts, including removing the `doasBootstrap.sh` step
entirely (no longer needed) and the fallback-detection logic in every
other script.

**ButterBash is now the main shell config**, not a standalone `.bashrc`.
`terminalButterbash.sh` installs it the same way the KDE-side toolkit
does (its own `install.sh` backs up and replaces `~/.bashrc`), then
appends an "XFCE additions" block on top — the genuinely XFCE-specific
pieces from your reference `.bashrc` that ButterBash doesn't already
provide (it already ships its own `extract()`, git aliases, and
system-info aliases, so those aren't duplicated): panel restart,
screenshot, `xfce4-terminal`/Thunar helpers, brightness/touchpad toggles,
and your `cd`-via-`zoxide` navigation habit. One small bug fixed while
merging: your original `.bashrc` had two conflicting `alias thunar=`
definitions (one for daemon mode, one for "open here") that silently
shadowed each other — split into `thunar-daemon` and `here` instead.

**Firefox hardening now uses a system-wide defaults file, not a
per-profile one.** Your `Butterbian-XFCE` ISO config's own
`/etc/firefox-esr/butterbian.js` approach is genuinely better than what
this toolkit had: Debian's firefox-esr reads every `.js` file in
`/etc/firefox-esr/` and applies it as *default* prefs for every profile
on the system, so it covers new profiles automatically and doesn't need
a launcher-wrapper trick to stay current. `firefoxHarden.sh` was rewritten
around this — Betterfox is still fetched **live** from upstream at
install time (never bundled), then converted from `user_pref()` to
`pref()` syntax and written to `/etc/firefox-esr/devuan-xfce-setup.js`,
sitting alongside the package's own defaults file without touching it.

**Added `fastfetchConfig.sh`** — pulls the curated fastfetch presets from
your own `butterscripts` repo, the same source your ISO's own hook uses,
just targeting your actual `$HOME` instead of `/etc/skel` (this runs
against an existing account, not a new-user template).

## Notes

- Every apt action checks what's *actually installed* first — nothing is
  blindly force-installed or force-purged, so re-running any script is
  safe.
- Nothing in this toolkit auto-enables a firewall deny rule. Install and
  get out of the way, don't silently change behavior you didn't ask for.
- Reboot (or at least log out/in) after a full run — group membership,
  the mousepoll fix, newly installed firmware/microcode, and theme
  changes all benefit from a fresh session.
