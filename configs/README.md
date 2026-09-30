# configs/ — versioned static config installed verbatim by scripts
#
# XFCE config here is either generated idempotently by the scripts or
# installed from a seed below — it is never pre-rendered theme output, so a
# checkout has to be valid as-is. Only files that are identical on every
# machine live here:
#
#   xfce4/xfconf/xfce-perchannel-xml/ — panel + window-manager seed: the
#                      panel item layout plus the convention/sans fonts
#                      (panel clock font, xfwm4 title font, decorations)
#                      and the xfwm4 built-in compositor (use_compositing,
#                      subtle shadows, inactive dim). picom is not used.
#                      21-theme.sh copies these into ~/.config/xfce4/xfconf/
#                      (backing up what's there) then restarts xfce4-panel
#                      and xfwm4. Also exported to /etc/skel by 52-skel-export.sh.
#   alacritty/alacritty.toml — Darkmatter palette (0.13+ TOML format), deployed
#                      by 21-theme.sh to ~/.config/alacritty/ (backing up)
#   Thunar/uca.xml   — Thunar custom actions, installed by 30-desktop-essentials.sh
#                      (Open Terminal Here via exo, Open as Root via pkexec)
#   lightdm/gtk.css  — Darkmatter login-box shim, installed by 22-theme-boot.sh
#                      to /var/lib/lightdm/.config/gtk-3.0/gtk.css (lightdm-owned)
#                      NOTE: the Darkmatter GTK/xfwm4 themes and Zafiro icons
#                      are NOT stored here — 21-theme.sh fetches them at install
#                      time from stevedylandev/darkmatter-linux and
#                      zayronxio/Zafiro-icons and auto-tweaks them via
#                      scripts/lib/darkmatter-fetch.sh (red-accent remap,
#                      hdpi/xhdpi assembly, Zafiro-icons-Dark rename + trim)
#                      into /usr/share/themes/ and /usr/share/icons/.
#   wallpapers/      — curated dark/red wallpaper set, deployed by 21-theme.sh
#                      to /usr/share/backgrounds/xfce/devuan-darkmatter/
#   dunst/dunstrc    — Darkmatter-accented Dunst config (20-* opt-in)
#   fastfetch/devuan.txt — the Devuan logo, deployed by 19-fastfetch.sh.
#                      A *template*, not a picture: the leading `$1` on every
#                      line is a fastfetch colour placeholder, swapped for the
#                      red of the palette at render time (`cat`ing the file
#                      shows the tokens), and every literal `$` in the logo is
#                      escaped as `$$`. Single-coloured on purpose — the logo
#                      is a solid mass of `$`, and a colour token after a run
#                      of `$$` pairs is misread as a literal digit.
#   bash/rc.sh        — loader: sources the parts below, then prints the fastfetch
#                      summary once per interactive shell. Non-interactive shells
#                      return immediately. Deployed by 18-shell-config.sh.
#   bash/functions.sh — extract, mkcd, cfile, reload, ff, ports, json
#   bash/aliases.sh   — navigation, eza/ls, ripgrep shortcuts, git, less/PAGER
#   bash/prompt.sh    — two-line Nerd-Font prompt; branch read from .git/HEAD
#                      without forking, one `git status` for the dirty marker
#   bash/hooks.sh     — bash-completion, fzf/zoxide, readline keybinds
#   bash/99-xfcemlg-overrides.sh — sourced LAST, after the vendored payload:
#                      corrects its bare-`sudo` apt aliases (doas-first
#                      `xfc_priv`) and its netstat-based `ports` alias.
#                      The vendored tree itself is never edited.
#   butterbash/       — vendored third-party shell framework, GPL-2.0
#                      (JustAGuyLinux, Codeberg), restored verbatim in 0.9.0.
#                      18-shell-config.sh installs bash/*.bash and
#                      bash/functions/*.bash to ~/.config/bash/ (the path
#                      upstream's own bashrc reads) plus its LICENSE. rc.sh
#                      sources it after the xfcemlg parts, so its prompt and
#                      aliases are what the user sees. Every file is
#                      byte-identical to upstream — see docs/PROVENANCE.md.
#   firefox/bookmarks.html — curated bookmarks imported by 35-first-run.sh
#   bin/xfce-first-run      — welcome wizard (update + Timeshift), deployed by
#                      35-first-run.sh to ~/.local/bin + autostart (once per user)
#   bin/xfce-seed-wallpaper — default backdrop for monitors with none yet
#                      (never overwrites), deployed by 35-first-run.sh
#
#   bin/xfce-menu / xfce-update-gui — themed GTK launchers, deployed by
#                      24-power-user.sh; they exec python3 apps from
#                      share/xfcemlg/{xfce-menu,xfce-update-gui}.py
#                      themed via the static picker.colors written by
#                      21-theme.sh (~/.config/xfcemlg/picker.colors).
#   bin/xfce-update-check — cron notifier (09:00 + 18:00), pops desktop
#                      notification with "Update now" action
#   bin/xfce-lock / xfce-suspend — thin wrappers (xflock4 / xfce4-session-logout --suspend)
#
# If you edit a file here, re-run its script to deploy it.