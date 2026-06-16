# baseline-github

The **public** first-boot entry point that makes any brand-new machine
**git-ready** with zero prior credentials. It fetches the GitHub SSH key from
Bitwarden, wires `~/.ssh` for `github.com`, and configures your git identity — so
the machine can immediately clone private repos and run git.

Only bootstrap *logic* is public here; every secret stays in Bitwarden behind
Bitwarden auth and is never committed.

## Quick start (clone-then-run — canonical)

A fresh machine can clone this public repo over **HTTPS with no key**, and you can
read the whole script before running it:

```bash
git clone https://github.com/juangalt/baseline-github.git ~/baseline-github
cd ~/baseline-github
./baseline-github.sh            # Bitwarden login → GitHub key → SSH config +
                                # known_hosts → git identity → verify → next step
```

You'll be prompted for Bitwarden (email + master password + 2FA) and, if not
already set, your git identity. To avoid the identity prompt:

```bash
GIT_IDENTITY_NAME="Your Name" GIT_IDENTITY_EMAIL="you@example.com" \
  ./baseline-github.sh
```

When it finishes, the machine is git-ready — proceed to your machine-class
bootstrap (`baseline-bluefin` for laptops, the fleet flow for control nodes).

## Quick start (curl one-liner — convenience)

For the impatient. The raw URL is **pinned to a release tag** (not `main`) so the
bytes piped into your shell are reviewable and stable:

```bash
curl -fsSL https://raw.githubusercontent.com/juangalt/baseline-github/v0.1.0/baseline-github.sh | bash
```

Prefer clone-then-run when you can — piping remote code into a shell runs it
unread. The pinned tag exists precisely so you *can* read it first:
<https://github.com/juangalt/baseline-github/blob/v0.1.0/baseline-github.sh>.

## What it does

1. Ensures `bw` + `jq` are present (installs the Bitwarden CLI via brew / npm /
   snap if absent), then `bw login` / `bw unlock` interactively.
2. Fetches the GitHub service key and writes `~/.ssh/github` (mode 600).
3. Ensures the `github.com` stanza in `~/.ssh/config` and host keys in
   `~/.ssh/known_hosts` — appending only if absent (safe to re-run).
4. Configures the global git identity if unset.
5. Verifies `ssh -T git@github.com` and prints the next step.

## What it does NOT do

Provisions **only** the GitHub key among secrets (no recovery key). Does not
clone or run any machine-class bootstrap, touch dotfiles/packages/dconf beyond
git config, set hostname, or manage fleet policy. That's the next rung, not this
one.

> **Future extension:** unattended Bitwarden auth via API key
> (`BW_CLIENTID`/`BW_CLIENTSECRET`, `bw login --apikey`) is not implemented in
> this cut — first boot is interactive only.

## Tests

```bash
tests/run
```

bats (vendored under `tests/bats.d/`) with every external tool mocked — no system
bats, no real Bitwarden auth, no secrets. See `CLAUDE.md` for the design and the
Bitwarden item name; `decisions/` for the load-bearing choices.
