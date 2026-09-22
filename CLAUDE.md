# baseline-access

**Category: baseline** — the public first-boot rung that makes any brand-new
machine git-ready, per `meta-ai-dev/decisions/0003-repo-taxonomy-by-type.md`.
Renamed from `baseline-github` at `v0.2.0` (baseline decomposition, Phase 1).

This repo is **PUBLIC**. Only bootstrap *logic* lives here so a credential-less
machine can clone it over HTTPS and read every byte before running it. No secret
value is ever committed — they render from Bitwarden at runtime.

## Secrets discipline

Never commit secrets, credentials, API keys, private keys, or personal key
material — not in code, tests, or git history. **Bitwarden is the canonical
store**; the provisioner fetches the GitHub key from it at runtime (`bw get`),
and key material only ever exists on disk as `~/.ssh/svc-github.com` (mode 600) outside
this repo. Bitwarden *item names* are acceptable in code (they are not secrets).
Because the repo is public, this discipline is load-bearing, not optional —
history is forever and the world can read it.

## What this repo is

`baseline-access` is the zero-credential entry point that breaks the first-boot
chicken-and-egg: a fresh machine can't clone the *private* repos that hold its
provisioning code until it has the GitHub SSH key, but that key lives behind
Bitwarden. This public repo is the one thing a credential-less machine can
always clone. After Bitwarden auth it makes the machine **git-ready**:

1. writes the GitHub SSH key to `~/.ssh/svc-github.com` (mode 600),
2. wires `~/.ssh/config` + `~/.ssh/known_hosts` for `github.com` (idempotent),
3. configures the global git identity (`user.name` / `user.email`),
4. verifies `ssh -T git@github.com`, then points at the next bootstrap.

Access is provisioned over **SSH only** — see the SSH-only constraint below.

It does this and **nothing more** (see Scope). The machine then proceeds to its
machine-class bootstrap — `baseline-bluefin` for laptops, the fleet flow for
control nodes — with GitHub already wired.

This file is self-sufficient by design: a fresh machine has **no**
`~/code/CLAUDE.md` carry-down at first boot, so nothing here assumes the shared
workspace context, and the script references nothing outside the repo and `$HOME`.

## Layout

| Path | Role |
|---|---|
| `baseline-access.sh` | the only executable — the first-boot provisioner |
| `README.md` | copy-pasteable first-boot recipe (clone-then-run + pinned curl) |
| `tests/` | bats suite (unit + integration); `tests/run` wrapper |
| `decisions/` | ADRs — the durable *why* |

## CLI

```bash
./baseline-access.sh                # provision (default): the whole git-ready flow
./baseline-access.sh provision      # explicit; same as the default
./baseline-access.sh help           # usage
```

`provision` runs: Bitwarden login → save GitHub key → SSH config + known_hosts →
git identity → verify → next-step.

## Key design constraints

- **GitHub key only.** Among *secrets* this provisions the GitHub service key and
  nothing else — no recovery key, no configurable item manifest. The recovery key
  reaches *other* hosts and belongs to the fleet flow.
- **GitHub key is written to disk** at `~/.ssh/svc-github.com`, mode 600 (`umask 077`).
  No key is ever loaded into ssh-agent here.
- **SSH only — never HTTPS.** The provisioned credential is an SSH key, so the
  machine is git-ready over `git@github.com:` URLs and nothing else. No
  `credential.helper`, no PAT, no `gh auth login`, and deliberately no
  `url.*.insteadOf` rewrite (global URL rewriting exceeds this rung's scope; the
  README documents it as an opt-in the operator may set themselves). The one
  intentional HTTPS use is cloning *this public repo* on a keyless first boot —
  that is the chicken-and-egg this rung exists to break, and switching it to SSH
  would make the repo unrunnable on a fresh machine. A failed HTTPS clone of a
  private repo is a wrong-URL symptom, not a failed provision.
- **Interactive Bitwarden auth only** (`bw login` / `bw unlock`). API-key /
  unattended auth (`BW_CLIENTID`/`BW_CLIENTSECRET`) is a documented future
  extension, not implemented in this cut.
