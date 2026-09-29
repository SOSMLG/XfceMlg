# Provenance

Where the code, assets and ideas in this toolkit come from.

## Self-contained

xfcemlg is a set of post-install shell scripts for Devuan 6 (excalibur) +
XFCE 4.20. As of **0.8.0 it vendors no third-party code**: there is no
copied, forked or patched upstream source tree in git, and the content deb
(`make pkg-deb`) ships only files written here. Everything installed from
the network is downloaded at install time by the script that needs it, is
verified where a digest is available, and stays under its own upstream
licence.

## Retired integrations

| Integration | What it was | Removed | Why |
| --- | --- | --- | --- |
| `butterbash/` | A third-party bash prompt/config framework (JustAGuyLinux, Codeberg) copied wholesale into git: 12 files, 56 767 bytes (88 KiB on disk), carrying its own GPL-2.0 `LICENSE`. Its installer wrote `~/.config/bash/`, replaced `~/.bashrc` and linked `~/.local/bin/{fd,bat}`. | 0.8.0 | Someone else's code, not ours — and the repo had already begun editing the copy in tree (`bashrc.example` carried a VSCodium-specific patch), which is the maintenance and licensing liability vendoring creates. Replaced by nothing at 0.8.0 (the default shell config was deemed sufficient) — but 0.8.1 reverses that: `scripts/18-shell-config.sh` (was `18-shell-reset.sh`, was `18-butterbash.sh`) now both clears what the old step left behind **and** deploys a from-scratch replacement — `configs/bash/` aliases, a Nerd-Font prompt, and fzf/zoxide hooks written for this toolkit, with none of the retired project's code. |
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
