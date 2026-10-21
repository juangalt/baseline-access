---
date: 2026-10-21
session: git-ready-skip-bw
project: baseline-access
related:
  - commit:dbc2490
  - [[2026-09-22-1800-review-identitiesonly-hardening]]
  - baseline-setup [[yoga720-vault-bw-unlock]]
status: done
---

## Goal
Stop re-prompting Bitwarden on every provision when the GitHub key is already wired, and
survive flaky `api.github.com` host-key refreshes.

## Context
- `BASELINE_ACCESS_SESSION_FILE` handoff already existed (commit:`5a8fbdb`).
- yoga720 re-runs of `baseline-setup` hit provision while already git-ready, so vault layers
  lost `BW_SESSION` unless unlocked later by the orchestrator.

## What we did
- `already_git_ready` short-circuit in `cmd_provision`; override with
  `BASELINE_ACCESS_FORCE_BW=1` (commit:`dbc2490`).
- `ensure_known_hosts`: retry meta fetch; keep existing pins on failure
  (`KNOWN_HOSTS_RETRY_SLEEP` for tests) (commit:`dbc2490`).
- Tests: integration provision skip/force + unit keep-pins path (commit:`dbc2490`).
- Docs: README / CLAUDE reconciled for the short-circuit and soft refresh.

## Decisions
- Chose soft-continue on known_hosts when pins exist over failing the whole provision —
  DNS flaps must not block an already-git-ready machine.

## What worked
- Bats suite green including the new skip/force cases.

## What didn't work
- Nothing notable in this repo — the vault-side unlock gap is owned by baseline-setup’s
  `ensure_bw_for_selection`.

## Open / next
- Session ended clean; hygiene: `main` clean, no stale branches. See primary session
  [[yoga720-vault-bw-unlock]] for the cross-repo story.