- **Portable installer**: the Bitwarden CLI is not in distro package repos, so
  `install_bw` picks the first of `brew` → `npm` → `snap` that is present — never
  hardcoded to brew.
- **Idempotent**: re-running never duplicates the SSH config stanza or the
  known_hosts entry, and never clobbers an already-configured git identity.
  known_hosts presence is checked per key with `ssh-keygen -F`, so hashed
  entries (`HashKnownHosts yes`) count. The stanza is skipped only when
  `ssh -G github.com` already resolves to `~/.ssh/svc-github.com` itself — any
  other "github"-named key does not count. A half-set identity gets only its
  missing half filled; an existing value beats `GIT_IDENTITY_*`.
- **`IdentitiesOnly yes` on the stanza**: without it ssh offers every
  ssh-agent key *before* the configured file, so an agent holding a personal
  GitHub key authenticates as that account. An existing block that maps our key
  but lacks it (earlier versions of this script, fleet-control) is warned
  about, not rewritten. Verify prints the account the banner names.
- **Host keys from GitHub's API, not keyscan**: `ensure_known_hosts` pins the
  `.ssh_keys` list from `https://api.github.com/meta` (TLS-authenticated) rather
  than `ssh-keyscan`, which trusts whatever answers on port 22. Needs `curl`.
- **Key file replaced, not truncated**: the key goes to a `mktemp` file (0600)
  renamed over `~/.ssh/svc-github.com`, so a pre-existing wider mode or symlink
  never carries over.
- **Self-contained**: it does not clone/run any machine-class bootstrap, touch
  dotfiles/packages/dconf beyond git config, set hostname, or manage fleet policy.
- It keeps an **independent copy** of the Bitwarden login + key-fetch logic that
  `baseline-bluefin`'s `install github-key` also has; the two are coupled only by
  the shared Bitwarden item name below, not by code. A change to the fetch logic
  in either must be mirrored deliberately.

## Git identity

Values come from `GIT_IDENTITY_NAME` / `GIT_IDENTITY_EMAIL` when set (the
unattended path), else the operator is prompted. An already-configured identity
is left untouched. Personal identity values are **not** committed to this public
repo — they are supplied at runtime.

Recommended convention (what the prompt hints at, and what this fleet uses):

| Setting | Value | Example |
|---|---|---|
| `user.name` | the GitHub **username** | `juangalt` |
| `user.email` | the GitHub **noreply** address | `juangalt@users.noreply.github.com` |

The noreply address keeps a personal email out of commit history — load-bearing
here because commits land in public repos and history is forever — while GitHub
still attributes the commit. Using the username as `user.name` keeps authorship
aligned with the account that owns the key this script installs. Newer GitHub
accounts are issued the `<ID>+<username>@users.noreply.github.com` form; either
works provided it matches an address on the account.

## Bitwarden items

| Step | Item name | JSON path |
|---|---|---|
| save GitHub key | `fleet-policy:keys/service/github` | `.sshKey.privateKey` |

Standardized on the fleet skill's reference name — the two names
(`fleet-policy:keys/service/github` and the legacy `ssh-access service key:
github` that `baseline-bluefin` used) were fingerprint-verified as the **same
key** on 2026-07-20, and fleet's schema requires the `fleet-policy:` prefix, so
it is the name that wins. The legacy item is **retained** until the migration
tombstone so `baseline-bluefin` and the pinned `v0.1.0` one-liner keep resolving;
see `baseline-setup` ADR 0004 D3.

## Testing

```bash
tests/run                              # full suite (unit + integration)
tests/run tests/unit/test_github.bats  # one file
```

- **bats** with bats-core, bats-support, bats-assert **vendored** under
  `tests/bats.d/` — no system bats or submodule init needed.
- All external tools (`bw`, `jq`, `git`, `ssh`, `curl`, the package managers,
  `sudo`) are mocked via PATH prepend — no real system calls, no real Bitwarden
  auth, no secrets in tests. The one exception is `ssh-keygen -F`: a read-only
  lookup on the test's own `known_hosts`, left real because matching hashed
  entries means reproducing its HMAC (those tests skip if it is missing).
