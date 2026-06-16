---
date: 2026-06-16
session: scaffold-baseline-github
project: baseline-github
related:
  - meta-ai-dev/plans/baseline-github.md
  - meta-ai-dev BACKLOG item B-26
status: done
---

## Goal
Scaffold the public `baseline-github` first-boot repo — a Bash provisioner that
makes any brand-new machine git-ready (GitHub key + git identity + SSH/known_hosts)
— with a fully mocked bats suite, per the resolved spec in `baseline-github.md`.

## Context
- B-26, discovered in the B-18 resolve session: when `baseline-bluefin` went
  private, a fresh machine lost its anonymous entry point for fetching the GitHub
  key. This repo is the public chicken-and-egg breaker.
- All six design forks were resolved 2026-06-14 at their recommendations
  (secret-scope a, invocation c, bluefin-dedup a, bitwarden-item a, machine-scope
  a, bw-auth-method a); recorded in `decisions/0001`.

## What we did
- Wrote `baseline-github.sh`: `provision` flow = `bw_login_or_unlock` →
  `save_github_key` (→ `~/.ssh/github` 600 + idempotent ssh config stanza) →
  `ensure_known_hosts` → `configure_git_identity` → `verify_github_auth` →
  `print_next_step`. Portable `detect_bw_installer`/`install_bw` (brew→npm→snap).
- Vendored bats-core/support/assert runtime under `tests/bats.d/` (no submodule
  init needed) and wrote 50 tests across `tests/unit/` + `tests/integration/`,
  every external tool mocked via PATH prepend. All green; script shellcheck-clean.
- Seeded the baseline-standard scaffold: thin `CLAUDE.md` (Category: baseline +
  secrets-discipline + Bitwarden-items table), `README.md` (clone-then-run
  canonical + pinned-tag curl), `.gitignore`, `.env.example`, lint-clean
  `BACKLOG.md`, `decisions/0001`, this devlog.

## Decisions
- Vendored bats as plain files over git submodules, because the repo is staged
  inside the meta-ai-dev worktree for the loop and must be runnable without a
  submodule fetch; the future standalone repo inherits a self-contained suite.
- Git identity sourced from `GIT_IDENTITY_NAME`/`GIT_IDENTITY_EMAIL` env (else
  interactive prompt), never hardcoded — keeps personal identity out of a public
  repo and keeps the script generic/machine-agnostic.

## What worked
- Mirroring `baseline-bluefin`'s test harness (PATH-prepend mocks, `head -n -1`
  + stubbed `main` to source functions) made the unit tests fall out quickly.

## What didn't work
- First test run restricted `PATH` to the mock bin without saving the original,
  which destroyed `grep`/`rm` and leaked into bats teardown; fixed with
  `only_mocks_on_path`/`restore_path` helpers in `common.bash`.
- A `mock_ssh_keyscan 0 ""` used `${2:-default}`, so the explicit empty string
  fell through to the default key — switched to `${2-default}`.

## Open / next
- Publishing is the one credentialed step the loop can't do: extract this dir to
  `~/code/baseline-github/`, `git init`, create the **public** GitHub repo
  `juangalt/baseline-github`, push, and cut tag `v0.1.0` so the README curl URL
  resolves.
- If `ssh-access service key: github` and the fleet's
  `fleet-policy:keys/service/github` turn out to be the same key, file the
  name-reconcile follow-up.
