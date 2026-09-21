# baseline-access

The **public** first-boot entry point that makes any brand-new machine
**git-ready** with zero prior credentials. It fetches the GitHub SSH key from
Bitwarden, wires `~/.ssh` for `github.com`, and configures your git identity — so
the machine can immediately clone private repos over **SSH** and run git.

It provisions **SSH access only** — no HTTPS credentials are ever set up. See
[SSH, not HTTPS](#ssh-not-https) for what that means when you clone.

Only bootstrap *logic* is public here; every secret stays in Bitwarden behind
Bitwarden auth and is never committed.

## Quick start (clone-then-run — canonical)

A fresh machine can clone this public repo over **HTTPS with no key**, and you can
read the whole script before running it:

```bash
git clone https://github.com/juangalt/baseline-access.git ~/baseline-access
cd ~/baseline-access
./baseline-access.sh            # Bitwarden login → GitHub key → SSH config +
                                # known_hosts → git identity → verify → next step
```

> **This is the one command that is deliberately HTTPS.** It has to be: the whole
> point of this rung is to break the chicken-and-egg on a machine that has no key
> yet, and this public repo is the one thing such a machine can always clone. An
> `git@github.com:` URL here would require the very key this script installs.
> Every clone *after* provisioning should use SSH — see below.

You'll be prompted for Bitwarden (email + master password + 2FA) and, if not
already set, your git identity. To avoid the identity prompt:

```bash
GIT_IDENTITY_NAME="juangalt" \
GIT_IDENTITY_EMAIL="juangalt@users.noreply.github.com" \
  ./baseline-access.sh
```

See [Git identity](#git-identity) for the recommended values.

When it finishes, the machine is git-ready — clone your private repos over SSH:

```bash
git clone git@github.com:juangalt/<repo>.git ~/code/<repo>
```

Then proceed to your machine-class bootstrap (`baseline-setup` for most machines,
`baseline-bluefin` for Bluefin laptops, the fleet flow for control nodes).

## Quick start (curl one-liner — convenience)

For the impatient. The raw URL is **pinned to a release tag** (not `main`) so the
bytes piped into your shell are reviewable and stable:

```bash
curl -fsSL https://raw.githubusercontent.com/juangalt/baseline-access/v0.3.0/baseline-access.sh | bash
```

Prefer clone-then-run when you can — piping remote code into a shell runs it
unread. The pinned tag exists precisely so you *can* read it first:
<https://github.com/juangalt/baseline-access/blob/v0.3.0/baseline-access.sh>.

(This URL is HTTPS for the same reason as the clone above: no key exists yet.)

> The pre-rename `v0.1.0` one-liner (`.../baseline-github/v0.1.0/baseline-github.sh`)
> still resolves via GitHub's rename redirect and the retained Bitwarden item, so
> machines pinned to it keep working until the migration tombstone.

## SSH, not HTTPS

This script provisions **SSH** access to GitHub, and only SSH. It writes the key
to `~/.ssh/svc-github.com`, wires `~/.ssh/config` and `~/.ssh/known_hosts`, and verifies
`ssh -T git@github.com`.

It sets up **no HTTPS credentials whatsoever** — no `credential.helper`, no
personal access token, no `gh auth login`. That is by design: the Bitwarden item
this rung provisions holds an SSH key, and nothing else.

So after provisioning, clone with **SSH URLs**:

```bash
git clone git@github.com:juangalt/<repo>.git       # ✅ works — uses ~/.ssh/svc-github.com
git clone https://github.com/juangalt/<repo>.git   # ❌ no credentials — will fail
```

An HTTPS clone of a **private** repo fails like this:

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

…or hangs on an interactive username/password prompt that no password can
satisfy (GitHub stopped accepting account passwords for git in 2021).

**This is not a broken provision.** It means the URL bypassed the key entirely.
To tell the two apart:

```bash
ssh -T git@github.com
```

If that answers `Hi <user>! You've successfully authenticated, but GitHub does
not provide shell access.` then your access is fine and the **URL** is the
problem, not the setup. (That command exits non-zero even on success — judge it
by the banner, not the exit code.)

To fix an existing clone that was made over HTTPS:

```bash
git remote set-url origin git@github.com:juangalt/<repo>.git
```

### Optional: make HTTPS URLs use the SSH key

If you'd rather not think about it — so pasted HTTPS URLs, and tools that default
to them, transparently use the key:

```bash
git config --global url."git@github.com:".insteadOf "https://github.com/"
```

`baseline-access` does **not** set this for you. It rewrites every GitHub URL
globally, which is a broader footprint than this rung's scope, and it would also
rewrite the public clone URL above. It's a reasonable default on a
single-operator machine; skip it on shared or CI boxes where the HTTPS path is
someone else's to configure.

## Git identity

The provisioner sets the global `user.name` / `user.email` when they aren't
already set. An existing identity is **never** clobbered — re-running is safe.

Recommended convention:

| Setting | Use | Example |
|---|---|---|
| `user.name` | your GitHub **username** | `juangalt` |
| `user.email` | your GitHub **noreply** address | `juangalt@users.noreply.github.com` |

```bash
GIT_IDENTITY_NAME="juangalt" \
GIT_IDENTITY_EMAIL="juangalt@users.noreply.github.com" \
  ./baseline-access.sh
```

**Why the noreply address:** it keeps your real email address out of every commit
you author — including in public repos, and this one is public — while GitHub
still attributes the commit to your account. Committing a personal address
publishes it permanently in git history, where it is trivially scraped.

**Why the username as `user.name`:** authorship then reads the same as the
account that owns the key this script installs, so commits, the key, and the
GitHub account all line up.

Find your exact noreply address under **GitHub → Settings → Emails**. Newer
accounts are issued the `<ID>+<username>@users.noreply.github.com` form; either
form works, as long as it matches an address on your account — otherwise GitHub
will not attribute the commits to you.

Personal identity values are supplied at runtime and are **not** committed to
this public repo.

## What it does

1. Ensures `bw` + `jq` are present (installs the Bitwarden CLI via brew / npm /
   snap if absent), then `bw login` / `bw unlock` interactively.
2. Fetches the GitHub service key and writes `~/.ssh/svc-github.com` (mode 600,
   replacing any existing file rather than inheriting its permissions).
3. Ensures the `github.com` stanza in `~/.ssh/config`, and GitHub's host keys in
   `~/.ssh/known_hosts` — taken from GitHub's API over TLS
   (`https://api.github.com/meta`), not trusted from whatever answers
   `ssh-keyscan`, and appended only if missing, hashed entries included (safe to
   re-run).
4. Configures the global git identity if unset.
5. Verifies `ssh -T git@github.com` and prints the next step.

## What it does NOT do

Provisions **only** the GitHub key among secrets (no recovery key), and only over
**SSH** — it configures no HTTPS credentials, no credential helper, no PAT, and
no `gh` login. Does not clone or run any machine-class bootstrap, touch
dotfiles/packages/dconf beyond git config, set hostname, or manage fleet policy.
That's the next rung, not this one.

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
