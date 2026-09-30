# Provenance

Where the code, assets and ideas in this toolkit come from.

## Self-contained

xfcemlg is a set of post-install shell scripts for Devuan 6 (excalibur) +
XFCE 4.20. It is **almost entirely self-contained** — with one exception,
the vendored shell framework under `configs/butterbash/`, which is a
**verbatim** copy of a third-party GPL-2.0 project, restored in 0.9.0 (see
the table below). Apart from that, there is no copied, forked or patched
upstream *source* tree in git, and the content deb (`make pkg-deb`) ships
only files written here. Everything installed from the network is
downloaded at install time by the script that needs it, is verified where a
digest is available, and stays under its own upstream licence.

## Vendored third-party code

### `configs/butterbash/` — GPL-2.0, restored 0.9.0

A third-party bash prompt/config framework by JustAGuyLinux (Codeberg),
vendored **verbatim**: 12 files, 56 767 bytes, restored from the tree
commit `59c4632` deleted. Every file is byte-identical to that commit
(verified by sha256), so the copy is auditable against upstream rather
than a fork that has drifted.

- **Licence:** GPL-2.0, shipped verbatim as `configs/butterbash/LICENSE`
  and copied to `~/.config/bash/LICENSE` at install time. The MIT licence
  covering the rest of this repository does **not** extend to these files.
  The content deb therefore carries a GPL-2.0 notice — see
  `packages/xfcemlg-assets/usr/share/doc/xfcemlg-assets/copyright`.
- **Installed to:** `~/.config/bash/` (the path upstream's own `bashrc`
  expects), by `scripts/18-shell-config.sh`. `configs/bash/rc.sh` sources
  it *after* the xfcemlg parts, so its prompt and aliases are what the
  user sees — that is the point of shipping it.
- **Never edited in place.** The upstream tree is kept pristine so its
  diffability and licence provenance stay intact. The two defects that
  are specific to *this* machine are corrected in a separate local layer,
  `configs/bash/99-xfcemlg-overrides.sh`, sourced last:
  1. the payload hardcodes bare `sudo` in its apt aliases, against this
     project's doas-first `priv()` policy and non-functional on a
     doas-only system — replaced with an `xfc_priv` helper that prefers
     doas and falls back to sudo;
  2. `alias ports='netstat -tulanp'` depends on `netstat`, gone from
     Debian trixie — the `ss`-based `ports` function is restored.

**History.** Removed in 0.8.0 because it is someone else's code and the
repo had begun editing the copy in tree. 0.8.1 replaced it with
`configs/bash/`, written from scratch. **0.9.0 restores it** at the
owner's request: the framework's feel is wanted back, and the maintainer
accepted the licence obligation rather than reimplementing it. The 0.8.0
objections are recorded here rather than deleted, because the restored
copy still carries the traits that prompted them.

## Retired integrations

| Integration | What it was | Removed | Why |
| --- | --- | --- | --- |

| Catppuccin Mocha | An early colour palette. Its last programmatic use was a btop theme fetch in `19-fastfetch.sh`; a `delta.syntax-theme "Catppuccin Mocha"` value was written by the old step 18. | 0.8.0 | The project settled on the fixed Darkmatter theme (near-black + red). It was a leftover of the earlier palette, not a dependency. |
| Butterbian-XFCE | A live-ISO builder for a XFCE-on-Debian flavour. Studied read-only; its BTRFS/systemd/Calamares parts were deliberately not ported. | never vendored | No code was copied. What was taken were notes: a never-overwrite rule for the first-run wallpaper seeder, a create-if-missing Super-shortcut set, a greeter `user-background = false` fix. Listed for the acknowledgement, not because anything is being taken back. |
| ohmydebn | An earlier post-install toolkit. `scripts/34-opencode-agent.sh` previously claimed to be "cherry-picked wholesale from ohmydebn (MIT)". | 0.8.0 (claim corrected) | **That claim was false** — see below. A false attribution is worse than none. |

### ohmydebn: the corrected claim

`scripts/34-opencode-agent.sh` is a ~150-line reimplementation. It vendors no
upstream payload and copies no upstream file from ohmydebn. The only thing
the two have in common is the idea of an install-then-launch hotkey bound to
a Super key. The MIT acknowledgement is kept because a shared idea warrants
one — but it should be read as: **no code was taken.**

### Darkmatter and Zafiro: not a problem to fix

The Darkmatter GTK/xfwm4 themes and the Zafiro icons are **not vendored and
are not being removed.** They used to sit in git as ~29 MB of binary payload;
as of 0.8.0 they are fetched at install time by
`scripts/lib/darkmatter-fetch.sh` (sha256-pinned codeload tarballs, digests
set in `scripts/21-theme.sh`) and installed by `scripts/21-theme.sh`. The
change is a packaging decision — smaller repo, no drift from upstream — and
not a licensing one. A future reader should not "fix" this.

## Upstream assets fetched at install time

Each is downloaded by the step that needs it and remains under its own
upstream licence. Versions are pinned — sha256 for the Darkmatter
tarballs, upstream release tags for the rest.

- Darkmatter GTK3/GTK4 + xfwm4 themes, Zafiro icons — sha256-pinned.
- JetBrainsMono Nerd Font (`17-fonts.sh`); the Noto and Font Awesome
  families come from APT, not a download here.
- Betterfox (`16-firefox.sh`); the uBlock Origin, search-engine and
  telemetry policies are our own `scripts/policies.json`, not a fetch.
- OpenCode binary (`34-opencode-agent.sh`), PhotoGIMP tarball
  (`43-photogimp.sh`), Steam, Heroic, Vesktop, Telegram (`44`/`45`).
- Flatpak and the Flathub repo (`30-desktop-essentials.sh`), then most
  desktop apps through Flatpak.

## Licence

xfcemlg is MIT licensed (`packages/xfcemlg-assets/usr/share/doc/xfcemlg-assets/copyright`).
Fetched upstream assets keep their own licences; see that file for the
per-directory breakdown.
