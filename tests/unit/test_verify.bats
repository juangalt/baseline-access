#!/usr/bin/env bats
# Tests for: verify_github_auth(), print_next_step()
# Covers AC7 (the non-zero "successfully authenticated" banner is treated as
# success, and a next-step message is printed).

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

@test "verify_github_auth: treats the non-zero auth banner as success" {
  # GitHub's `ssh -T` exits 1 even on success — the banner is the signal.
  mock_ssh none authed
  run verify_github_auth
  assert_success
  assert_output --partial "GitHub authentication succeeded"
}

@test "verify_github_auth: reports failure when banner absent" {
  mock_ssh none denied
  run verify_github_auth
  assert_failure
  assert_output --partial "Could not confirm GitHub authentication"
}

@test "verify_github_auth: exits 1 when ssh absent" {
  only_mocks_on_path
  run verify_github_auth
  restore_path
  assert_failure
  assert_output --partial "Required tool not found: ssh"
}

@test "print_next_step: names the machine-class bootstraps" {
  run print_next_step
  assert_success
  assert_output --partial "git-ready"
  assert_output --partial "most machines: baseline-setup"
  assert_output --partial "still baseline-bluefin"
  assert_output --partial "fleet bootstrap"
}
