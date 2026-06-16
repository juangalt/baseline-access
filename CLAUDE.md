# baseline-github

**Category: baseline** — the public first-boot rung that makes any brand-new
machine git-ready, per `meta-ai-dev/decisions/0003-repo-taxonomy-by-type.md`.

This repo is **PUBLIC**. Only bootstrap *logic* lives here so a credential-less
machine can clone it over HTTPS and read every byte before running it. No secret
value is ever committed — they render from Bitwarden at runtime.

## Secrets discipline

Never commit secrets, credentials, API keys, private keys, or personal key
material — not in code, tests, or git history. **Bitwarden is the canonical
store**; the provisioner fetches the GitHub key from it at runtime (`bw get`),
and key material only ever exists on disk as `~/.ssh/github` (mode 600) outside
this repo. Bitwarden *item names* are acceptable in code (they are not secrets).
Because the repo is public, this discipline is load-bearing, not optional —
history is forever and the world can read it.

## What this repo is

`baseline-github` is the zero-credential entry point that breaks the first-boot
chicken-and-egg: a fresh machine can't clone the *private* repos that hold its
provisioning code until it has the GitHub SSH key, but that key lives behind
Bitwarden. This public repo is the one thing a credential-less machine can
always clone. After Bitwarden auth it makes the machine **git-ready**:

1. writes the GitHub SSH key to `~/.ssh/github` (mode 600),
2. wires `~/.ssh/config` + `~/.ssh/known_hosts` for `github.com` (idempotent),
3. configures the global git identity (`user.name` / `user.email`),
4. verifies `ssh -T git@github.com`, then points at the next bootstrap.

It does this and **nothing more** (see Scope). The machine then proceeds to its
machine-class bootstrap — `baseline-bluefin` for laptops, the fleet flow for
control nodes — with GitHub already wired.

This file is self-sufficient by design: a fresh machine has **no**
`~/code/CLAUDE.md` carry-down at first boot, so nothing here assumes the shared
workspace context, and the script references nothing outside the repo and `$HOME`.

## Layout

| Path | Role |
|---|---|
| `baseline-github.sh` | the only executable — the first-boot provisioner |
| `README.md` | copy-pasteable first-boot recipe (clone-then-run + pinned curl) |
| `tests/` | bats suite (unit + integration); `tests/run` wrapper |
| `decisions/` | ADRs — the durable *why* |

## CLI

```bash
./baseline-github.sh                # provision (default): the whole git-ready flow
./baseline-github.sh provision      # explicit; same as the default
./baseline-github.sh help           # usage
```

`provision` runs: Bitwarden login → save GitHub key → SSH config + known_hosts →
git identity → verify → next-step.

## Key design constraints

- **GitHub key only.** Among *secrets* this provisions the GitHub service key and
  nothing else — no recovery key, no configurable item manifest. The recovery key
  reaches *other* hosts and belongs to the fleet flow.
- **GitHub key is written to disk** at `~/.ssh/github`, mode 600 (`umask 077`).
  No key is ever loaded into ssh-agent here.
- **Interactive Bitwarden auth only** (`bw login` / `bw unlock`). API-key /
  unattended auth (`BW_CLIENTID`/`BW_CLIENTSECRET`) is a documented future
  extension, not implemented in this cut.
- **Portable installer**: the Bitwarden CLI is not in distro package repos, so
  `install_bw` picks the first of `brew` → `npm` → `snap` that is present — never
  hardcoded to brew.
- **Idempotent**: re-running never duplicates the SSH config stanza or the
  known_hosts entry, and never clobbers an already-configured git identity.
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

## Bitwarden items

| Step | Item name | JSON path |
|---|---|---|
| save GitHub key | `ssh-access service key: github` | `.sshKey.privateKey` |

The item name is reused verbatim from `baseline-bluefin` (the two are the laptop
first-boot path and must agree). Reconciling this name with the fleet skill's
`fleet-policy:keys/service/github` — if they point at the same key material — is a
separate concern, not this repo's job.

## Testing

```bash
tests/run                              # full suite (unit + integration)
tests/run tests/unit/test_github.bats  # one file
```

- **bats** with bats-core, bats-support, bats-assert **vendored** under
  `tests/bats.d/` — no system bats or submodule init needed.
- All external tools (`bw`, `jq`, `git`, `ssh`, `ssh-keyscan`, the package
  managers, `sudo`) are mocked via PATH prepend — no real system calls, no real
  Bitwarden auth, no secrets in tests.
