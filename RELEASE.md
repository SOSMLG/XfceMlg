# xfcemlg — Release Notes

Tag a release with: `git tag -a "v$(cat VERSION)" -m "v$(cat VERSION)" && git push --tags`

## 0.8.2 — Self-update, login health, and a runtime test tier

0.8.2 is the closing release: after the 0.8.1 freeze, the toolkit can now
update itself, chips in a silent login health check that only speaks up when
something is wrong, gains a machine-readable verification reporter, and gets
a brand-new test tier that runs the toolkit for real inside a Devuan chroot —
the failure class that static lint and sandboxed units cannot see (the class
that shipped two broken steps in 0.8.0). Everything stays non-interactive:
`--full`/`install.sh` remain zero-keypress.

### What's New
- **Toolkit self-update** (`configs/bin/xfcemlg`, deployed by 24-power-user):
  `xfcemlg selfupdate` compares the installed version against the latest
  GitHub release and applies it automatically with an unattended `install.sh`
  run; `--check` reports only. Exit 2 never claims "up to date" when an
  update couldn't be checked.
- **Login-time health check**: 24-power-user.sh now autostarts
  `xfcemlg-health --quiet` at login — silent on success, notifies only on
  problems — joining the battery/thermal guards that already autostart.
- **`verifySetup.sh --json`**: one machine-readable JSON object
  (`passed/failed/warned` + `checks[]`) as the final line, same exit-code
  contract — so the end-state audit can gate scripts.
- **Tier-4 runtime tests** (`make check-live`, new `tests/live/run.sh`):
  opt-in — bootstraps a real Devuan excalibur chroot and runs a curated,
  headless-safe step slice as a normal user with `permit nopass` doas. This
  is the tier that exercises real apt installs, `run.sh` orchestration, doas
  escalation and file deploys — the failure class static lint and sandboxed
  units cannot see (the class that shipped two broken steps in 0.8.0).
- **`docs/TROUBLESHOOTING.md`**: a run-book of the real failure modes —
  theme-fetch hashes, DM races, polkit duplicates, debconf, apt components,
  and the health/verify exit-code contracts.

## 0.8.1 — The run-day release

0.8.1 is the release meant to be taken to a fresh ThinkPad and run with one
command. The theme fetch is pinned to immutable commits, installs are fully
unattended with no keypresses, every optional step is defaulted or guarded so
`--full` is actually safe to run, and the claims the README makes are backed
by a widening unit-test tier. It closes the last gap the 0.8.0
de-integration left: the vendored butterbash framework was removed with
nothing in its place. Step 18 is now `18-shell-config.sh` and does two jobs —
it still retires butterbash leftovers, and it deploys the toolkit's own shell
config, written from scratch: aliases, a Nerd-Font two-line prompt in the
Darkmatter palette, and fzf/zoxide/keybind hooks that only activate when
those tools are installed. No third-party framework is vendored; fzf and
zoxide load their own distro-shipped integration files.

### What's New
- **18-shell-config.sh** (was `18-shell-reset.sh`): keeps the retirement
  audit, then deploys `configs/bash/` (rc loader + aliases + prompt + hooks)
  to `~/.config/xfcemlg/bash/` with a guarded, append-only `xfcemlg-shell`
  block in `~/.bashrc`. `deploy_seed_file` discipline: user edits are the
  truth and are never clobbered; re-runs are idempotent.
- **Prompt**: pure-bash two-line PS1, Darkmatter palette, Nerd Font glyphs
  (JetBrainsMono Nerd Font from 17-fonts; `XFCONF_PLAIN_PROMPT=1` for
  glyph-free), git branch + dirty marker, last-command exit status, trimmed
  cwd.
- **Aliases**: navigation, eza ls-family with ls fallback, file safety
  (non-root), `extract()`, `term`/`screenshot`/`update-check`/`menu`,
  git shortcuts.
