#!/usr/bin/env bash
# baseline-access.sh — first-boot provisioner that makes any machine git-ready.
#
# Zero-credential entry point: from a brand-new machine, clone this PUBLIC repo
# (HTTPS, no key needed), run it, authenticate to Bitwarden interactively, and
# end up fully git-ready — the GitHub SSH key written to ~/.ssh/svc-github.com (mode 600),
# the github.com SSH config + known_hosts wired, and the git identity configured —
# so the machine can immediately clone private repos and run git.
#
# ACCESS IS SSH-ONLY. What this provisions is an SSH key, so private repos clone
# over git@github.com: URLs and nothing else. No credential.helper, no PAT, no
# `gh auth login`, no url.*.insteadOf rewrite. An https:// clone of a private repo
# failing afterwards is a wrong-URL symptom, not a failed provision. The single
# deliberate HTTPS use is cloning this public repo on a keyless first boot — the
# chicken-and-egg this script exists to break.
#
# This repo is PUBLIC: only bootstrap *logic* lives here. Every secret value stays
# in Bitwarden and renders at runtime; nothing secret is ever committed.
#
# Usage: baseline-access.sh [provision]   (provision is the default)
# Run:   baseline-access.sh help
#
# Scope: this makes the machine git-ready and NOTHING more. It does not clone or
# run any machine-class bootstrap, does not touch dotfiles/packages/dconf beyond
# git config, and provisions ONLY the GitHub service key among secrets.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; DIM=''; RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()     { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()    { echo -e "  ${RED}✘${RESET}  $*" >&2; }
info()   { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
dim()    { echo -e "       ${DIM}$*${RESET}"; }
header() { echo -e "\n${BOLD}$*${RESET}"; }
die()    { err "$*"; exit 1; }

have() { command -v "$1" &>/dev/null; }
require() {
  have "$1" || die "Required tool not found: $1"
}

# Where interactive prompts (our `read`s and bw's own login/unlock prompts) take
# their input. Under the `curl … | bash` one-liner, stdin IS the script pipe, so
# reading it yields EOF instead of the operator's keystrokes — fall back to the
# controlling terminal. With neither (CI, no tty) stdin is used and a missing
# answer dies with a clear message. BASELINE_PROMPT_IN overrides (tests).
prompt_in() {
  if [[ -n "${BASELINE_PROMPT_IN:-}" ]]; then
    printf '%s\n' "$BASELINE_PROMPT_IN"
  elif [[ -t 0 ]]; then
    printf '/dev/stdin\n'
  elif { : </dev/tty; } 2>/dev/null; then
    printf '/dev/tty\n'
  else
    printf '/dev/stdin\n'
  fi
}

# Run "$@" with stdin taken from prompt_in(). Plain stdin is inherited rather
# than re-opened via /dev/stdin, which fails when fd 0 is closed or a socket.
with_prompt_in() {
  local src
  src=$(prompt_in)
  if [[ "$src" == /dev/stdin ]]; then
    "$@"
  else
    "$@" <"$src"
  fi
}

# ── Configuration ─────────────────────────────────────────────────────────────
# Bitwarden item carrying the GitHub service key. Standardized on the fleet
# skill's reference name `fleet-policy:keys/service/github` — the same key
# material (fingerprint-verified 2026-07-20) that baseline-bluefin's
# `install github-key` fetched under the legacy name `ssh-access service key:
# github`. Fleet's schema requires the `fleet-policy:` prefix, so this is the
# name that wins. The legacy item is retained until the migration tombstone so
# the pinned v0.1.0 one-liner keeps resolving; see baseline-setup ADR 0004 D3.
GITHUB_BW_ITEM="fleet-policy:keys/service/github"
GITHUB_BW_FIELD='.sshKey.privateKey'
# Same filename fleet-control derives from its `github.com` ssh_service
# (~/.ssh/svc-<service-name>). Sharing the name means a fleet-enrolled host
# holds ONE key file that fleet audits and prunes, instead of this script
# leaving a second, orphaned copy that fleet is blind to (it only scans svc-*).
GITHUB_KEY_FILE="$HOME/.ssh/svc-github.com"

# ── Bitwarden ─────────────────────────────────────────────────────────────────

require_bw_session() {
  [[ -n "${BW_SESSION:-}" ]] || die "BW_SESSION not set — run the login sequence first"
}

# Pick the first available installer that can actually ship the Bitwarden CLI.
# Bitwarden CLI is NOT packaged in distro repos (apt/dnf/pacman), so we prefer
# brew (Bluefin and macOS), then npm, then snap — whichever the machine has.
# Echoes the installer name, or nothing if none is available.
detect_bw_installer() {
  local mgr
  for mgr in brew npm snap; do
    if have "$mgr"; then
      printf '%s\n' "$mgr"
      return 0
    fi
  done
  return 1
}

install_bw() {
  local mgr
  mgr=$(detect_bw_installer) \
    || die "No supported installer found for the Bitwarden CLI (need one of: brew, npm, snap)"
  info "Installing Bitwarden CLI via ${mgr}..."
  case "$mgr" in
    brew) brew install bitwarden-cli ;;
    npm)  npm install -g @bitwarden/cli ;;
    snap) sudo snap install bw ;;
  esac || die "Failed to install bitwarden-cli via ${mgr}"
  ok "Bitwarden CLI installed"
}

