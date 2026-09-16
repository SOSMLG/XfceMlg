.PHONY: check lint test apt-checks consistency release-preflight pkg-deb check-deb clean

DEB_NAME  := devuan-xfce-assets
DEB_VER   := $(shell cat VERSION)
DEB_STAGE := build/$(DEB_NAME)-$(DEB_VER)
DEB_FILE  := build/$(DEB_NAME)_$(DEB_VER)_all.deb

# ── Main targets ─────────────────────────────────────────────────────────────

check: ## Run all tiers (lint + unit + consistency + apt-checks)
	bash tests/run.sh

lint: ## Tier 1: bash -n, shellcheck, py_compile
	bash tests/lint.sh

test: ## Tier 2: sandboxed unit tests (no root, no apt, no X)
	bash tests/unit/run.sh

apt-checks: ## Tier 3: read-only apt-cache package existence checks
	bash tests/apt-checks.sh

consistency: ## Tier 3: cross-file regression guards
	bash tests/consistency.sh

# ── Release gate ─────────────────────────────────────────────────────────────

release-preflight: ## Verify VERSION/RELEASE.md consistency + all tests green
	bash tests/lint.sh
	bash tests/unit/run.sh
	bash tests/consistency.sh
	@test "$$(cat VERSION)" = "$$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' RELEASE.md | cut -d' ' -f2)" || \
		{ echo "[preflight] VERSION file ($(cat VERSION)) does not match latest RELEASE.md heading" >&2; exit 1; }
	@echo "[preflight] READY for v$$(cat VERSION)"

# ── Packaging (single content deb, no APT repo) ─────────────────────────────

pkg-deb: ## Stage repo tree into $(DEB_FILE) (data-only, all arch)
	rm -rf "$(DEB_STAGE)"
	mkdir -p "$(DEB_STAGE)/DEBIAN"
	mkdir -p "$(DEB_STAGE)/usr/share/doc/$(DEB_NAME)"
	mkdir -p "$(DEB_STAGE)/usr/share/$(DEB_NAME)/skills"
	@set -e
	sed "s/@VERSION@/$(DEB_VER)/" packages/$(DEB_NAME)/DEBIAN/control > "$(DEB_STAGE)/DEBIAN/control"
	cp packages/$(DEB_NAME)/DEBIAN/postinst "$(DEB_STAGE)/DEBIAN/postinst"
	sed "s/@VERSION@/$(DEB_VER)/" packages/$(DEB_NAME)/usr/share/doc/$(DEB_NAME)/copyright > "$(DEB_STAGE)/usr/share/doc/$(DEB_NAME)/copyright"
	sed "s/@VERSION@/$(DEB_VER)/" packages/$(DEB_NAME)/usr/share/doc/$(DEB_NAME)/changelog > "$(DEB_STAGE)/usr/share/doc/$(DEB_NAME)/changelog"
	cp -a configs "$(DEB_STAGE)/usr/share/$(DEB_NAME)/configs"
	cp scripts/skills/xfce-setup-SKILL.md "$(DEB_STAGE)/usr/share/$(DEB_NAME)/skills/"
	chmod 0644 "$(DEB_STAGE)/usr/share/doc/$(DEB_NAME)/copyright"
	find "$(DEB_STAGE)" -type d -exec chmod 0755 {} +
	find "$(DEB_STAGE)" -type f -exec chmod 0644 {} +
	find "$(DEB_STAGE)/usr/share" -type f -exec awk 'NR==1 { exit !/^#!\// }' {} \; -exec chmod 0755 {} +
	gzip -9fn "$(DEB_STAGE)/usr/share/doc/$(DEB_NAME)/changelog"
	chmod 0755 "$(DEB_STAGE)/DEBIAN/postinst"
	dpkg-deb --build --root-owner-group "$(DEB_STAGE)" "$(DEB_FILE)" >/dev/null
	@echo "[debug/pkgs] $(DEB_FILE) built ($$(du -h '$(DEB_FILE)' 2>/dev/null | cut -f1))"

check-deb: ## Inspect the built deb: info, contents, lintian (if present)
	@test -f "$(DEB_FILE)" || { echo "[debug/pkgs] run 'make pkg-deb' first" >&2; exit 2; }
	dpkg-deb --info "$(DEB_FILE)"
	@echo "[debug/pkgs] --- contents sample ---"
	dpkg-deb --contents "$(DEB_FILE)" | sed -n '1,15p'
	@echo "[debug/pkgs] --- lintian (errors/notes) ---"
	@if command -v lintian >/dev/null 2>&1; then \
		lintian -E --info "$(DEB_FILE)" 2>&1 | grep -Ev '^N: |^W: (no-symbols-control-file|debian-revision-not-recommended)' ; \
	else echo "lintian not installed — skipping"; fi

# ── Housekeeping ─────────────────────────────────────────────────────────────

clean: ## Remove generated __pycache__/*.pyc and build staging
	find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	find . -name '*.pyc' -delete 2>/dev/null || true
	rm -rf build