- **Hooks**: fzf key-bindings/completion + Darkmatter `FZF_DEFAULT_OPTS`
  when fzf is installed, `zoxide init bash` when zoxide is present, PgUp/PgDn
  history search.
- **CLI ergonomics packages** (bat, eza, fzf, zoxide, ripgrep, ncdu, tree,
  unar) are installed unconditionally by the step — the README's "CLI stack"
  claim is a promise the step now keeps (btop stays with 19-fastfetch.sh).
- **52-skel-export.sh** exports `~/.config/xfcemlg/bash` and appends the
  same guarded hook to `/etc/skel/.bashrc`, so fresh accounts start with the
  config too.
- **Native-over-Flatpak Heroic** (`44-gaming.sh`, new lib
  `lib/gaming-flatpak.sh`): when the toolkit's native Heroic .deb is
  installed but a Flatpak copy also exists, the step offers to purge the
  Flatpak (a duplicate app + re-downloadable runtimes). Default N, so
  `--full` and `--yes` never auto-fire it; never offered when the native
  Heroic is missing. New unit tier: `tests/unit/test-gaming-flatpak.sh`.
- `make check` + `make release-preflight` stay green; new unit tier:
  `tests/unit/test-shell-config.sh` (step end-to-end in a scratch HOME,
  deploy idempotency, interactive/non-interactive behaviour).
- **Zero-keypress, debconf-proof installs**: `install.sh` exports
  `DEBIAN_FRONTEND=noninteractive` and `install_pkgs` passes
  `--force-confdef/--force-confold`, so a scripted run never hangs on a
  config prompt and never clobbers an admin's edited conffiles.
- **ThinkPad extras default-on** (`13-hardware.sh`): thinkfan and powertop
  now install automatically under `--full`; the other guarded steps
  (unattended security updates, PhotoGIMP Flatpak) stay default-N opt-ins.
- **Single polkit auth agent** (`10-xfce-core.sh` + new lib guard + new
  `tests/unit/test-polkit-guard.sh`): polkitd accepts exactly one agent per
  subject, so foreign agents (lxpolkit, mate-polkit, …) that hand-built
  installs commonly stack next to xfce-polkit are masked with user-level
  `Hidden=true` overrides — package files are never touched, so the fix
  survives upgrades, and `verifySetup.sh` now asserts the single-agent state.
- **Repo hygiene**: CI (`.github/workflows/check.yml`) runs the test suite +
  release-preflight on push/PR, a fast `make hooks` / `.githooks/pre-commit`
  lint hook guards every commit, and `.gitattributes`/`.editorconfig` pin
  LF/tab conventions.

## 0.8.0 — De-branded, de-integrated, and the long-run hardening tier

0.8.0 is the recovery release: this repository absorbed the tree of another
project early in its life, and every trace of that other project — its names,
its vendored parts, its false claims, and the plausible but wrong advice that
came with them — is now out. On top of that, seven long-run maintenance gaps
are closed with a new hardening tier: a scheduled fstrim, SMART health, apt
archive upkeep, aged Trash/`~/.cache` trims, tmpfiles drop-ins, stale xfwm4
window-state pruning, and a one-command read-only end-state health reporter.

Delivered as **0.8.0**, not 0.7.1, because half of the changes are breaking
by design: the namespace is renamed, the committed config paths moved, one
whole step was retired, and the theme fetch now pins immutable commits.

### De-branding and de-integration (breaking)

