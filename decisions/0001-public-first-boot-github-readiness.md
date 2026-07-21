# 0001 — A public first-boot repo whose only job is GitHub readiness

- **Status:** accepted
- **Date:** 2026-06-16 (created from `meta-ai-dev` plan `plans/baseline-github.md`,
  backlog item B-26; forks resolved 2026-06-14)

> **Provenance (2026-07-21, baseline decomposition Phase 1).** This repo was created
> as `baseline-github` and is now **`baseline-access`** (`v0.2.0`). The
> `bitwarden-item` fork below is **resolved**: the two names were fingerprint-verified
> as the same key and the script standardized on `fleet-policy:keys/service/github`;
> the legacy `ssh-access service key: github` item is retained until the migration
> tombstone. See `baseline-setup` ADR 0004 D3. The dated decision text below is left
> as the original historical record.

## Context

When `baseline-bluefin` (the merged laptop bootstrap) went **private**, a fresh
machine lost its anonymous entry point: it can't clone the private repo that
contains the code to fetch its GitHub SSH key, because fetching that key is what
lets it clone private repos. The fleet skill hits the same wall for control
nodes and works around it with an HTTPS+PAT install of a private tool — a PAT
minted by hand on every fresh machine.

The fetch logic itself is small (~40 lines, already correct in
`baseline-bluefin.sh`): `bw login`/`unlock` → `bw get item` → write
`~/.ssh/github` mode 600 → ensure the `github.com` SSH config stanza.

## Decision

Create a tiny **public** repo, `baseline-github`, that a credential-less machine
can always clone over HTTPS and run. Its single job is to make the machine
**git-ready**, then stop:

1. interactive Bitwarden auth (mirrors the proven bluefin flow);
2. write the GitHub service key to `~/.ssh/github` (mode 600);
3. wire `~/.ssh/config` + `~/.ssh/known_hosts` for `github.com`, idempotently;
4. configure the global git identity;
5. verify `ssh -T git@github.com` and point at the next bootstrap.

Resolved forks (all at their recommended option, 2026-06-14):

- **secret-scope (a):** GitHub service key **only**. The recovery key reaches
  other hosts and belongs to the fleet flow; bundling it widens a public repo's
  blast radius for no first-boot need. Build clean enough that adding items later
  is small, but ship just the key.
- **invocation (c):** clone-then-run is canonical (auditable); a `curl | bash`
  one-liner is offered, pinned to a **tag**, not `main`, so the executed bytes
  are reviewable and stable.
- **bluefin-dedup (a):** `baseline-github` and `baseline-bluefin` keep
  **independent copies** of the login + fetch logic, coupled only by a shared
  Bitwarden item name — no cross-repo code dependency, and the public repo stays
  self-contained. A future edit to the fetch logic must touch both deliberately.
- **bitwarden-item (a):** reuse bluefin's item name `ssh-access service key:
  github` (`.sshKey.privateKey`) verbatim. Do not unify or rename names across
  bluefin/fleet here; that reconciliation is a separate item if the names truly
  point at the same key.
- **machine-scope (a):** generic and machine-agnostic — no Bluefin assumptions;
  package-manager detection is portable, so a cloud VM or LXC control node could
  reuse the same entry point.
- **bw-auth-method (a):** interactive Bitwarden auth only for the first cut;
  API-key / unattended auth is a documented future extension.

## Alternatives considered

- **Keep the PAT dance / leave bluefin's path as-is.** Works, but requires
  minting a PAT by hand on every fresh machine — exactly the friction this
  removes.
- **Extract the fetch logic into one provisioner and have bluefin delegate to
  it.** Most DRY, but couples bluefin's first-run story to a second (public) repo
  and adds a public→private ordering wrinkle. Rejected in favor of two
  self-sufficient repos sharing only an item name.
- **A configurable item manifest (provision any secret).** Scope creep for a
  first-boot rung; the door is left open by keeping the github path clean, not by
  building the manifest now.

## Consequences

- The repo is **public**: only logic ships, never secret values; the
  secrets-discipline in `CLAUDE.md` is load-bearing.
- The provisioner is the deployment; the bats suite is the executable invariant
  (every external tool mocked). No Terraform/verify.sh is warranted at this
  altitude (dev-practices `decisions/0007`).
- ~40 lines of stable fetch logic are duplicated with `baseline-bluefin` on
  purpose; the coupling is the item name, documented in both repos' `CLAUDE.md`.
- A real divergence between `ssh-access service key: github` and the fleet's
  `fleet-policy:keys/service/github` would warrant its own reconcile item.
