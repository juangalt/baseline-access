#!/usr/bin/env bats
# Tests for: prompt_in() and the prompts routed through it.
# Regression cover for the `curl … | bash` one-liner, where stdin is the script
# pipe and every prompt used to read EOF.

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

@test "prompt_in: honours BASELINE_PROMPT_IN" {
  export BASELINE_PROMPT_IN="$BATS_TEST_TMPDIR/answers"
  run prompt_in
  assert_success
  assert_output "$BATS_TEST_TMPDIR/answers"
}

@test "prompt_in: falls back to stdin with no tty and no controlling terminal" {
  unset BASELINE_PROMPT_IN
  # setsid detaches from the controlling terminal, so /dev/tty cannot open.
  run setsid -w bash -c "source <(head -n -1 '$BOOTSTRAP'); prompt_in" </dev/null
  assert_success
  assert_output "/dev/stdin"
}

@test "configure_git_identity: reads answers from the prompt source, not stdin" {
  mock_git_identity
  printf 'Prompted User\nprompted@example.com\n' > "$BATS_TEST_TMPDIR/answers"
  export BASELINE_PROMPT_IN="$BATS_TEST_TMPDIR/answers"
  run configure_git_identity </dev/null
  assert_success
  assert_output --partial "Git identity configured (Prompted User <prompted@example.com>)"
}

@test "bw_login_or_unlock: bw login reads from the prompt source" {
  mock_jq_value unauthenticated
  # A bw whose login echoes back the first line of its stdin as the session.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf "{\\"status\\":\\"unauthenticated\\"}\\n" ;;\n'
    printf '  login) IFS= read -r line; printf "%%s\\n" "$line" ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  printf 'from-prompt-source\n' > "$BATS_TEST_TMPDIR/answers"
  export BASELINE_PROMPT_IN="$BATS_TEST_TMPDIR/answers"
  bw_login_or_unlock </dev/null >/dev/null
  [[ "$BW_SESSION" == "from-prompt-source" ]]
}
