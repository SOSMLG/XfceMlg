#!/usr/bin/env bash
# tests/live/run.sh — tier 4: chroot runtime integration tests (opt-in).
#
# Bootstraps a real Devuan excalibur minbase chroot and runs a curated,
# headless-safe slice of the toolkit inside it EXACTLY the way run-day does:
# as a normal user with a `permit nopass` doas rule. This is the one tier
# that exercises real apt installs, real run.sh orchestration, real
# priv()/doas escalation and real file deploys — the failure class static
# lint and sandboxed units cannot see (0.8.0 shipped two steps that only
# failed on a real first run).
#
#   exit 0  every step ran and every assertion passed
#   exit 1  a step or assertion failed — a real toolkit bug
#   exit 2  could not run at all (not root / no debootstrap / no network /
#           bad mirror) — never mistaken for a pass
#
# Not part of `make check` (which must stay read-only, no root). Explicit:
#   doas bash tests/live/run.sh        (root required)
#
# Overrides:
#   XMLG_LIVE_SUITE=excalibur                devuan suite codename
#   XMLG_LIVE_MIRROR=http://deb.devuan.org/merged
#   XMLG_LIVE_STEPS="10 12 17 18 24 32 51"   curated headless-safe set
#   XMLG_LIVE_KEEP=1                         keep the chroot on failure
set -uo pipefail

LIVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE="${XMLG_LIVE_SUITE:-excalibur}"
MIRROR="${XMLG_LIVE_MIRROR:-http://deb.devuan.org/merged}"
STEPS="${XMLG_LIVE_STEPS:-10 12 17 18 24 32 51}"

say() { printf '[check-live] %s\n' "$*"; }
fail2() {
	say "could not run: $*" >&2
	exit 2
}

# --- can we even run? --------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
	fail2 "must run as root (maintainer box: 'doas bash tests/live/run.sh')"
fi
for tool in debootstrap chroot tar timeout; do
	command -v "$tool" >/dev/null 2>&1 || fail2 "missing tool: $tool (apt-get install -y debootstrap)"
done

CHROOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xfcemlg-live.XXXXXX")"
cleanup() {
	umount "$CHROOT_DIR/proc" 2>/dev/null || true
	umount "$CHROOT_DIR/dev" 2>/dev/null || true
	if [ "${XMLG_LIVE_KEEP:-0}" = 1 ]; then
		say "keeping chroot at $CHROOT_DIR (XMLG_LIVE_KEEP=1)"
	else
		rm -rf "$CHROOT_DIR"
	fi
}
trap cleanup EXIT

# --- bootstrap ---------------------------------------------------------------
say "debootstrap $SUITE from $MIRROR (this takes a few minutes)..."
debootstrap --variant=minbase --include=doas,login "$SUITE" "$CHROOT_DIR" "$MIRROR" \
	>"$CHROOT_DIR/debootstrap.log" 2>&1 || fail2 "debootstrap failed — see $CHROOT_DIR/debootstrap.log"
say "bootstrap ok."

mount -t proc proc "$CHROOT_DIR/proc" || fail2 "cannot mount /proc"
mount --bind /dev "$CHROOT_DIR/dev" 2>/dev/null || true
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

# apt needs a sources file to refresh lists (run.sh does apt-get update).
{
	echo "deb $MIRROR $SUITE main contrib non-free-firmware"
} >"$CHROOT_DIR/etc/apt/sources.list"

# --- chroot helpers ----------------------------------------------------------
in_chroot() { chroot "$CHROOT_DIR" /bin/bash -c "$1"; }
as_tester() { chroot "$CHROOT_DIR" /bin/su -s /bin/bash tester -c "$1"; }

in_chroot "useradd -m -s /bin/bash tester" || fail2 "useradd tester"
printf 'permit nopass tester as root\n' >"$CHROOT_DIR/etc/doas.conf"

# ship the repo in, tester-owned (no .git — but scripts/, configs/, run.sh all go)
say "copying repo into chroot..."
mkdir -p "$CHROOT_DIR/opt/xfcemlg"
tar --exclude=.git -C "$LIVE_ROOT" -cf - . |
	tar -C "$CHROOT_DIR/opt/xfcemlg" -xf - || fail2 "repo copy failed"
