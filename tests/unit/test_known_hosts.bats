#!/usr/bin/env bats
# Tests for: ensure_known_hosts()
# Covers AC5 (idempotent github.com entry in ~/.ssh/known_hosts).

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

@test "ensure_known_hosts: exits 1 when ssh-keyscan absent" {
  only_mocks_on_path
  run ensure_known_hosts
  restore_path
  assert_failure
  assert_output --partial "Required tool not found: ssh-keyscan"
}

@test "ensure_known_hosts: appends github.com host keys on first run" {
  mock_ssh_keyscan 0 "github.com ssh-ed25519 AAAAFAKEKEYMATERIAL"
  run ensure_known_hosts
  assert_success
  assert_output --partial "github.com added"
  [[ -f "$HOME/.ssh/known_hosts" ]]
  grep -q "^github.com ssh-ed25519" "$HOME/.ssh/known_hosts"
  [[ "$(stat -c '%a' "$HOME/.ssh/known_hosts")" == "600" ]]
}

@test "ensure_known_hosts: creates ~/.ssh if missing" {
  mock_ssh_keyscan 0 "github.com ssh-ed25519 AAAAFAKEKEYMATERIAL"
  [[ ! -d "$HOME/.ssh" ]]
  run ensure_known_hosts
  assert_success
  [[ -d "$HOME/.ssh" ]]
}

@test "ensure_known_hosts: second run adds no duplicate" {
  mock_ssh_keyscan 0 "github.com ssh-ed25519 AAAAFAKEKEYMATERIAL"
  ensure_known_hosts >/dev/null
  run ensure_known_hosts
  assert_success
  [[ "$(grep -c '^github.com' "$HOME/.ssh/known_hosts")" -eq 1 ]]
}

@test "ensure_known_hosts: skips when github.com already present" {
  mkdir -p "$HOME/.ssh"
  printf 'github.com ssh-rsa PREEXISTING\n' > "$HOME/.ssh/known_hosts"
  # keyscan exits non-zero — must NOT be reached since entry already exists.
  mock_ssh_keyscan 1 ""
  run ensure_known_hosts
  assert_success
  refute_output --partial "github.com added"
  [[ "$(grep -c '^github.com' "$HOME/.ssh/known_hosts")" -eq 1 ]]
}

@test "ensure_known_hosts: dies when keyscan fails" {
  mock_ssh_keyscan 1 ""
  run ensure_known_hosts
  assert_failure
  assert_output --partial "ssh-keyscan github.com failed"
}

@test "ensure_known_hosts: dies when keyscan returns nothing" {
  mock_ssh_keyscan 0 ""
  run ensure_known_hosts
  assert_failure
  assert_output --partial "no host keys"
}
