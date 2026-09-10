---
date: 2026-08-23
session: github-com-alias-detection
project: baseline-access
related:
  - PR#3
  - commit:70ffeda
  - baseline-setup PR#28 (companion fix, cross-repo)
status: done
---

## Goal
Fix `ssh_config_has_github()` false-detecting `github.com` coverage from an unrelated SSH alias, which left `~/.ssh/github` orphaned and `git@github.com:` unauthenticated.

## Context
- Follow-on from a `baseline-setup` investigation (its own devlog `[[2026-08-23-1653-private-repo-clone-scheme]]`) into a reported GitHub-auth inconsistency across `baseline-access`, `app-fleet-control`, and `baseline-setup` on the operator's laptop.
- That investigation's background-agent sweep found: `app-fleet-control` manages a working `Host github` SSH alias + `~/.ssh/svc-github` + a global `url.github:.insteadOf` rewrite; `baseline-access` independently writes `~/.ssh/github` from the *same* Bitwarden item but via its own `Host github.com` stanza — and that stanza was silently never getting written.

## What we did
- Read `ssh_config_has_github()` (`baseline-access.sh:144-153` pre-fix): looped over `for host in github.com github`, returning true on a match against *either* — so a working `github` alias (from `app-fleet-control`) was treated as proof the literal `github.com` host was covered.
- Confirmed live: `ssh -G github.com` resolved only default identities (no route); `ssh -G github` resolved `~/.ssh/svc-github`. The loop's OR made `save_github_key()` skip its own `Host github.com` stanza, leaving `~/.ssh/github` on disk but unrouted, and `verify_github_auth()`'s `ssh -T git@github.com` failing with `Permission denied (publickey)`.
- Fixed `ssh_config_has_github()` to check only `ssh -G github.com` (`baseline-access.sh`, commit `70ffeda`) — per this repo's own contract (`CLAUDE.md` "SSH only — never HTTPS", ADR 0001) it must make literal `git@github.com:` work standalone, not depend on another tool's alias/rewrite.
- Extended `tests/helpers/mocks.bash`'s `mock_ssh` with a new `alias` mode (a `github` alias resolves to a github-named key while `github.com` stays unrouted) and added a regression test in `tests/unit/test_github.bats` that fails against the pre-fix script and passes after.
- Ran the `devlog` skill's intake step against `BACKLOG.md`: `Open` section was already empty (only closed `B-1`), nothing from this session needed a new id — the finding was fixed in the same session, not deferred.
- `tests/run` — 53/53 pass. Opened PR#3.
- Applied the fix's effect live on the operator's machine: appended the same idempotent `Host github.com` stanza `save_github_key()` now writes, verified `ssh -T git@github.com` authenticates directly.

## Decisions
- Chose fixing the detection bug over unifying `~/.ssh/github` and `~/.ssh/svc-github` into one file, because ADR 0001 deliberately keeps `baseline-access` and other consumers as independent, self-contained copies coupled only by the shared Bitwarden item name — merging the files would fight a documented decision for no real gain, since both already contain byte-identical key material (verified matching `SHA256:nKchjruXmOTSjDSjn/aHYcHBZB8u5l7Za6yaMY/stC8` fingerprint).

## What worked
- Reading `ssh_config_has_github`'s mock (`mock_ssh` in `tests/helpers/mocks.bash`) before writing the fix showed exactly *why* the bug went uncaught: the mock only ever wired up `ssh -G github.com`, never a `github` alias branch, so the false-coverage path was structurally untestable until the mock itself was extended.
- Writing the regression test as a `mock_ssh alias` mode (rather than a one-off inline mock in the test file) keeps it reusable and makes the intent ("alias resolves, literal host doesn't") legible from the mode name alone.

## What didn't work
- Nothing notable — root cause was pinned down on the first read of the function once the live `ssh -G github.com` vs `ssh -G github` comparison was run.

## Open / next
- Session ended clean. PR#3 open, unmerged — operator to review/merge.
- Git-hygiene: branch `fix-github-com-alias-detection` (no worktree — edited directly in the live checkout since `EnterWorktree` only isolates the session's primary repo, not sibling repos) left in place pending PR merge.

## Not filed
- None — nothing surfaced this session that wasn't already fixed and committed.