bw_login_or_unlock() {
  header "Bitwarden Login"
  have bw || install_bw
  require jq

  # The `||` fallback MUST stay OUTSIDE the command substitution. Inside it, a
  # failing pipeline appends "error" to whatever the pipeline already printed,
  # yielding a multi-line $bw_st (e.g. $'unauthenticated\nerror') that matches no
  # case branch below and dies with a mangled "Unexpected bw status". Outside, a
  # failure cleanly *replaces* the value with the sentinel. `set -o pipefail` is
  # in force, so any stage failing (including SIGPIPE from a reader that exits
  # early) fails the whole pipeline.
  local bw_st
  bw_st=$(bw status 2>/dev/null | jq -r '.status // "unknown"') || bw_st="error"

  if [[ -n "${BW_SESSION:-}" && ( "$bw_st" == "authenticated" || "$bw_st" == "unlocked" ) ]]; then
    ok "Vault already unlocked (BW_SESSION set)"
  else
    local session
    case "$bw_st" in
      unauthenticated)
        info "Logging in to Bitwarden..."
        session=$(with_prompt_in bw login --raw) || die "bw login failed"
        ;;
      locked)
        info "Unlocking Bitwarden vault..."
        session=$(with_prompt_in bw unlock --raw) || die "bw unlock failed"
        ;;
      unlocked|authenticated)
        info "Vault already unlocked — refreshing BW_SESSION"
        session=$(with_prompt_in bw unlock --raw) || die "bw unlock failed"
        ;;
      *)
        die "Unexpected bw status: ${bw_st}"
        ;;
    esac

    export BW_SESSION="$session"
    ok "BW_SESSION exported"
  fi
}

# ── GitHub key ────────────────────────────────────────────────────────────────

# True when resolved SSH config already maps the LITERAL github.com host to an
# IdentityFile whose path contains "github". Uses `ssh -G` so Include
# directives and wildcards are honoured. Deliberately does NOT also check a
# `github` alias: this script's own contract (CLAUDE.md "SSH only") is that
# plain `git@github.com:` URLs work without relying on any alias or git-level
# URL rewrite another tool might layer on top. Something else provisioning a
# `github` alias (e.g. a fleet-control insteadOf rewrite) does not mean the
# literal host is covered, and treating it as equivalent left `github.com`
# unrouted while this function reported false coverage.
ssh_config_has_github() {
  have ssh || return 1
  ssh -G github.com 2>/dev/null | grep -qi '^identityfile.*github'
}

save_github_key() {
  require bw
  require jq
  require_bw_session

  info "Fetching GitHub SSH key from Bitwarden..."
  local key
  key=$(bw get item "$GITHUB_BW_ITEM" --session "$BW_SESSION" | jq -r "$GITHUB_BW_FIELD") \
    || die "Failed to fetch '$GITHUB_BW_ITEM' from Bitwarden"

  # `jq -r` prints the literal string "null" (exit 0) when the field is
  # missing/null, so guard against that too — not just the empty string.
  [[ -n "$key" && "$key" != "null" ]] || die "GitHub SSH key is empty — check the Bitwarden item"

  mkdir -p "$HOME/.ssh"
  (umask 077; printf '%s\n' "$key" > "$GITHUB_KEY_FILE")
  ok "GitHub SSH key saved to ~/.ssh/svc-github.com"

  # Ensure SSH uses this key for github.com without needing ssh-agent.
  local ssh_config="$HOME/.ssh/config"
  if ! ssh_config_has_github; then
    (umask 077; printf '\nHost github.com\n  IdentityFile ~/.ssh/svc-github.com\n' >> "$ssh_config")
    ok "SSH config updated for github.com"
  fi
}

# ── known_hosts ───────────────────────────────────────────────────────────────

# Idempotently add github.com's host keys to ~/.ssh/known_hosts so the first
# git/ssh connection doesn't trip the interactive host-key prompt. Appends only
# when github.com is absent.
ensure_known_hosts() {
  require ssh-keyscan
  local known="$HOME/.ssh/known_hosts"
  mkdir -p "$HOME/.ssh"

  if [[ -f "$known" ]] && grep -q '^github\.com[, ]' "$known"; then
    return 0
  fi

  local keys
  keys=$(ssh-keyscan github.com 2>/dev/null) \
    || die "ssh-keyscan github.com failed"
  [[ -n "$keys" ]] || die "ssh-keyscan returned no host keys for github.com"

  (umask 077; printf '%s\n' "$keys" >> "$known")
  ok "github.com added to ~/.ssh/known_hosts"
}

