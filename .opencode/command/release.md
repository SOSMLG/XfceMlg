---
description: Run the full read-only test suite (make check) and summarize.
agent: build
---

Run `make check` in the repo root (it needs no root and touches nothing). If
any tier fails, read the failure output carefully and decide whether to fix
the cause or call it out as environmental. Report a one-line summary per tier
(lint / unit / consistency / apt-checks) plus the final pass/fail. Do not
commit anything. If `make check` is green and the user is heading for a
release, note that `make release-preflight` is the version gate and offer it.