- **The namespace is now `XMLG_` / `xfcemlg`, everywhere.** The `DEBSWAY*`
  prefix (the parent project's name), the `DEVX_` prefix, `devuan-xfce-setup`
  paths, the vendored `butterbash` tree, the Catppuccin palette, and the
  "ohmydebn-style" test-harness claim are gone. `run.sh` prepares the rename
  live: old on-disk paths (`~/.config/devuan-xfce-setup`, the apt component
  snippet, `/usr/share/devuan-xfce-assets` …) move to their `xfcemlg`
  equivalents when present, content-preserving, never clobbering — an upgrade
  finds its state where it left it. Two guards now keep the lineage out,
  including from a stale-allowlist rotation (C16, C17 in
  `tests/consistency.sh`).
- **The vendored `butterbash` prompt framework is removed** (12 files,
  ~56 KB, GPL-2.0 code under a claim of MIT). Step 18 is now
  `18-shell-reset.sh`, a retirement audit that installs nothing. `docs/
  PROVENANCE.md` records each integration that was retired and where it went.
- **The false ohmydebn affiliation is corrected.** `scripts/34-opencode-agent.sh`
  previously claimed to be "cherry-picked wholesale" from another toolkit;
  the file was rewritten from first principles on this repo, the skill file
  was renamed to `xfcemlg-SKILL.md`, and the test suite wording dropped the
  foreign label.

### Long-run hardening tier (five in 53-longrun.sh, one health reporter, one fwupd job)

1. **fstrim weekly** — a one-time pass plus a `/etc/cron.d` job (marker-grep
   idempotent install, the step-24 discipline). `fstrim` lives in
   `/usr/sbin` and the job calls it absolutely; the `/etc/fstrim` allowlist is
   honoured, with an explicit fstype test as fallback.
2. **SMART** — `smartmontools` installed, a one-time `smartctl -H -A` per
   whole disk, the verdict parsed from the tool's own words.
3. **apt archive upkeep** — a measured sweep (this machine: 1692 `.deb`,
   1.5 GB), a `99xfcemlg-autoclean` `apt.conf.d` key wired into the apt
   scheduler that already runs daily, and a *user-opted* one-time autoclean.
   Zero new schedulers.
4. **Aged Trash + `~/.cache` trim** — bounded, top-level, age-limited; a
   running app's cache tree is never recursed into.
5. **tmpfiles drop-ins** — `e`-type rules for the toolkit's own litter only,
   with the honest disclosure that this box has no `systemd-tmpfiles` to run
   them (the §4 trims are what actually reclaim here; the drop-ins are
   forward-compatible configuration).
6. **Stale `xfwm4-*.state` pruning** — only files *older* than the threshold
   *and* dead are removed. The liveness gate proves the X connection first,
   because a missing `DISPLAY` makes `xdotool` exit exactly like a dead
   window — without the gate, a cron run could delete live session state.
7. **`xfcemlg-health`** — a one-command, read-only end-state report:
   `verifySetup.sh` result, dual-display-manager detection (reads the
   `/etc/runlevels/*/` symlinks, not `rc-update show` padding), live-systemd
   detection, service states via `rc-status`, disk space *and* inodes, and a
   notification only when something is wrong. Exit contract 0 / 1 / 2
   (tooling problem, never a silent pass — a bare `env -i` crash in
   `verifySetup.sh` that would have shown up as "fine" is now exit 2 and
   the `USER`-unset crash itself is fixed in `common.sh`). `--quiet` for cron.
- **fwupd metadata refresh** — fwupd ships only systemd units, so
  `fwupd-refresh.timer` is inert under OpenRC and `/var/lib/fwupd/metadata/`
  stays empty, making `fwupdmgr get-updates` a confident `no updates` on a
  machine that never asked. A `cron.daily` job (weekly download throttle,
  daily cheap check) refreshes LVFS metadata only, never flashes firmware, and
  reports `unknown` rather than `no updates` when the output is unrecognised —
  1.9.x has no `get-count`, and its prose output parses into false zeros.

Everything that deletes is behind `ask_no_full` (default **No**, ignoring
`XMLG_FULL`), and the whole step proves zero destructive changes under
`XMLG_ASSUME_YES=1 XMLG_FULL=1` by snapshotting user crontab, `/etc/cron.d`,
Trash, apt cache and xfwm4 state before/after.

### Fixes (each verified against its failure mode)

- **Suspend never ran after suspend.** The bundled `xfce-suspend` branched on
  `command -v pm-suspend`, but pm-utils is not in excalibur at all — the
  branch was dead and the fallback was a typo. Now: `xfce4-session-logout
  --suspend` (elogind D-Bus) with a `busctl` fallback, and a resume hook
  deployed to `/etc/elogind/system-sleep/` (the only scan path elogind reads)
  that runs `tlp resume`. The help text no longer claims busctl comes from
  "package: systemd" — it ships in elogind, and systemd is not installed.
- **The lid action was inverted.** LOCK_SCREEN (3) was written for battery,
  NOTHING (4) for AC; live settings therefore *never* suspended on battery and
  *always* blanked on AC. Fixed to SUSPEND / NOTHING per the enum, mirrored in
  the seed XML, with an allowlist guard (C15) against both the dead name
  (`brightness-on-*`) and the argument-of-plausibility (the settings GUI's
  widget id shares the name, so a substring search cannot see it).
- **TLP's battery threshold could not raise a user's START**, and nothing
  reported whether the *hardware* accepted the configured cap (this box: EC
  ignored 60 and booted at 80/80). Writes now respect a lower START, and the
  step reads the effect back from sysfs instead of assuming it.
- **`pcie_aspm=force` and `runtime_pm=force=auto` removed from GRUB** — TLP
  owns that policy; the kernel flags are what make the two fight.
- **Seeds stopped clobbering.** The theme step overwrote hand-edited files.
  `deploy_seed_file()` stamps every deployed seed with its sha256 and
  distinguishes four cases: install / no-op / safe in-place update / refuse
  and back the user's edit up as `*.user.<ts>` — 11 new unit assertions.
- **Two display managers.** `dm_enabled_runlevel()` reads the runlevel
  symlinks and lightdm is the single allowed owner of the console.
- **Three silent data-loss paths** in debloat/VSCodium/first-run (a forced
  purge, an overwritten onboarding file, a rewritten wizard) now back up and
  ask on default-No.
- **A `set -u` crash in `common.sh`** that made every script die at source
  time with USER unset (scrubbed cron/CI environments) and made
  `verifySetup.sh` produce no verdict at all.
- **The package extractor harvested English words.** `log_info "Run:
  apt-get install smartmontools (then re-run …)"` produced four "package not
  found" errors for `re-run`, `this`, `for`, `the`. Quote-parity detection
  now distinguishes prose from command position; verification rose from 155
  to 167 real packages, zero non-packages.

### Known issues (0.8.0)

- **`systemd-tmpfiles` does not exist on Devuan excalibur** and `systemd` is
  deliberately not installed, so the §5 tmpfiles drop-ins are inert text on a
  live install. That is disclosed in the step's output and in the drop-in
  comments; the actual reclaim comes from the script's own bounded trims. If a
  tmpfiles runner ever appears, the drop-ins activate with no reinstall.
- **`xfcemlg-health` wants the source checkout.** `verifySetup.sh` is not
  deployed by 24-power-user.sh, so the deployed reporter is pointed at the
  checkout and *says which copy it used*; with no checkout reachable it exits
  2 (tooling problem) instead of reporting success. There is no silent green.
- **The live box this release was tuned against still has two DMs enabled
  (lightdm and greetd racing for the console)**, a legacy
  `# devuan-xfce-setup: update notifier` crontab marker, and state under the
  old `~/.local/state/devuan-xfce-setup/`. Those are live-machine conditions,
  deliberately out of scope for the repo; the health reporter surfaces them
  and the migration step moves the state when the toolkit next runs.
- **fwupd refresh is silent to the user.** It refreshes metadata and writes
  `/var/log/xfcemlg-fwupd.log`, but no notification is raised — a pending
  firmware update is seen when the log is read or `fwupdmgr get-updates` runs.
- **TLP AC power policy is left at the driver-appropriate stock defaults.**
  The battery path is tuned; changing AC behaviour without a driver-level
  reason would be guessing, so it was deliberately not touched.
- **`docs/BUILDING.md` documents a `blend/` ISO tree that is not in this
  repository** (it never was — `git log --diff-filter=D -- blend/` is empty).
  It is kept as the specification upstream of the ISO, with a status banner
  pointing at `make pkg-deb` as the thing a clone can actually build.

### Upgrading from 0.7.x

`run.sh` migrates your on-disk `devuan-xfce-setup*` paths the first time it
runs — nothing is deleted, and nothing is moved without a backup-able write.
The theme/icon fetch pins new commit SHAs; the recorded checksums changed only
because the URL changed (the extracted tree is byte-identical) and codeload
zeroes gzip mtime, so a one-time re-download is expected. Any `--only` name
you used before still resolves through the step alias table, and any script
referencing the old prefixes finds the legacy-path migration instead of a
typo.

## 0.7.0 — Themes/icons fetched at install (bundles deleted), rofi removed

The delivery model for the rice changes: the ~29 MB of bundled themes and
icons no longer live in git. `21-theme.sh` now fetches the Darkmatter GTK
theme from `stevedylandev/darkmatter-linux` and the Zafiro icons from
`zayronxio/Zafiro-icons` at install time, then applies the same tweaks that
used to be applied by hand in 0.6.0 — all automated by
`scripts/lib/darkmatter-fetch.sh`. Rofi and its config are gone entirely;
stock `xfce4-appfinder` owns Super+space.

### What's New
- **No more bundles.** `configs/themes/` (7.7 MB), `configs/icons/` (21 MB)
  and `configs/rofi/` are deleted. The repo payload drops ~29 MB (79 → 51 MB)
  and so does the content deb.
- **`scripts/lib/darkmatter-fetch.sh`** — the fetch+build+tweak engine:
  - fetches `darkmatter-linux` (codeload tarball, sha256-pinned by default,
    overridable via `DM_THEME_SHA256` / `DM_ICONS_SHA256`; `DM_SKIP_FETCH=1`
    reuses a cached fetch for offline runs);
  - assembles the three variants (`Darkmatter`, `Darkmatter-hdpi`,
    `Darkmatter-xhdpi`) from the upstream root `gtk-3.0`/`gtk-4.0`/`assets`
    plus its `xfwm4/Darkmatter{,-hdpi,-xhdpi}/xfwm4` decorations;
  - rewrites `index.theme` per variant
    (`Name=<variant>`, `IconTheme=Zafiro-icons-Dark`);
  - remaps the upstream orange `#e78a53` → red `#e75353` in every text
    asset (css/scss/svg) via sed and every PNG pixel via ImageMagick;
  - builds `Zafiro-icons-Dark` from the upstream `Dark/` dir, dropping the
    heavy `apps/scalable` SVG subtree (1553 files) + `previews/`.
- **`21-theme.sh`** reworked: step 2 fetches+builds+deploys the themes to
  `/usr/share/themes/` (purging earlier Darkmatter variants), step 4 does
  the same for the icons (Papirus-Dark fallback if the fetch fails), the
  rofi bonus block is removed, and `imagemagick` joins the theme deps.
- **Full unit coverage of the pipeline** — `tests/unit/test-darkmatter.sh`
  builds variants + runs the remap against an offline fixture (a 1x1
  `#e78a53` PNG included as base64), asserts the orange is gone everywhere,
  the PNG pixels changed, and the icon trim (no `apps/scalable`), still with
  no root / no apt / no X / no network.
- Dependencies of the fetch step: `curl` and `imagemagick` (both already
  used elsewhere in the toolkit).

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
  leftovers (`~/.config/xfcemlg/lib|themes|current`,
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
- **`xfce-scratch` — drop-down terminal** (`configs/bin/xfce-scratch`,
  Super+grave): one dedicated undecorated alacritty (class `xfce-ddown`,
  Darkmatter-themed), docked top-center at 60%×45% on every workspace,
  toggled via windowunmap/map so it never occupies the taskbar. Pure
  xdotool — no new packages. Deployed by `24-power-user.sh`.
- **tmux auto-attach** — `configs/tmux.conf` (Ctrl+b, base-index 1, vi keys,
  mouse, Darkmatter status bar) deployed by `18-butterbash.sh`, and
  alacritty now runs `tmux new -A -s main` on launch (plain bash fallback),
  so every terminal — dropdown included — is a tmux client. `18` also
  installs git-delta and wires it as the git pager (decorations,
  line-numbers, Catppuccin-Mocha) without clobbering an existing
  `core.pager`.
- **Battery + thermal watchdogs** — `xfce-battery-warn` / `xfce-temp-warn`
  (flock-guarded daemons reading sysfs, no acpi dependency): one dunst
  notification per threshold crossing (battery 20/10/5%, cpu 80/90°C),
  critical is persistent, warnings re-arm on recharge/cool-down; autostarted
  by `24-power-user.sh`; sensors/interval/lock env-overridable for headless
  tests.
- **Hardened `xfce-lock`** — idempotent (skips when `light-locker-command
  -q` already reports active), prefers light-locker directly, pauses dunst
  and clears the clipboard while locked, restores both on unlock.
- **Cross-WM Super set** (`23-input-fix.sh`): `Super+t` terminal,
  `Super+e/f/w` focus-or-launch via new `xfce-raise`,
  `Super+Shift+Left/Right` move window between workspaces, `Super+grave`
  dropdown, `Super+n` / `Shift+Super+n` dunst mute / re-show-last,
  `XF86Sleep` suspend (`xfce-suspend`), Print=full / Super+Print=area /
  Super+Ctrl+Print=OBS-record, CapsLock→Escape (stored in the
  keyboard-layout channel so xfsettingsd persists it), touchpad natural
  scroll (libinput, persisted via a guarded session-xinitrc block).
- **Thunar deep pack** — `configs/Thunar/uca.xml` grows to 7 actions
  (Open Terminal Here, Open as Root, Open in VSCodium, Play with VLC, Play
  Folder with VLC, Copy Full Path, Make Executable); `21-theme.sh` seeds
  Thunar view defaults create-only so per-folder settings and user choices
  are never clobbered.
- **VSCodium defaults + VLC dark** — `40-vscodium.sh` merges additive
  Darkmatter editor defaults (Nerd Font, minimap off, bracket pairs, trim
  whitespace — only keys the user hasn't set) and seeds keybindings
  (ctrl+alt+t new terminal, ctrl+alt+b sidebar) only when none exist. VLC
  installs alongside `qt5-gtk-platformtheme` and the session xinitrc exports
  `QT_QPA_PLATFORMTHEME=gtk3` (self-guarding on the plugin), so VLC's Qt
  chrome renders in Darkmatter; the Thunar "Play with VLC" actions pair
  with it.
- **Autostart hygiene** — duplicate user-vs-system `.desktop` entries are
  deduplicated; both watchdog daemons are flock-guarded so a double spawn
  can never run twice.
- **`verifySetup.sh`** now guards dunst (Darkmatter config) and alacritty
  (default terminal helper).

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
  writes `~/.cache/xfcemlg-assets/picker.colors` (bg0/bg1/bg3/fg0)
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
  `xfcemlg-assets_0.5.0_all.deb` (~6 MB) shipping the full versioned
  asset bundle under `/usr/share/xfcemlg-assets/` when installed.
  `make check-deb` runs `dpkg-deb` info + lintian with zero errors.
  `packages/xfcemlg-assets/` holds the committed DEBIAN metadata;
  the ~36 MB `configs/` (incl. the bundled Darkmatter themes + Zafiro
  icons) is staged from the repo at build time.
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
- **Live ISO blend**: `blend/xfcemlg-thinkpad/` (build-here.sh,
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
- Automatic: `ask()` answers Yes under `XMLG_FULL=1` (`install.sh`
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
