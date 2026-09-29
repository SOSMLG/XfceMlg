# xfcemlg — Troubleshooting / Run-book

The real failure modes this toolkit has hit or defends against, and what to
do about each. Grounded in the actual code and messages — read the relevant
script before guessing.

## Install-time

### The theme fetch fails with a sha256 mismatch
`scripts/lib/darkmatter-fetch.sh` pins Darkmatter-linux `822d163c` and
Zafiro-icons `5c7f38ca` at **immutable commit SHAs** and verifies each
tarball against `DM_THEME_SHA256` / `DM_ICONS_SHA256`. A mismatch means the
archive changed (either the commit moved — it can't, it's immutable — or the
download was corrupted/truncated).

- Re-run the step; a transient download is usually the cause.
- The fetched archives are cached in `~/.cache/xfcemlg/`:
  - `DM_SKIP_FETCH=1 bash scripts/21-theme.sh` — reuse the cache as-is.
  - Delete the cache dir to force a fresh fetch.
- If the *hash itself* is stale (upstream repacked), update the two
  `DM_*_SHA256` values in `scripts/lib/darkmatter-fetch.sh` together with the
  pinned commit — the consistency guard C18 keeps each URL and its hash from
  drifting apart, and both must change in the same commit.

### Two login screens / display-manager race
Exactly **one** DM may be enabled. `10-xfce-core.sh` enables LightDM, purges
SLiM and offers to disable any rival (`greetd`, `sddm`) found in a boot
runlevel. If you still see two greeters:

```sh
doas rc-update del greetd default   # whichever rival you have
```

### Polkit: "an authentication agent already exists for the given subject"
polkitd accepts exactly **one** auth agent per subject. Hand-built installs
often stack lxpolkit / polkit-mate / polkit-gnome next to `xfce-polkit`.
`10-xfce-core.sh` now masks every foreign agent with a user-level
`Hidden=true` override in `~/.config/autostart/` — it never edits package
files, so the fix survives upgrades, and deleting the mask undoes it:

```sh
ls ~/.config/autostart/            # the masked *.desktop files live here
rm ~/.config/autostart/lxpolkit.desktop   # to unmask, remove the file
```

`scripts/verifySetup.sh` reports "single polkit agent" FAIL with the extra
agents listed; re-run `10-xfce-core.sh` to re-mask.

### The run hangs on a debconf / config prompt
`install.sh` exports `DEBIAN_FRONTEND=noninteractive` and `install_pkgs`
passes `--force-confdef --force-confold`, so nothing should ever prompt.
If you're running steps manually without those env vars:

```sh
DEBIAN_FRONTEND=noninteractive bash scripts/<step>.sh
```

### apt: "The repository ... does not have a Release file" / component missing
Some packages need `contrib`/`non-free`/`non-free-firmware` components that a
minimal Devuan install doesn't ship with. `ensure_repo_component()` (in
`scripts/lib/common.sh`, called by `11-backports.sh`) adds an
`xfcemlg-<component>.sources` snippet on demand; the repo is Devuan Excalibur
= Debian trixie-compatible. If a package still isn't found, check
`/etc/apt/sources.list.d/xfcemlg-*.sources` exists, then `apt update`.

### A step fails mid-run
Every step is idempotent — re-run it. State:

- `~/.local/state/xfcemlg/last-run.log` — what ran, in order.
- Destructive writes are preceded by `*.bak.<timestamp>` backups; `scripts/`
  never force-purges blindly (`is_installed` is checked first).
- `scripts/51-backup.sh` snapshots HOME config to
  `~/xfce-config-backup-<stamp>.tar.gz` (restore via `scripts/51-backup.sh
  --restore`).

## Post-install / verification

### `verifySetup.sh` exit codes and `--json`
`report` lines are `PASS/FAIL/WARN`; the script exits `1` if any check
failed. For scripting, `verifySetup.sh --json` prints one JSON object as its
final line (`passed/failed/warned` plus a `checks[]` array with
`name/status/detail`) with the same exit-code contract.

### `xfcemlg-health` exit codes (0 / 1 / 2)
Deployed by `24-power-user.sh` and run from cron (hourly 09:00 + 18:00) and
at login (`~/.config/autostart/xfcemlg-health.desktop`):

- `0` — every check that could run passed.
- `1` — a real machine fault (fix the machine, then `xfcemlg-health
  --verbose` to see details; `--no-notify` for headless runs).
- `2` — the check itself couldn't run: no `verifySetup.sh` found
  (`XFCEMLG_VERIFY` / `XFCEMLG_REPO` point it at one), no parseable verdict,
  a missing core utility, or another instance held the lock for the whole
  20 s wait. This is deliberately NOT reported as a pass.

Quiet mode (`--quiet`) prints nothing on success — only problems are ever
announced, so cron and login stay silent when the box is healthy.

### Firewall "Everything auto-enables a deny rule" worries
`30-desktop-essentials.sh` installs `ufw` but never auto-enables a deny rule:
the `SSH-safe guard` in the README means enabling is opt-in and defaults to
permit — inspect `/etc/default/ufw` and `ufw status` before changing policy.

## Toolkit self-update

`xfcemlg selfupdate` (deployed by `24-power-user.sh` to `~/.local/bin/`):

- Checks the latest **published** GitHub release (`github.com/SOSMLG/XfceMlg`)
  against the installed version (the `xfcemlg-assets` deb's version, or
  `$XFCEMLG_REPO/VERSION` as fallback), and applies it automatically with an
  unattended `install.sh` run.
- `--check` only reports; `XMLG_SELFUPDATE_NOAPPLY=1` forces the same.
- Exit `2` means the state was not determinable (offline, no release yet,
  no version source) — never "up to date".
- Requires network + `curl`; zero-prompt under your run-day
  `permit nopass` doas rule.

## Developer / testing

### `make check-live` (tier-4 chroot runtime tests)
`tests/live/run.sh` bootstraps a real Devuan excalibur minbase chroot and
runs a curated, headless-safe slice of the toolkit as a normal user with a
`permit nopass tester as root` doas rule — the exact run-day permission
layout. It needs **root + network + `debootstrap`** (`doas apt-get install -y
debootstrap`) and is deliberately not part of `make check`:

```sh
doas bash tests/live/run.sh        # or, as root: make check-live
```

It exits `0` (all green), `1` (a step/assertion failed — a real bug) or `2`
(couldn't run). Overrides: `XMLG_LIVE_SUITE`, `XMLG_LIVE_MIRROR`,
`XMLG_LIVE_STEPS`, `XMLG_LIVE_KEEP=1` (keep the chroot for debugging).
X-dependent steps (theme apply, xfconf, input fix) intentionally stay in the
sandboxed unit tier + the run-day manual pass; the chroot tier covers real
apt installs, `run.sh` orchestration, doas escalation and file deploys.