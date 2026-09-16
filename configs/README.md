# configs/ — versioned static config installed verbatim by scripts
#
# Unlike DebianSway (where configs/ holds rendered theme output), most
# XFCE config here is generated idempotently by the scripts themselves
# (the Darkmatter alacritty.toml is written inline by 21-*). Only files
# that are identical on every machine live here:
#
#   xfce4/xfconf/xfce-perchannel-xml/ — panel + window-manager seed: the
#                      panel item layout plus the convention/sans fonts
#                      (panel clock font, xfwm4 title font, decorations).
#                      21-theme.sh copies these into ~/.config/xfce4/xfconf/
#                      (backing up what's there) then restarts xfce4-panel
#                      and xfwm4. Also exported to /etc/skel by 52-skel-export.sh.
#   Thunar/uca.xml   — Thunar custom actions, installed by 30-desktop-essentials.sh
#                      (Open Terminal Here via exo, Open as Root via pkexec)
#   lightdm/gtk.css  — Darkmatter login-box shim, installed by 22-theme-boot.sh
#                      to /var/lib/lightdm/.config/gtk-3.0/gtk.css (lightdm-owned)
#   themes/          — bundled Darkmatter GTK/xfwm4 theme, all three variants
#                      (Darkmatter / -hdpi / -xhdpi), deployed by 21-theme.sh to
#                      /usr/share/themes/. No theme engine — this IS the theme.
#   icons/           — bundled Zafiro-icons-Dark (PNG variant), deployed by
#                      21-theme.sh to /usr/share/icons/
#   wallpapers/      — curated dark/red wallpaper set, deployed by 21-theme.sh
#                      to /usr/share/backgrounds/xfce/devuan-darkmatter/
#   dunst/dunstrc    — Darkmatter-accented Dunst config (20-* opt-in)
#   rofi/darkmatter.rasi — matching rofi theme (21-* optional deploy)
#   bin/xfce-first-run      — welcome wizard (update + Timeshift), deployed by
#                      35-first-run.sh to ~/.local/bin + autostart (once per user)
#   bin/xfce-seed-wallpaper — default backdrop for monitors with none yet
#                      (never overwrites), deployed by 35-first-run.sh
#
#   bin/xfce-menu / xfce-update-gui — themed GTK launchers, deployed by
#                      24-power-user.sh; they exec python3 apps from
#                      share/devuan-xfce-setup/{xfce-menu,xfce-update-gui}.py
#                      themed via the static picker.colors written by
#                      21-theme.sh (~/.config/devuan-xfce-setup/picker.colors).
#   bin/xfce-update-check — cron notifier (09:00 + 18:00), pops desktop
#                      notification with "Update now" action
#   bin/xfce-lock / xfce-suspend — thin wrappers (xflock4 / pm-suspend)
#
# If you edit a file here, re-run its script to deploy it.