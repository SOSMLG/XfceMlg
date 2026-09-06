# devuan-xfce-setup

Post-install polish for a Devuan (or Debian) box where **XFCE is already
installed** by the distro's own installer. This does *not* install XFCE —
it swaps a couple of defaults (Geany over Mousepad, VLC over Parole — XFCE's
own task install is already fairly lean, unlike KDE's `kde-standard`), then
fills in the rest: codecs, WiFi/Bluetooth firmware, fonts, ButterBash for a
proper terminal, Flatpak, printing, GParted, GUFW, Timeshift, and an optional
from-source build of the Windows XP theme.

Built from your `myxfce` and `Butterbian-XFCE` repos the same way the
KDE-side version of this toolkit was built from `DebianSway` — as the seed
to extend with the same process (ordered `run.sh` + flat `scripts/` dir,
granular y/N prompts, backups before anything destructive), while adopting
real improvements found along the way (see "What changed" below).

## Structure

```
devuan-xfce-setup/
├── run.sh                        # main entry — run this
├── butterbash/                   # bundled ButterBash, used offline
├── scripts/
│   ├── addUserToGroups.sh        # input/video/render groups
│   ├── xfceDebloat.sh            # Mousepad→Geany, Parole→VLC, optional Xfburn removal
│   ├── catppuccinTheme.sh        # Catppuccin (Black+Red) GTK/xfwm4 theme, icons, cursors, panel CSS
│   ├── picomSetup.sh             # picom compositor — fades only, no shadows/blur, battery-friendly
│   ├── touchpadTrackpointFix.sh  # usbhid mousepoll fix + optional libinput tuning
│   ├── hardwareSupport.sh        # WiFi/BT firmware, CPU microcode, fwupd
│   ├── bluetoothSetup.sh         # bluez + Blueman GUI + audio bridge (Pulse/PipeWire) + codec negotiation
│   ├── multimediaCodecs.sh       # ffmpeg/GStreamer codecs, DVD playback, Audacity/Shotcut
│   ├── firefoxHarden.sh          # Firefox ESR + Betterfox, system-wide defaults (see below)
│   ├── policies.json             # firefox enterprise policy used by the above
│   ├── installFonts.sh           # Noto, Font Awesome, JetBrainsMono Nerd Font
│   ├── terminalRedTheme.sh       # Catppuccin Red xfce4-terminal colors, optional Alacritty/Kitty
│   ├── terminalButterbash.sh     # ButterBash + XFCE-specific shell additions
│   ├── fastfetchConfig.sh        # fastfetch + your curated config presets
│   ├── usefulApps.sh             # base tools, Python/data-science stack, Geany, VLC
│   ├── desktopEssentials.sh      # Flatpak, printing, GParted, GUFW
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
- **`terminalRedTheme.sh`'s Alacritty config is now version-aware.**
  Alacritty changed its config syntax at 0.14 (`[terminal].shell` +
  `[general].import` are unrecognized before that). Debian/Devuan point
  releases ship different Alacritty versions, so the script now checks the
  installed version and rewrites the two syntax-sensitive keys to their
  pre-0.14 form when needed, the same compatibility trick
  [dougburks/ohmydebn](https://github.com/dougburks/ohmydebn) uses for the
  same problem — one config, both syntaxes, instead of two configs to keep
  in sync.

- **New `picomSetup.sh`.** Adds "a little bit of animation" the way that
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

**`terminalRedTheme.sh` is new too** — recolors `xfce4-terminal` to
match (Catppuccin Mocha backgrounds, Red cursor/accent, official
Catppuccin 16-color ANSI mapping), and can optionally install
Alacritty and/or Kitty with the same palette if you'd rather have a
GPU-accelerated terminal — including switching XFCE's default
terminal emulator to one of them while leaving `xfce4-terminal`
installed as a fallback. This runs before `terminalButterbash.sh` on
purpose: this script is about the terminal's colors, the other is
about the shell running inside it.

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