# ── git identity ──────────────────────────────────────────────────────────────

# Prompt for whichever of the caller's `name` / `email` locals are still empty
# (bash dynamic scoping). Both reads share one stdin, so a single with_prompt_in
# redirect feeds them in order. `|| true`: read fails on EOF, and under `set -e`
# that would exit silently instead of reaching the "not provided" message.
prompt_git_identity() {
  if [[ -z "$name" ]]; then
    read -rp "  git user.name: " name || true
  fi
  if [[ -z "$email" ]]; then
    read -rp "  git user.email: " email || true
  fi
}

# Configure the global git identity if it isn't already set. Values come from
# GIT_IDENTITY_NAME / GIT_IDENTITY_EMAIL when set (the unattended path), else the
# operator is prompted interactively. Already-configured identities are left
# untouched — re-running never clobbers an existing name/email.
configure_git_identity() {
  require git

  local cur_name cur_email
  cur_name=$(git config --global user.name || true)
  cur_email=$(git config --global user.email || true)

  if [[ -n "$cur_name" && -n "$cur_email" ]]; then
    ok "Git identity already set ($cur_name <$cur_email>)"
    return 0
  fi

  local name="${GIT_IDENTITY_NAME:-$cur_name}"
  local email="${GIT_IDENTITY_EMAIL:-$cur_email}"

  # Only hint when we are actually about to prompt (the unattended path is silent).
  if [[ -z "$name" || -z "$email" ]]; then
    info "Recommended: your GitHub username, and your GitHub noreply email."
    dim "e.g.  user.name: octocat  ·  user.email: octocat@users.noreply.github.com"
    dim "The noreply address keeps your real email out of public commit history,"
    dim "and GitHub still attributes the commits to your account."
    dim "Find yours under GitHub → Settings → Emails."
  fi

  with_prompt_in prompt_git_identity

  [[ -n "$name"  ]] || die "git user.name not provided (set GIT_IDENTITY_NAME or answer the prompt)"
  [[ -n "$email" ]] || die "git user.email not provided (set GIT_IDENTITY_EMAIL or answer the prompt)"

  git config --global user.name  "$name"
  git config --global user.email "$email"
  ok "Git identity configured ($name <$email>)"
}

# ── Verify + next step ────────────────────────────────────────────────────────

# GitHub answers `ssh -T git@github.com` with a NON-ZERO exit and the banner
# "Hi <user>! You've successfully authenticated, but GitHub does not provide
# shell access." — so success is the banner, not the exit code.
verify_github_auth() {
  require ssh
  info "Verifying GitHub SSH authentication..."
  local out
  out=$(ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)
  if grep -qi 'successfully authenticated' <<<"$out"; then
    ok "GitHub authentication succeeded"
    return 0
  fi
  warn "Could not confirm GitHub authentication"
  dim "$out"
  return 1
}

print_next_step() {
  header "Machine is git-ready"
  info "Clone private repos over SSH — this machine has an SSH key, not HTTPS creds:"
  dim "git clone git@github.com:<owner>/<repo>.git"
  dim "https:// URLs will NOT work here — no credential helper or PAT is configured."
  info "Next step: run your machine-class bootstrap with GitHub already wired —"
  dim "most machines: baseline-setup   ·   control nodes: the fleet bootstrap"
  dim "(Bluefin laptop: still baseline-bluefin for now)"
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_provision() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
  ensure_known_hosts
  header "Git Identity"
  configure_git_identity
  header "Verify"
  verify_github_auth || true
  print_next_step
}

usage() {
  cat <<'EOF'

baseline-access — first-boot provisioner to make any machine git-ready

Usage:
  baseline-access.sh [provision]   Bitwarden login → GitHub key → SSH config +
                                   known_hosts → git identity → verify → next step
  baseline-access.sh help          Show this help

Provisions ONLY the GitHub service key (Bitwarden item:
"fleet-policy:keys/service/github"). Interactive Bitwarden auth only. Git
identity is taken from GIT_IDENTITY_NAME / GIT_IDENTITY_EMAIL when set, else
prompted; recommended values are your GitHub username and your GitHub noreply
address (<username>@users.noreply.github.com).

Access is SSH-only: afterwards, clone private repos with git@github.com: URLs.
No HTTPS credentials (credential helper, PAT, gh login) are configured.
EOF
}

main() {
  local cmd="${1:-provision}"
  case "$cmd" in
    provision)      cmd_provision ;;
    help|-h|--help) usage ;;
    *)              err "Unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
