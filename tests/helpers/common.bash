#!/usr/bin/env bash
# Common setup helpers for the baseline-access.sh test suite.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$TESTS_DIR/../baseline-access.sh"

# Load bats-support and bats-assert from the vendored copies.
load "$TESTS_DIR/bats.d/bats-support/load"
load "$TESTS_DIR/bats.d/bats-assert/load"

# Source baseline-access.sh with main() stubbed so individual functions can be
# called directly. Relies on `main "$@"` being the last line of the script.
load_bootstrap_functions() {
  # shellcheck disable=SC1090
  source <(head -n -1 "$BOOTSTRAP"; printf 'main() { :; }\n')
}

# Standard environment isolation — call at the top of every setup().
isolate_environment() {
  unset BW_SESSION SSH_AUTH_SOCK SSH_AGENT_PID BASH_ENV ENV \
        GIT_IDENTITY_NAME GIT_IDENTITY_EMAIL
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# Create a per-test mock bin dir and prepend it to PATH.
setup_mock_bin() {
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  if declare -F mock_sudo_blocker >/dev/null; then
    mock_sudo_blocker
  fi
}

# Temporarily restrict PATH to the mock bin only — so `have <tool>` is false for
# any unmocked tool. Symlinks bash into the mock bin so generated mock scripts
# (which run `#!/usr/bin/env bash`) still execute. Always pair with restore_path
# so later shell/test-teardown commands (grep, rm, …) remain reachable.
only_mocks_on_path() {
  ln -sf "$(command -v bash)" "$MOCK_BIN/bash"
  _SAVED_PATH="$PATH"
  export PATH="$MOCK_BIN"
}
restore_path() { export PATH="${_SAVED_PATH:-$PATH}"; }
