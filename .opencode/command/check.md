---
description: Run the release gate: make release-preflight, then pkg-deb + check-deb.
agent: build
---

Run, in order and stopping on failure:

1. `make release-preflight` — the version gate (lint + unit + consistency +
   VERSION ↔ RELEASE.md agreement). If it fails on the VERSION/RELEASE.md
   agreement, either bump `VERSION` and add the matching top `## x.y.z —`
   heading in `RELEASE.md`, or fold an `## Unreleased` block into the pending
   release — ask the user which before editing.
2. `make pkg-deb` then `make check-deb` — build the content deb and verify it
   with dpkg-deb + lintian (expect zero errors).
3. Tell the user the tag command to run once they're happy:
   `git tag -a "v$(cat VERSION)" -m "v$(cat VERSION)" && git push --tags`

Do not commit or tag yourself unless asked.