# configs/ — versioned static config installed verbatim by scripts
#
# Unlike DebianSway (where configs/ holds rendered theme output), most
# XFCE config here is generated idempotently by the scripts themselves
# (theme names vary per machine, so terminalrc and the LightDM greeter
# conf are written inline by 21-* and 22-*). Only files that are
# identical on every machine live here:
#
#   Thunar/uca.xml   — Thunar custom actions, installed by 30-desktop-essentials.sh
#                      (Open Terminal Here via exo, Open as Root via pkexec)
#   lightdm/gtk.css  — Catppuccin Red login-box shim, installed by 22-theme-boot.sh
#                      to /var/lib/lightdm/.config/gtk-3.0/gtk.css (lightdm-owned)
#   bin/xfce-first-run      — welcome wizard (update + Timeshift), deployed by
#                      35-first-run.sh to ~/.local/bin + autostart (once per user)
#   bin/xfce-seed-wallpaper — default backdrop for monitors with none yet
#                      (never overwrites), deployed by 35-first-run.sh
#   bin/xfce-theme-set / xfce-theme-list — palette switcher + listing, deployed
#                      by 21-theme-tokyonight.sh with the theme engine
#                      (~/.config/devuan-xfce-setup/). They consume palettes
#                      from themes/ at the repo root.
#
#   bin/xfce-menu / xfce-update-gui — themed GTK launchers, deployed by
#                      24-power-user.sh; they exec python3 apps from
#                      share/devuan-xfce-setup/{xfce-menu,xfce-update-gui}.py
#                      themed via the palette engine's picker.colors.
#   bin/xfce-update-check — cron notifier (09:00 + 18:00), pops desktop
#                      notification with "Update now" action
#   bin/xfce-lock / xfce-suspend — thin wrappers (xflock4 / pm-suspend)
#
# NOTE: alacritty.yml and gtk-session.css no longer live here — they were
# palette-driven and moved to themes/_base/tpl/ (rendered by
# lib/theme-apply.sh from themes/<id>/palette.sh).
#
# If you edit a file here, re-run its script to deploy it.