in_chroot "chown -R tester:tester /opt/xfcemlg"
in_chroot "chmod 0755 /opt/xfcemlg/install.sh /opt/xfcemlg/run.sh 2>/dev/null" || true

# --- run the curated steps as tester, with doas, exactly like run-day --------
fail=0
for step in $STEPS; do
	say "step $step ..."
	if ! as_tester "cd /opt/xfcemlg && timeout 3600 env XMLG_ASSUME_YES=1 DEBIAN_FRONTEND=noninteractive bash run.sh --only $step --yes"; then
		say "step $step FAILED (rc=$?)" >&2
		fail=1
		break
	fi
	say "step $step ok."
done

# --- smoke: run.sh --list parses step headers --------------------------------
if [ "$fail" -eq 0 ] && ! as_tester "cd /opt/xfcemlg && bash run.sh --list >/dev/null"; then
	say "run.sh --list FAILED" >&2
	fail=1
else
	[ "$fail" -eq 0 ] && say "run.sh --list ok."
fi

# --- assertions (guarded: never run after a step already failed) -------------
assert_pkg() {
	if in_chroot "dpkg-query -W -f='\${Status}' '$1' 2>/dev/null | grep -q 'install ok installed'"; then
		say "  [ok] package: $1"
	else
		say "  [FAIL] package missing: $1" >&2
		fail=1
	fi
}
assert_not_pkg() {
	if in_chroot "dpkg-query -W -f='\${Status}' '$1' 2>/dev/null | grep -q 'install ok installed'"; then
		say "  [FAIL] package should NOT be installed: $1" >&2
		fail=1
	else
		say "  [ok] absent: $1"
	fi
}
assert_home() { # assert_home <tester-relative path>
	if as_tester "test -e \"\$HOME/$1\""; then
		say "  [ok] ~/$1"
	else
		say "  [FAIL] ~/$1 missing" >&2
		fail=1
	fi
}
assert_bin() { # assert_bin <name>
	if as_tester "test -x \"\$HOME/.local/bin/$1\""; then
		say "  [ok] bin: $1"
	else
		say "  [FAIL] bin missing: $1" >&2
		fail=1
	fi
}

if [ "$fail" -eq 0 ]; then
	# 10 → lean XFCE core, no SLiM/tasksel
	assert_pkg xfce4-session
	assert_pkg xfwm4
	assert_pkg lightdm
	assert_pkg xfce-polkit
	assert_not_pkg slim
	assert_not_pkg task-xfce-desktop
	# 12 → user groups
	if as_tester "id -nG | grep -qw video"; then
		say "  [ok] tester in group video"
	else
		say "  [FAIL] tester not in group video" >&2
		fail=1
	fi
	# 17 → fonts
	assert_pkg fonts-noto-core
	# 18 → shell config in tester's HOME
	assert_home ".config/xfcemlg/bash"
	# 24 → power-user bins + login health autostart + cron notifier
	for b in xfcemlg xfcemlg-health xfce-menu xfce-update-check; do
		assert_bin "$b"
	done
	assert_home ".config/autostart/xfcemlg-health.desktop"
	if as_tester "crontab -l 2>/dev/null | grep -q xfce-update-check"; then
		say "  [ok] update-notifier cron"
	else
		say "  [FAIL] update-notifier cron missing" >&2
		fail=1
	fi
	if as_tester "\$HOME/.local/bin/xfcemlg help >/dev/null 2>&1"; then
		say "  [ok] xfcemlg help"
	else
		say "  [FAIL] xfcemlg help failed" >&2
		fail=1
	fi
	# 32 → chrony
	assert_pkg chrony
	# 51 → timestamped HOME backup
	if as_tester "ls \"\$HOME\"/xfce-config-backup-*.tar.gz >/dev/null 2>&1"; then
		say "  [ok] config backup taken"
	else
		say "  [FAIL] no xfce-config-backup tarball" >&2
		fail=1
	fi
fi

if [ "$fail" -eq 0 ]; then
	say "ALL GREEN (steps: $STEPS)"
	exit 0
fi
say "FAILURES above — keep the chroot for debugging with XMLG_LIVE_KEEP=1" >&2
exit 1
