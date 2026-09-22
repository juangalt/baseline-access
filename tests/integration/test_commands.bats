#!/usr/bin/env bats
# Integration tests — drive baseline-access.sh end to end with every external
# tool mocked. Covers the full git-ready provision flow (AC3–AC7) and the CLI.

BOOTSTRAP="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/baseline-access.sh"

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
}

# ── help / dispatch ───────────────────────────────────────────────────────────

@test "help: shows usage text" {
  run bash "$BOOTSTRAP" help
  assert_success
  assert_output --partial "first-boot provisioner"
  assert_output --partial "provision"
  assert_output --partial "fleet-policy:keys/service/github"
}

@test "--help: shows usage text" {
  run bash "$BOOTSTRAP" --help
  assert_success
  assert_output --partial "first-boot provisioner"
}

@test "unknown command: exits 1" {
  run bash "$BOOTSTRAP" bogus
  assert_failure
  assert_output --partial "Unknown command: bogus"
}

# ── full provision flow ───────────────────────────────────────────────────────

provision_mocks() {
  mock_bw_status unauthenticated
  mock_github_meta 0 "$GH_ED25519" ".status=unauthenticated" \
                   ".sshKey.privateKey=-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_ssh none authed
  mock_git_identity
  export GIT_IDENTITY_NAME="Test User"
  export GIT_IDENTITY_EMAIL="test@example.com"
}

@test "provision (default, no args): runs the whole git-ready flow" {
  provision_mocks
  run bash "$BOOTSTRAP"
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "GitHub SSH key saved"
  assert_output --partial "github.com host keys added to ~/.ssh/known_hosts"
  assert_output --partial "Git identity configured"
  assert_output --partial "GitHub authentication succeeded"
  assert_output --partial "Machine is git-ready"
  [[ -f "$HOME/.ssh/svc-github.com" ]]
  [[ "$(stat -c '%a' "$HOME/.ssh/svc-github.com")" == "600" ]]
  grep -q "^github.com" "$HOME/.ssh/known_hosts"
}

@test "provision: a missing required tool dies before Bitwarden login" {
  provision_mocks
  # PATH = mocks only: bw/jq/curl/ssh/git are mocked, ssh-keygen is not.
  only_mocks_on_path
  run bash "$BOOTSTRAP"
  restore_path
  assert_failure
  assert_output --partial "Missing required tools: ssh-keygen"
  refute_output --partial "Bitwarden Login"
  [[ ! -e "$HOME/.ssh/svc-github.com" ]]
}

@test "provision: explicit subcommand behaves the same" {
  provision_mocks
  run bash "$BOOTSTRAP" provision
  assert_success
  assert_output --partial "Machine is git-ready"
}

@test "provision: succeeds overall even when GitHub verify fails" {
  provision_mocks
  mock_ssh none denied
  run bash "$BOOTSTRAP" provision
  assert_success
  assert_output --partial "Could not confirm GitHub authentication"
  assert_output --partial "Machine is git-ready"
}

@test "provision: writes only the GitHub key — no recovery key, no ssh-agent" {
  provision_mocks
  mock_cmd_capture ssh-add 0
  mock_cmd_capture ssh-agent 0
  run bash "$BOOTSTRAP" provision
  assert_success
  [[ ! -f "$BATS_TEST_TMPDIR/ssh-add.calls" ]]
  [[ ! -f "$BATS_TEST_TMPDIR/ssh-agent.calls" ]]
  [[ ! -f "$HOME/.ssh/recovery" ]]
}

# ── curl | bash (script arrives on stdin) ────────────────────────────────────

@test "piped script: prompts read the prompt source, not the script pipe" {
  provision_mocks
  unset GIT_IDENTITY_NAME GIT_IDENTITY_EMAIL
  printf 'Piped User\npiped@example.com\n' > "$BATS_TEST_TMPDIR/answers"
  export BASELINE_PROMPT_IN="$BATS_TEST_TMPDIR/answers"
  run bash -c "cat '$BOOTSTRAP' | bash"
  assert_success
  assert_output --partial "Git identity configured (Piped User <piped@example.com>)"
  assert_output --partial "Machine is git-ready"
}

@test "piped script: no terminal and no answer dies with a clear message" {
  provision_mocks
  unset GIT_IDENTITY_NAME BASELINE_PROMPT_IN
  # Pre-fix, read hit EOF under set -e and the script exited 1 silently.
  run setsid -w bash -c "cat '$BOOTSTRAP' | bash"
  assert_failure
  assert_output --partial "git user.name not provided"
}

@test "script run from its file: piped answers on stdin still feed the prompts" {
  provision_mocks
  unset GIT_IDENTITY_NAME GIT_IDENTITY_EMAIL BASELINE_PROMPT_IN
  run bash -c "printf 'Stdin User\nstdin@example.com\n' | bash '$BOOTSTRAP'"
  assert_success
  assert_output --partial "Git identity configured (Stdin User <stdin@example.com>)"
}
