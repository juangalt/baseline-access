#!/usr/bin/env bats
# Tests for: configure_git_identity()
# Covers AC6 (git config --global user.email and user.name are set).

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

@test "configure_git_identity: sets name and email from env vars" {
  mock_git_identity
  export GIT_IDENTITY_NAME="Test User"
  export GIT_IDENTITY_EMAIL="test@example.com"
  run configure_git_identity
  assert_success
  assert_output --partial "Git identity configured"
  grep -q 'config --global user.name Test User' "$BATS_TEST_TMPDIR/git.calls"
  grep -q 'config --global user.email test@example.com' "$BATS_TEST_TMPDIR/git.calls"
}

@test "configure_git_identity: persisted values are readable back" {
  mock_git_identity
  export GIT_IDENTITY_NAME="Test User"
  export GIT_IDENTITY_EMAIL="test@example.com"
  configure_git_identity >/dev/null
  run git config --global user.name
  assert_success
  assert_output "Test User"
  run git config --global user.email
  assert_success
  assert_output "test@example.com"
}

@test "configure_git_identity: leaves an already-configured identity untouched" {
  mock_git_identity
  seed_git_identity "Existing Name" "existing@example.com"
  export GIT_IDENTITY_NAME="Should Not Win"
  export GIT_IDENTITY_EMAIL="shouldnot@example.com"
  run configure_git_identity
  assert_success
  assert_output --partial "already set"
  # No write calls were issued (only the two reads).
  ! grep -q 'Should Not Win' "$BATS_TEST_TMPDIR/git.calls"
}

@test "configure_git_identity: dies when name unavailable and non-interactive" {
  mock_git_identity
  export GIT_IDENTITY_EMAIL="test@example.com"
  unset GIT_IDENTITY_NAME
  # stdin closed → read returns empty → name stays empty → die.
  run configure_git_identity </dev/null
  assert_failure
  assert_output --partial "git user.name not provided"
}

@test "configure_git_identity: exits 1 when git absent" {
  only_mocks_on_path
  run configure_git_identity
  restore_path
  assert_failure
  assert_output --partial "Required tool not found: git"
}
