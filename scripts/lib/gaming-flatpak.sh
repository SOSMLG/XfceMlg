#!/usr/bin/env bash
# =======================================================
# gaming-flatpak.sh — Heroic "native over Flatpak" helper
# -------------------------------------------------------
# The toolkit's method for Heroic Games Launcher is the
# native .deb (44-gaming.sh downloads the latest GitHub
# release). When the Flatpak build of Heroic is ALSO
# installed, the machine carries a duplicate app plus
# ~1.7 GB of re-downloadable runtimes (config/heroic/tools)
# that no backup is allowed to include — dead weight.
#
# These helpers detect that orphan and offer to purge it.
# The offer is ask_no_full with a default of N: neither
# --full nor an unattended run may answer it. Never fires
# when the native Heroic is missing (the Flatpak may be the
# user's only Heroic) or when no Flatpak is present at all.
#
# Privilege: priv() for the flatpak removal (system installs
# need root). Sourced by 44-gaming.sh.
# =======================================================

# gaming_flatpak_uninstall — remove the Flatpak Heroic app AND its data
# (~/.var/app/com.heroicgameslauncher.hgl, the multi-GB tools dir).
# Returns priv()'s status so callers can report success/failure.
gaming_flatpak_uninstall() {
	priv flatpak uninstall --delete-data -y com.heroicgameslauncher.hgl
}

# gaming_flatpak_orphan_check — offer to purge the Flatpak Heroic when the
# native one is installed. No-op unless BOTH are present.
gaming_flatpak_orphan_check() {
	command -v heroic >/dev/null 2>&1 || return 0  # no native Heroic
	command -v flatpak >/dev/null 2>&1 || return 0 # no Flatpak at all
	if ! flatpak list --app 2>/dev/null | grep -qF 'com.heroicgameslauncher.hgl'; then
		return 0 # Flatpak Heroic not installed
	fi

	log_info "Flatpak Heroic detected alongside the native install — the Flatpak is a"
	log_info "duplicate app holding re-downloadable runtimes (~1.7 GB in"
	log_info "$HOME/.var/app/com.heroicgameslauncher.hgl). The toolkit's method is native."

	if ask_no_full "Remove the Flatpak Heroic Games Launcher (native is installed)?" "N"; then
		if gaming_flatpak_uninstall; then
			log_ok "Flatpak Heroic removed — the native Heroic stays untouched."
		else
			log_warn "Flatpak Heroic removal failed (escalation? no permission?). Leaving it"
			log_warn "in place — it is harmless, just duplicate disk."
		fi
	else
		log_info "Keeping the Flatpak Heroic. Re-run this step with 'y' to purge it later."
	fi
	return 0
}
