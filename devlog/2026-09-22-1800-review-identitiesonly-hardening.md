---
date: 2026-09-22
session: review-identitiesonly-hardening
project: baseline-access
related:
  - PR#6
  - PR#7
  - PR#8
  - tag:v0.3.2
  - tag:v0.3.3
  - BACKLOG B-4, B-5, B-6, B-7, B-8
status: done
---

## Goal
Review the whole repo, fix what it turned up, and cut releases so the pinned
curl one-liner serves the fixes.

## Context
- Started on the unpushed `fix-github-detection` branch (B-4, `dfb8811`), one
  commit ahead of `main` (`e78512a`, v0.3.1). The branch's README already
  pinned `v0.3.2`, which did not exist yet.

## What we did
- Full repo review: read `baseline-access.sh`, README, ADR 0001, BACKLOG, test
  harness; `tests/run` 73/73. Two real bugs, reproduced live:
  - **B-5** — the `Host github.com` stanza had only `IdentityFile`. With
    `ssh -v` and a throwaway agent key, ssh offered the *agent* key before the
    configured file, so a personal key in ssh-agent authenticates as the wrong
    account while verify (banner match only) reports success.
  - **B-6** — `${GIT_IDENTITY_NAME:-$cur_name}` let the env var overwrite an
    already-set `user.name` when only `user.email` was missing (reproduced with
    an isolated `HOME` + `XDG_CONFIG_HOME`).
- Fixed both on top of B-4: stanza gains `IdentitiesOnly yes`; existing values
  win over `GIT_IDENTITY_*` and only the missing half is written; verify prints
  the account from the banner (`Hi <user>!`).
- PR#6 review (`/code-review` medium) found two gaps, both confirmed with real
  `ssh -G`: IdentityFiles accumulate in file order and `IdentitiesOnly` does
  not filter configured files (an earlier `Host github.com` block's personal
  key is still tried first); and ssh keeps the first `IdentitiesOnly` value, so
  an earlier `Host *` with `no` overrides our appended `yes`. Fixed by always
  checking the *resolved* config after the stanza step and warning (never
  rewriting — the block may be fleet-control's).
- Self-review caught a B-1-class race in those new checks: `ssh -G` prints
  ~4 KB, so `ssh -G | grep -q` / `| head -n1` can SIGPIPE ssh under
  `pipefail`. Replaced with captured output / process substitution; 200/200
  stable against real ssh. Squash-merged PR#6 (`45a4625`), tagged `v0.3.2`.
- Operator's machine: `~/.ssh/config` was the old two-line stanza. Backed up to
  `~/.ssh/config.bak-2026-09-22`, added `IdentitiesOnly yes`; `ssh -T`
  authenticates as `juangalt`.
- **B-7** minor hardening (PR#7, `bf237f4`): `preflight` checks
  `curl jq git ssh ssh-keygen` before Bitwarden login (also closes the
  duplicate-stanza-per-run case when `ssh` is absent); README Prerequisites
  section; failed key write/rename removes the temp file; a directory at the
  key path is refused (`mv` would move the key *into* it, `mv -T` is GNU-only);
  key path matched by file via `-ef` (Bluefin `/home` → `/var/home`);
  `.claude/worktrees/` gitignored. Review: no findings.
- PR#8 (`34c92d4`) bumped the README pin; `v0.3.3` tagged on that merge commit.
  Raw URL returns 200 and serves `preflight()`. Suite 83/83.
- **B-8** (closing, with this devlog): Ctrl-C/SIGTERM between `mktemp` and the
  rename could still leave the temp key file. The write now runs in a subshell
  with its own EXIT/INT/TERM cleanup handlers. Suite 85/85; the signal test
  fails pre-fix and ran 10/10 clean after.

## Decisions
- Warn, don't rewrite, when the resolved github.com config is unsafe
  (`IdentitiesOnly no`, or another key tried first): the block may belong to
  fleet-control, and this rung's scope is to add its own stanza, not manage
  other tools' config.
- Preflight names tools, not packages — package names differ per distro
  (`openssh-client` vs `openssh`); the README carries per-distro lines.
- Tags are cut from the merge commit that bumps the README pin, so each tag's
  README points at itself.

## What worked
- Checking every claim against real OpenSSH (`ssh -v`, `ssh -G -F`) before and
  after fixing — both review findings were confirmed that way in minutes.
- Swapping in the pre-fix script to prove each new regression test fails
  first.

## What didn't work
- The first B-5 fix only covered the "stanza skipped" branch; the reviewer
  showed appending is not sufficient on its own. Checking the resolved config
  unconditionally is the real invariant.
- B-8's first attempt set function-level handlers and saved/restored the
  caller's. Under bats `run`, `trap -p` inside the subshell still reports the
  parent's handlers, so restoring re-installed bats' EXIT handler there and
  failed unrelated tests. A subshell with its own handlers avoids the problem.

## Open / next
- B-8 is on `main` but not in a release: the README still pins `v0.3.3`.
- The directory guard is check-then-act (only racy with a concurrent writer in
  `~/.ssh`); noted on PR#7, not filed.
- `baseline-bluefin` keeps an independent copy of this logic and likely has the
  same stanza without `IdentitiesOnly`; left alone this session by operator
  instruction.
- Machines provisioned by `v0.3.x` and fleet-control's rendered block need
  `IdentitiesOnly yes` — re-running now only warns.

## Not filed
- The directory-guard check-then-act note above (low severity).
