# Building the devuan-xfce-thinkpad live ISO

This blends the toolkit's lean XFCE desktop — plus OpenRC — into a bootable
Devuan 6 (excalibur) **live ISO** using the official
[Devuan live-sdk](https://git.devuan.org/devuan-sdk/live-sdk.git) +
[libdevuansdk](https://git.devuan.org/devuan-sdk/libdevuansdk.git).

What you get:

- Boots to a Darkmatter-themed XFCE desktop (panel seed, Alacritty,
  themed greeter) in a live session
- **OpenRC** init (Devuan's hybrid: sysvinit stays PID1, openrc is the
  service manager — the same transition the Devuan installer performs)
- **Lean core**: no `task-xfce-desktop`/`task-desktop` meta-pack (which drag
  in SLiM + ~200 recommends), everything selected explicitly with
  `--no-install-recommends`
- ThinkPad power stack: TLP with battery thresholds, fwupd, CPU microcode,
  wifi/BT firmware
- Firmware + grub `.debs` staged in `/firmware` so a later
  refractainstaller install is fully offline-capable

## Prerequisites

On the machine doing the build (inside a Devuan/Debian chroot or VM; the
live-sdk uses zsh + sudo + debootstrap):

```sh
apt-get install -y zsh sudo cgpt parted xz-utils xorriso squashfs-tools \
    live-boot live-config-sysvinit syslinux-common dosfstools git
```

The build *user* must be able to `sudo`. You need ~4 GB free disk and a
working internet connection.

## One-command setup

From this repository root:

```sh
bash blend/devuan-xfce-thinkpad/deploy.sh
```

The deploy script:

1. Clones `live-sdk` (and its zuper + libdevuansdk submodules) into `./live-sdk`
2. Links `extra/syslinux → syslinux.excal`
3. Copies the `devuan-xfce-thinkpad` blend into `live-sdk/blends/`
4. Registers it in the `blend_map` inside `live-sdk/sdk`
5. Refreshes the blend's `rootfs-overlay/` from `configs/` (via
   `sync-overlay.sh`) so the ISO carries the current themes/panel/alacritty

## Manual setup (what deploy.sh does, step by step)

```sh
git clone https://git.devuan.org/devuan-sdk/live-sdk.git
cd live-sdk
git submodule update --init --recursive --checkout
ln -s syslinux.excal extra/syslinux                 # pick the excalibur set
cp -r ../blend/devuan-xfce-thinkpad blends/
# register in sdk's blend_map:
#   "devuan-xfce-thinkpad" "$R/blends/devuan-xfce-thinkpad/devuan-xfce-thinkpad.blend"
bash ../blend/devuan-xfce-thinkpad/sync-overlay.sh  # refresh overlay from configs/
```

## Building

```sh
cd live-sdk
zsh -f -c 'source sdk'
load devuan devuan-xfce-thinkpad
build_iso_dist
```

Wait for the bootstrap + package installs + squashfs pass. The finished
hybrid ISO (BIOS + UEFI bootable) lands at:

```
live-sdk/dist/devuan_excalibur_6.1.1_amd64_xfce-thinkpad.iso
live-sdk/dist/devuan_excalibur_6.1.1_amd64_xfce-thinkpad.iso.sha256
```

## Layout of the blend

```
blend/devuan-xfce-thinkpad/
├── config                     # blend-level: arch, mirror, version, MKEFI
├── devuan-xfce-thinkpad.blend # lifecycle: preinst → isolinux → finalize
├── deploy.sh                  # clone live-sdk + register this blend
├── sync-overlay.sh            # copy configs/ → excalibur/rootfs-overlay
└── excalibur/
    ├── config                 # the package set (lean XFCE + OpenRC + TLP)
    ├── rootfs-overlay/        # files rsynced INTO the live rootfs:
    │   ├── home/devuan/...    #   alacritty, panel, fastfetch,
    │   │                      #   redshift.conf  (user session seed)
    │   └── etc/...            #   lightdm greeter, apt auto-upgrades, tlp.d
    ├── isolinux-overlay/      # boot splash (splash.png)
    ├── live-overlay/          # memtest86+ etc.
    └── efi-files/             # UEFI boot glue (built by iso_make_efi)
```

## Tuning

| What | Where |
|------|-------|
| Extra packages | `excalibur/config` → `extra_packages+=(...)` |
| Purged packages | `excalibur/config` → `purge_packages+=(...)` |
| Release codename / version / ISO name | `config` |
| Kernel cmdline / boot menu | `iso_write_isolinux_cfg` + `iso_write_grub_cfg` in the `.blend` |
| In-rootfs post-processing | `blend_finalize` in the `.blend` |
| Darkmatter / panel / terminal / wallpapers | `configs/` (re-run `sync-overlay.sh`) |

To bump to the next release: change `release`/`version`/`image_name` in
`config`, retarget `extra/syslinux`, and move `excalibur/` to
`old-blend-configs/` before creating the new suite dir (see the stock
`devuan-desktop-live/README.releases` for the exact dance).

## Cookbook: value-add the whole toolkit into the ISO

The ISO ships the *applied* desktop (themes, panel, terminal,
wallpapers, greeter). If you also want the toolkit's **scripts** inside the
live system so a user can re-run/adjust anything:

```sh
# from repo root, before building:
mkdir -p blend/devuan-xfce-thinkpad/excalibur/rootfs-overlay/opt/devuan-xfce-setup
cp -r scripts install.sh run.sh VERSION configs \
      blend/devuan-xfce-thinkpad/excalibur/rootfs-overlay/opt/devuan-xfce-setup/
```

Then in the live session: `cd /opt/devuan-xfce-setup && bash run.sh --yes`
re-applies everything as a normal user.

## Notes & Caveats

- **OpenRC** is installed by the blend's `blend_finalize` (`apt-get install
  openrc openrc-shutdown`), which performs the sysvinit→OpenRC hand-off the
  same way the Devuan installer does. `live-config-sysvinit` is kept: its
  init scripts are executed by OpenRC's bootchain without a systemd move.
- live-sdk needs **plain git**, not the web UI — git.devuan.org is behind an
  Anubis anti-bot wall for browsers, but `git clone` works normally.
- First build takes a while (full debootstrap + stage3/stage4). Rebuilds are
  fast: `stage3.cpio.gz`/`stage4.cpio.gz` caches live in
  `live-sdk/tmp/` and are reused when the package set is unchanged. Set
  `CPIO_STAGE4=1` to keep the stage4 cache too.
- Test the ISO with `qemu-system-x86_64 -m 2048 -cdrom dist/*.iso` or write
  it to a USB with GNOME Disks (`Restore Disk Image…`).