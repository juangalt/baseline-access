#!/usr/bin/env bats
# Tests for: bw_login_or_unlock(), detect_bw_installer(), install_bw()
# Covers AC3 (interactive Bitwarden auth + install-when-absent) and
# AC8 (portable package-manager detection, not hardcoded to brew).

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Package-manager detection (AC8) ───────────────────────────────────────────

@test "detect_bw_installer: prefers brew when present" {
  mock_cmd brew 0
  mock_cmd npm 0
  run detect_bw_installer
  assert_success
  assert_output "brew"
}

@test "detect_bw_installer: falls back to npm when brew absent" {
  mock_cmd npm 0
  only_mocks_on_path
  run detect_bw_installer
  restore_path
  assert_success
  assert_output "npm"
}

@test "detect_bw_installer: falls back to snap when brew and npm absent" {
  mock_cmd snap 0
  only_mocks_on_path
  run detect_bw_installer
  restore_path
  assert_success
  assert_output "snap"
}

@test "detect_bw_installer: fails when no supported installer present" {
  only_mocks_on_path
  run detect_bw_installer
  restore_path
  assert_failure
}

@test "install_bw: installs via brew when brew present" {
  mock_cmd_capture brew 0
  only_mocks_on_path
  run install_bw
  restore_path
  assert_success
  assert_output --partial "via brew"
  grep -q "install bitwarden-cli" "$BATS_TEST_TMPDIR/brew.calls"
}

@test "install_bw: installs via npm when only npm present" {
  mock_cmd_capture npm 0
  only_mocks_on_path
  run install_bw
  restore_path
  assert_success
  assert_output --partial "via npm"
  grep -q "install -g @bitwarden/cli" "$BATS_TEST_TMPDIR/npm.calls"
}

@test "install_bw: dies when no installer is available" {
  only_mocks_on_path
  run install_bw
  restore_path
  assert_failure
  assert_output --partial "No supported installer"
}

# ── bw_login_or_unlock: install-when-absent (AC3) ─────────────────────────────

@test "bw_login_or_unlock: installs bw via brew when absent" {
  mock_jq_value "unlocked"
  mock_cmd_capture brew 0
  only_mocks_on_path
  run bw_login_or_unlock
  restore_path
  [[ -f "$BATS_TEST_TMPDIR/brew.calls" ]]
  grep -q "install bitwarden-cli" "$BATS_TEST_TMPDIR/brew.calls"
}

@test "bw_login_or_unlock: dies when bw absent and no installer present" {
  mock_jq_value "unlocked"
  only_mocks_on_path
  run bw_login_or_unlock
  restore_path
  assert_failure
  assert_output --partial "No supported installer"
}

@test "bw_login_or_unlock: exits 1 when jq is absent" {
  mock_bw_status unlocked
  only_mocks_on_path
  run bw_login_or_unlock
  restore_path
  assert_failure
  assert_output --partial "Required tool not found: jq"
}

# ── bw_login_or_unlock: vault state (AC3) ─────────────────────────────────────

@test "bw_login_or_unlock: skips login when BW_SESSION set and vault unlocked" {
  mock_bw_status unlocked
  mock_jq_value "unlocked"
  export BW_SESSION="existing-token"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Vault already unlocked"
}

@test "bw_login_or_unlock: calls bw login when vault unauthenticated" {
  mock_bw_status unauthenticated
  mock_jq_value "unauthenticated"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Logging in"
  assert_output --partial "BW_SESSION exported"
}

@test "bw_login_or_unlock: calls bw unlock when vault locked" {
  mock_bw_status locked
  mock_jq_value "locked"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Unlocking"
  assert_output --partial "BW_SESSION exported"
}

@test "bw_login_or_unlock: refreshes BW_SESSION when vault unlocked but no session" {
  mock_bw_status unlocked
  mock_jq_value "unlocked"
  unset BW_SESSION
  run bw_login_or_unlock
  assert_success
  assert_output --partial "refreshing BW_SESSION"
  assert_output --partial "BW_SESSION exported"
}

@test "bw_login_or_unlock: exits 1 on unexpected vault status" {
  mock_bw_status "bogus"
  mock_jq_value "bogus"
  run bw_login_or_unlock
  assert_failure
  assert_output --partial "Unexpected bw status: bogus"
}

@test "bw_login_or_unlock: exits 1 when bw login fails" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"unauthenticated"}\n'"'"' ;;\n'
    printf '  login) exit 1 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  mock_jq_value "unauthenticated"
  run bw_login_or_unlock
  assert_failure
  assert_output --partial "bw login failed"
}
