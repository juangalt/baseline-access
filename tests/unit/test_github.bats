#!/usr/bin/env bats
# Tests for: save_github_key()
# Covers AC4 (key written to ~/.ssh/svc-github.com mode 600 from the named Bitwarden item)
# and AC5 (idempotent ~/.ssh/config github stanza).

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
  mock_ssh none
}

# ── Tool / precondition tests ─────────────────────────────────────────────────

@test "save_github_key: exits 1 when bw is absent" {
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  only_mocks_on_path
  run save_github_key
  restore_path
  assert_failure
  assert_output --partial "Required tool not found: bw"
}

@test "save_github_key: exits 1 when BW_SESSION is unset" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  unset BW_SESSION
  run save_github_key
  assert_failure
  assert_output --partial "BW_SESSION not set"
}

@test "save_github_key: exits 1 when bw get fails" {
  mock_bw_get_fail unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_failure
  assert_output --partial "Failed to fetch"
}

@test "save_github_key: exits 1 when key is empty" {
  mock_bw_status unlocked
  mock_jq_value ""
  export BW_SESSION="fake"
  run save_github_key
  assert_failure
  assert_output --partial "GitHub SSH key is empty"
}

@test "save_github_key: exits 1 when field is missing (jq prints literal null)" {
  # bw returns an item without .sshKey.privateKey → jq -r emits "null" (exit 0),
  # which must not be written to ~/.ssh/svc-github.com as if it were a real key.
  mock_bw_status unlocked
  mock_jq_value "null"
  export BW_SESSION="fake"
  run save_github_key
  assert_failure
  assert_output --partial "GitHub SSH key is empty"
  [[ ! -f "$HOME/.ssh/svc-github.com" ]]
}

# ── Key written (AC4) ─────────────────────────────────────────────────────────

@test "save_github_key: writes key to ~/.ssh/svc-github.com with 600 permissions" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  assert_output --partial "GitHub SSH key saved"
  [[ -f "$HOME/.ssh/svc-github.com" ]]
  [[ "$(stat -c '%a' "$HOME/.ssh/svc-github.com")" == "600" ]]
  [[ "$(cat "$HOME/.ssh/svc-github.com")" == "-----BEGIN OPENSSH PRIVATE KEY-----" ]]
}

@test "save_github_key: tightens an existing key file's wider mode to 600" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mkdir -p "$HOME/.ssh"
  printf 'OLD\n' > "$HOME/.ssh/svc-github.com"
  chmod 644 "$HOME/.ssh/svc-github.com"
  run save_github_key
  assert_success
  [[ "$(stat -c '%a' "$HOME/.ssh/svc-github.com")" == "600" ]]
  [[ "$(cat "$HOME/.ssh/svc-github.com")" == "-----BEGIN OPENSSH PRIVATE KEY-----" ]]
}

@test "save_github_key: replaces a symlinked key file instead of writing through it" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mkdir -p "$HOME/.ssh"
  printf 'TARGET\n' > "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.ssh/svc-github.com"
  run save_github_key
  assert_success
  [[ ! -L "$HOME/.ssh/svc-github.com" ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/elsewhere")" == "TARGET" ]]
  [[ "$(stat -c '%a' "$HOME/.ssh/svc-github.com")" == "600" ]]
}

@test "save_github_key: leaves no temp file behind" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  [[ -z "$(find "$HOME/.ssh" -name '.svc-github.com.*')" ]]
}

@test "save_github_key: creates ~/.ssh if missing" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  [[ ! -d "$HOME/.ssh" ]]
  run save_github_key
  assert_success
  [[ -d "$HOME/.ssh" ]]
}

@test "save_github_key: fetches the canonical Bitwarden item name" {
  # bw mock records its args; assert the exact item name is requested.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/bw.calls"
    printf 'exit 0\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  grep -q "get item fleet-policy:keys/service/github" "$BATS_TEST_TMPDIR/bw.calls"
}

@test "save_github_key: does not load any key into ssh-agent" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd_capture ssh-add 0
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  [[ ! -f "$BATS_TEST_TMPDIR/ssh-add.calls" ]]
}

# ── SSH config idempotency (AC5) ──────────────────────────────────────────────

@test "save_github_key: creates ssh config with github.com entry at mode 600" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  assert_output --partial "SSH config updated"
  [[ -f "$HOME/.ssh/config" ]]
  grep -q "Host github.com" "$HOME/.ssh/config"
  grep -q "IdentityFile ~/.ssh/svc-github.com" "$HOME/.ssh/config"
  grep -q "IdentitiesOnly yes" "$HOME/.ssh/config"
  [[ "$(stat -c '%a' "$HOME/.ssh/config")" == "600" ]]
}

