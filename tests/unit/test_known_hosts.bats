#!/usr/bin/env bats
# Tests for: ensure_known_hosts()
# Covers AC5 (idempotent github.com entry in ~/.ssh/known_hosts), keys sourced
# from GitHub's meta API over TLS rather than trust-on-first-use ssh-keyscan.

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
  command -v ssh-keygen >/dev/null || skip "ssh-keygen not installed"
  KNOWN="$HOME/.ssh/known_hosts"
  BOTH_KEYS="$GH_ED25519"$'\n'"$GH_ECDSA"
}

@test "ensure_known_hosts: exits 1 when curl absent" {
  only_mocks_on_path
  run ensure_known_hosts
  restore_path
  assert_failure
  assert_output --partial "Required tool not found: curl"
}

@test "ensure_known_hosts: fetches keys from GitHub's meta API, not ssh-keyscan" {
  mock_github_meta 0 "$BOTH_KEYS"
  mock_cmd_capture ssh-keyscan 0
  run ensure_known_hosts
  assert_success
  grep -q "https://api.github.com/meta" "$BATS_TEST_TMPDIR/curl.calls"
  [[ ! -f "$BATS_TEST_TMPDIR/ssh-keyscan.calls" ]]
}

@test "ensure_known_hosts: appends every published key on first run, mode 600" {
  mock_github_meta 0 "$BOTH_KEYS"
  run ensure_known_hosts
  assert_success
  assert_output --partial "host keys added to ~/.ssh/known_hosts (2)"
  grep -qxF "github.com $GH_ED25519" "$KNOWN"
  grep -qxF "github.com $GH_ECDSA" "$KNOWN"
  [[ "$(stat -c '%a' "$KNOWN")" == "600" ]]
}

@test "ensure_known_hosts: creates ~/.ssh at mode 700 if missing" {
  mock_github_meta 0 "$BOTH_KEYS"
  [[ ! -d "$HOME/.ssh" ]]
  run ensure_known_hosts
  assert_success
  [[ "$(stat -c '%a' "$HOME/.ssh")" == "700" ]]
}

@test "ensure_known_hosts: second run adds no duplicate" {
  mock_github_meta 0 "$BOTH_KEYS"
  ensure_known_hosts >/dev/null
  run ensure_known_hosts
  assert_success
  assert_output --partial "already in ~/.ssh/known_hosts"
  [[ "$(wc -l < "$KNOWN")" -eq 2 ]]
}

@test "ensure_known_hosts: hashed entries (HashKnownHosts) count as present" {
  mkdir -p "$HOME/.ssh"
  printf 'github.com %s\ngithub.com %s\n' "$GH_ED25519" "$GH_ECDSA" > "$KNOWN"
  ssh-keygen -H -f "$KNOWN" >/dev/null 2>&1
  rm -f "$KNOWN.old"
  ! grep -q '^github\.com' "$KNOWN"   # really hashed
  mock_github_meta 0 "$BOTH_KEYS"
  run ensure_known_hosts
  assert_success
  assert_output --partial "already in ~/.ssh/known_hosts"
  [[ "$(wc -l < "$KNOWN")" -eq 2 ]]
}

@test "ensure_known_hosts: adds only the keys that are missing" {
  mkdir -p "$HOME/.ssh"
  printf 'github.com %s\n' "$GH_ED25519" > "$KNOWN"
  mock_github_meta 0 "$BOTH_KEYS"
  run ensure_known_hosts
  assert_success
  assert_output --partial "(1)"
  [[ "$(grep -cF "$GH_ED25519" "$KNOWN")" -eq 1 ]]
  grep -qxF "github.com $GH_ECDSA" "$KNOWN"
}

@test "ensure_known_hosts: a stale github.com key does not block the current ones" {
  # e.g. GitHub's RSA key revoked in 2023: presence of *a* github.com entry is
  # not presence of the published keys.
  mkdir -p "$HOME/.ssh"
  printf 'github.com %s\n' "$GH_ECDSA" > "$KNOWN"
  mock_github_meta 0 "$GH_ED25519"
  run ensure_known_hosts
  assert_success
  grep -qxF "github.com $GH_ED25519" "$KNOWN"
  grep -qxF "github.com $GH_ECDSA" "$KNOWN"   # existing entries left alone
}

@test "ensure_known_hosts: dies when the API fetch fails" {
  mock_github_meta 22 "$BOTH_KEYS"
  run ensure_known_hosts
  assert_failure
  assert_output --partial "Failed to fetch github.com host keys"
  [[ ! -f "$KNOWN" ]]
}

@test "ensure_known_hosts: dies when the API returns no keys" {
  mock_github_meta 0 ""
  run ensure_known_hosts
  assert_failure
  assert_output --partial "returned no SSH host keys"
}
