#!/usr/bin/env python3
"""xfce-menu — a themed power-user menu for the devuan-xfce-setup toolkit.

Adapted from devuan-menu (Cinnamon, MIT licensed):
curated categories + commands, type-ahead search, themed via the palette-
engine's picker.colors file.

Launch from the command line or a keyboard shortcut (e.g. Super+M).
"""
import os
import shlex
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, Gtk, Pango

DEVX_CONFIG = os.environ.get(
    "DEVX_CONFIG",
    os.path.expanduser("~/.config/devuan-xfce-setup"),
)
PICKER = os.path.join(DEVX_CONFIG, "picker.colors")
DEFAULTS = {"bg0": "#121113F2", "bg1": "#1c1b1d", "bg3": "#e75353F2", "fg0": "#ffffff"}

CATEGORIES = {
    "Apps": [
        ("Files", "thunar"),
        ("Firefox", "firefox"),
        ("Timeshift", "sudo timeshift-launcher"),
    ],
    "AI": [
        ("OpenCode Agent", "opencode"),
    ],
    "Terminals": [
        ("Alacritty", "alacritty"),
        ("btop", "btop"),
        ("htop", "htop"),
        ("Root shell", "pkexec x-terminal-emulator -- bash -il"),
    ],
    "Editors": [
        ("VSCodium", "codium"),
        ("Pluma", "pluma"),
    ],
    "Update": [
        ("Update Window", "xfce-update-gui"),
        ("Force update check", "sh -c '~/.local/bin/xfce-update-check; echo; read -p press-enter'"),
    ],
    "System": [
        ("Lock Screen", "xfce-lock"),
        ("Suspend", "xfce-suspend"),
        ("Restart", "sudo shutdown -r now"),
        ("Shut Down", "sudo shutdown -h now"),
        ("Log Out", "xfce4-session-logout --logout --no-prompt"),
    ],
}

TERMINAL_WRAPPED = ("btop", "htop", "opencode", "sh -c")


def terminal_wrap(cmd):
    inner = shlex.split(cmd)
    return [
        "x-terminal-emulator", "--", "bash", "-c",
        '"$@" ; exec bash', "xfce-menu", *inner,
    ]


def theme_colors():
    colors = dict(DEFAULTS)
    try:
        with open(PICKER, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith(("bg0=", "bg1=", "bg3=", "fg0=")):
                    key, value = line.split("=", 1)
                    if value:
                        colors[key] = value
    except OSError:
        pass
    return colors


def rgba(value, alpha=1.0):
    value = value.strip()
    if len(value) == 9:
        value = value[:7]
    if not (value.startswith("#") and len(value) == 7):
        value = "#121113"
    return Gdk.RGBA(
        red=int(value[1:3], 16) / 255.0,
        green=int(value[3:5], 16) / 255.0,
        blue=int(value[5:7], 16) / 255.0,
        alpha=alpha,
    )


ALL_ITEMS = [(cat, name, cmd) for cat, items in CATEGORIES.items() for name, cmd in items]


class Menu(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_title("xfce-menu")
        self.set_default_size(520, 420)
        self.colors = theme_colors()
        self.setup_css()

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        vbox.set_margin_top(12)
        vbox.set_margin_bottom(12)
        vbox.set_margin_left(12)
        vbox.set_margin_right(12)
        self.add(vbox)

        hint = Gtk.Label(label="Type to filter — Enter/click to run")
        hint.get_style_context().add_class("hint")
        vbox.pack_start(hint, False, False, 0)

        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("search apps, system, update…")
        self.search.connect("search-changed", self.on_search)
        vbox.pack_start(self.search, False, False, 0)

        self.store = Gtk.ListStore(str, str, str)
        for cat, name, cmd in ALL_ITEMS:
            self.store.append([cat, name, cmd])

        self.view = Gtk.TreeView(model=self.store)
        self.view.set_headers_visible(True)
        self.view.set_activate_on_single_click(True)
        self.view.connect("row-activated", self.on_activate)
        col_cat = Gtk.TreeViewColumn("Category", Gtk.CellRendererText(), text=0)
        col_name = Gtk.TreeViewColumn("Action", Gtk.CellRendererText(), text=1)
        col_name.set_expand(True)
        self.view.append_column(col_cat)
        self.view.append_column(col_name)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(self.view)
        scrolled.set_vexpand(True)
        vbox.pack_start(scrolled, True, True, 0)

        self.status = Gtk.Label(label="")
        self.status.get_style_context().add_class("hint")
        vbox.pack_start(self.status, False, False, 0)

        self.search.grab_focus()

    def setup_css(self):
        css = (
            "window {{ background-color: {bg0}; }}\n"
            "treeview {{ background-color: {bg1}; color: {fg0}; }}\n"
            "treeview:selected {{ background-color: {bg3}; color: {bg1}; }}\n"
            ".hint {{ color: {fg0}; font-size: 11px; }}\n"
        ).format(**self.colors).encode("utf-8")
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def on_search(self, _entry):
        needle = self.search.get_text().strip().lower()
        self.store.clear()
        for cat, name, cmd in ALL_ITEMS:
            if not needle or needle in (cat + " " + name + " " + cmd).lower() or needle in name.lower() or needle in cmd.lower():
                self.store.append([cat, name, cmd])
        self.status.set_text("" if needle else "Categories: Apps · AI · Terminals · Editors · Update · System")

    def on_activate(self, _view, path, _col):
        it = self.store.get_iter(path)
        _, name, cmd = (self.store.get_value(it, i) for i in (0, 1, 2))
        self.close()
        run_command(name, cmd)


def run_command(name, cmd):
    argv = cmd.split()
    base = argv[0]
    if any(tok in cmd for tok in TERMINAL_WRAPPED) and base not in ("sudo", "pkexec"):
        argv = terminal_wrap(cmd)
    try:
        if base in ("sudo", "pkexec"):
            subprocess.Popen(argv)
        else:
            subprocess.Popen(argv, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        subprocess.Popen(["x-terminal-emulator", "-e", cmd])
    except Exception as exc:
        print(f"xfce-menu: could not launch {name}: {exc}", file=sys.stderr)
        raise SystemExit(1)


def main():
    app = Gtk.Application()
    app.connect("activate", lambda a: Menu(a).show_all())
    app.run(None)


if __name__ == "__main__":
    main()