@test "save_github_key: skips ssh config if github.com entry already exists" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh direct
  run save_github_key
  assert_success
  refute_output --partial "SSH config updated"
  refute_output --partial "IdentitiesOnly"
  refute_output --partial "Another IdentityFile"
}

@test "save_github_key: warns when existing github.com block lacks IdentitiesOnly" {
  # Without IdentitiesOnly, ssh offers agent keys first, so a personal key in
  # the agent authenticates as the wrong account. The block may be managed by
  # something else (fleet-control), so it is flagged, not rewritten.
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh direct authed no
  run save_github_key
  assert_success
  refute_output --partial "SSH config updated"
  assert_output --partial "resolves 'IdentitiesOnly no'"
  [[ ! -e "$HOME/.ssh/config" ]]
}

@test "save_github_key: warns when IdentitiesOnly still resolves no after appending" {
  # ssh keeps the FIRST IdentitiesOnly it sees, so an earlier `Host *` with
  # `IdentitiesOnly no` overrides the `yes` in our appended stanza.
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh none authed no
  run save_github_key
  assert_success
  assert_output --partial "SSH config updated"
  assert_output --partial "resolves 'IdentitiesOnly no'"
}

@test "save_github_key: warns when another IdentityFile is tried before ours" {
  # IdentityFiles accumulate in file order and IdentitiesOnly does not filter
  # configured files, so an earlier github.com block's personal key wins.
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh 'path:~/.ssh/github_personal|~/.ssh/svc-github.com'
  run save_github_key
  assert_success
  refute_output --partial "SSH config updated"
  assert_output --partial "Another IdentityFile is tried before"
}

@test "ssh_config_github_key_first: true only when our key is listed first" {
  mock_ssh 'path:~/.ssh/svc-github.com|~/.ssh/github_personal'
  run ssh_config_github_key_first
  assert_success
  mock_ssh 'path:~/.ssh/github_personal|~/.ssh/svc-github.com'
  run ssh_config_github_key_first
  assert_failure
}

@test "save_github_key: adds github.com stanza when github.com uses a different github-named key" {
  # Regression: any IdentityFile containing "github" used to count as coverage,
  # so a personal key like ~/.ssh/github_personal skipped the stanza and the key
  # just fetched was never offered.
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh 'path:~/.ssh/github_personal'
  run save_github_key
  assert_success
  assert_output --partial "SSH config updated"
  grep -q "IdentityFile ~/.ssh/svc-github.com" "$HOME/.ssh/config"
}

# ── ssh_config_has_github: exact-path match ───────────────────────────────────

@test "ssh_config_has_github: true for ~/.ssh/svc-github.com" {
  mock_ssh 'path:~/.ssh/svc-github.com'
  run ssh_config_has_github
  assert_success
}

@test "ssh_config_has_github: true for the absolute path" {
  mock_ssh "path:$HOME/.ssh/svc-github.com"
  run ssh_config_has_github
  assert_success
}

@test "ssh_config_has_github: true for the %d and \${HOME} forms ssh expands" {
  mock_ssh 'path:%d/.ssh/svc-github.com'
  run ssh_config_has_github
  assert_success
  mock_ssh 'path:${HOME}/.ssh/svc-github.com'
  run ssh_config_has_github
  assert_success
}

@test "ssh_config_has_github: false for another github-named key" {
  mock_ssh 'path:~/.ssh/github_personal'
  run ssh_config_has_github
  assert_failure
}

@test "ssh_config_has_github: false for a path that merely starts with ours" {
  mock_ssh 'path:~/.ssh/svc-github.com.bak'
  run ssh_config_has_github
  assert_failure
}

@test "ssh_config_has_github: false when ssh is absent" {
  rm -f "$MOCK_BIN/ssh"
  only_mocks_on_path
  run ssh_config_has_github
  restore_path
  assert_failure
}

@test "save_github_key: adds github.com stanza even when a 'github' alias (not github.com) already resolves to a github-named key" {
  # Regression: a prior bug treated a resolvable `github` alias (e.g. one
  # another tool's SSH config + git url.insteadOf wires up) as proof the
  # literal github.com host was already covered, and skipped adding its own
  # stanza — leaving github.com (and thus `ssh -T git@github.com` / any plain
  # `git@github.com:` clone) unrouted.
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh alias
  run save_github_key
  assert_success
  assert_output --partial "SSH config updated"
  grep -q "Host github.com" "$HOME/.ssh/config"
  grep -q "IdentityFile ~/.ssh/svc-github.com" "$HOME/.ssh/config"
}

@test "save_github_key: second run adds no duplicate config stanza" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  # First run with no github config; afterwards pretend config now resolves.
  save_github_key >/dev/null
  mock_ssh direct
  run save_github_key
  assert_success
  [[ "$(grep -c 'Host github.com' "$HOME/.ssh/config")" -eq 1 ]]
}
