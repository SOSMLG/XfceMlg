#!/usr/bin/env python3
"""xfce-update-gui — themed GTK window that runs system updates in a VTE.

Falls back to a plain xfce4-terminal window if VTE is unavailable
(gir1.2-vte-2.91 not installed). Reads palette from picker.colors
(the same file xfce-menu uses), falling back to Darkmatter defaults.
"""
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
try:
    gi.require_version("Vte", "2.91")
    from gi.repository import Vte
    VTE_AVAILABLE = True
except (ValueError, ImportError):
    Vte = None
    VTE_AVAILABLE = False
from gi.repository import Gdk, GLib, Gtk

DEVX_CONFIG = os.environ.get(
    "DEVX_CONFIG",
    os.path.expanduser("~/.config/devuan-xfce-setup"),
)
PICKER = os.path.join(DEVX_CONFIG, "picker.colors")
DEFAULTS = {"bg0": "#121113F2", "bg1": "#1c1b1d", "bg3": "#e75353F2", "fg0": "#ffffff"}


def theme_colors():
    colors = dict(DEFAULTS)
    try:
        with open(PICKER, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, value = line.split("=", 1)
                    if key in colors and value:
                        colors[key] = value
    except OSError:
        pass
    return colors


def parse_rgba(value, alpha=1.0):
    v = value.strip()
    if len(v) == 9:
        v = v[:7]
    if not (v.startswith("#") and len(v) == 7):
        v = "#121113"
    return Gdk.RGBA(
        red=int(v[1:3], 16) / 255.0,
        green=int(v[3:5], 16) / 255.0,
        blue=int(v[5:7], 16) / 255.0,
        alpha=alpha,
    )


class UpdateWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_title("Devuan Update")
        self.set_default_size(720, 520)
        self.colors = theme_colors()
        self.busy = False
        self.setup_css()

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        outer.set_margin_top(14)
        outer.set_margin_bottom(14)
        outer.set_margin_left(16)
        outer.set_margin_right(16)
        self.add(outer)

        title = Gtk.Label(label="System Update")
        title.get_style_context().add_class("title")
        outer.pack_start(title, False, False, 0)

        sub = Gtk.Label(label="Updates run in the terminal below. Your password may be asked for sudo.")
        sub.get_style_context().add_class("subtitle")
        outer.pack_start(sub, False, False, 0)

        if VTE_AVAILABLE:
            self.term = Vte.Terminal()
            self.term.set_size(80, 24)
            fg = parse_rgba(self.colors["fg0"])
            bg = parse_rgba(self.colors["bg1"])
            self.term.set_colors(fg, bg, [])
            scroller = Gtk.ScrolledWindow()
            scroller.set_hexpand(True)
            scroller.set_vexpand(True)
            scroller.add(self.term)
            outer.pack_start(scroller, True, True, 0)
        else:
            self.term = None
            warn = Gtk.Label(
                label="VTE terminal widget is missing (gir1.2-vte-2.91 not installed).\n"
                "Updates will open in a separate terminal window instead."
            )
            warn.get_style_context().add_class("subtitle")
            outer.pack_start(warn, False, False, 0)

        btnrow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btnrow.set_halign(Gtk.Align.END)
        outer.pack_end(btnrow, False, False, 0)

        check = Gtk.Button(label="Check only")
        check.connect("clicked", self.on_check)
        self.check_btn = check
        btnrow.pack_start(check, False, False, 0)

        self.update_btn = Gtk.Button(label="Update now")
        self.update_btn.connect("clicked", self.on_update)
        btnrow.pack_start(self.update_btn, False, False, 0)

        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_: self.close())
        btnrow.pack_start(close, False, False, 0)

        status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        outer.pack_start(status_row, False, False, 0)
        self.status = Gtk.Label(label="Ready")
        self.status.get_style_context().add_class("status")
        status_row.pack_start(self.status, False, False, 0)
        self.spinner = Gtk.Spinner()
        self.spinner.set_active(False)
        status_row.pack_start(self.spinner, False, False, 0)

        self.update_btn.grab_focus()

    def setup_css(self):
        css = b"""
            .title { font-size: 20px; font-weight: bold; color: %s; }
            .subtitle { color: %s; }
            .status { color: %s; }
        """ % (
            self.colors["fg0"].encode(),
            self.colors["fg0"].encode(),
            self.colors["bg3"].encode(),
        )
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def set_busy(self, busy):
        self.busy = busy
        self.spinner.set_active(busy)
        self.update_btn.set_sensitive(not busy)
        if self.check_btn is not None:
            self.check_btn.set_sensitive(not busy)

    def spawn(self, argv, on_exit=None):
        if self.term is not None:
            def _handler(_term, status, cb=on_exit):
                if cb:
                    cb(status)

            try:
                self.term.spawn_sync(
                    Vte.PtyFlags.DEFAULT, None, argv, None,
                    GLib.SpawnFlags.SEARCH_PATH, None, None, None,
                )
                if on_exit is not None:
                    self.term.connect("child-exited", _handler)
            except Exception:
                if on_exit:
                    on_exit(-1)
        else:
            subprocess.Popen(argv)
            if on_exit:
                on_exit(0)

    def on_check(self, _btn):
        self.set_busy(True)
        self.status.set_text("Checking for updates...")

        def _done(_code):
            self.set_busy(False)
            self.status.set_text("Check complete — lines ending in 'upgradable' are pending updates.")

        self.spawn(["bash", "-lc", "sudo -n apt-get update; apt list --upgradable"], on_exit=_done)

    def on_update(self, _btn):
        if self.busy:
            return
        self.set_busy(True)
        self.status.set_text("Updating... do not close this window mid-update.")

        if self.term is None:
            def _empty(_code):
                self.set_busy(False)
                self.status.set_text("Update running in the separate terminal window.")

            self.spawn(["x-terminal-emulator"], on_exit=_empty)
        else:
            def _finished(_code):
                self.set_busy(False)
                self.status.set_text("Update finished.")

            self.spawn(
                [
                    "bash",
                    "-lc",
                    "sudo apt-get update && sudo apt-get full-upgrade; "
                    "CODE=$?; if [ $CODE -eq 0 ]; then "
                    "notify-send -i software-update-ok 'Updates complete' 'Your system is up to date.'; "
                    "else notify-send -i software-update-error 'Update had errors' "
                    "'See the terminal output for what failed.'; fi; exit $CODE",
                ],
                on_exit=_finished,
            )


def main():
    app = Gtk.Application()
    app.connect("activate", lambda a: UpdateWindow(a).show_all())
    app.run(None)


if __name__ == "__main__":
    if not VTE_AVAILABLE and not os.environ.get("DISPLAY"):
        sys.exit(subprocess.call(["sudo", "apt-get", "full-upgrade"]))
    main()
