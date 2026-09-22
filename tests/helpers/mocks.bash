#!/usr/bin/env bash
# Mock factory helpers. Requires setup_mock_bin() to have been called first.
# Every external tool the script touches (bw, jq, git, ssh, curl, brew,
# npm, snap, sudo) is mocked here via PATH prepend — tests make no real calls.

# Write a simple mock that exits with EXIT_CODE and optionally prints OUTPUT.
# Usage: mock_cmd NAME EXIT_CODE [OUTPUT]
mock_cmd() {
  local name="$1" exit_code="${2:-0}" output="${3:-}"
  {
    printf '#!/usr/bin/env bash\n'
    [[ -n "$output" ]] && printf 'printf "%%s\\n" %q\n' "$output"
    printf 'exit %s\n' "$exit_code"
  } > "$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

# Write a mock that appends its arguments to a capture file and exits/prints.
# Capture file: $BATS_TEST_TMPDIR/<name>.calls
# Usage: mock_cmd_capture NAME EXIT_CODE [OUTPUT]
mock_cmd_capture() {
  local name="$1" exit_code="${2:-0}" output="${3:-}"
  local capture="$BATS_TEST_TMPDIR/${name}.calls"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$capture"
    [[ -n "$output" ]] && printf 'printf "%%s\\n" %q\n' "$output"
    printf 'exit %s\n' "$exit_code"
  } > "$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

# Write a bw mock pre-configured for a given vault status.
# STATUS: unlocked | authenticated | locked | unauthenticated | <any>
# Usage: mock_bw_status STATUS [SESSION_TOKEN]
mock_bw_status() {
  local status="$1" token="${2:-fake-session-token}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"%s"}\n'"'"' %q ;;\n' "$status"
    printf '  login|unlock) printf "%%s\\n" %q ;;\n' "$token"
    printf '  get) exit 0 ;;\n'
    printf '  sync) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
}

# Write a bw mock where 'bw get' fails (item not found).
mock_bw_get_fail() {
  local status="${1:-unlocked}" token="${2:-fake-session-token}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"%s"}\n'"'"' %q ;;\n' "$status"
    printf '  login|unlock) printf "%%s\\n" %q ;;\n' "$token"
    printf '  get) exit 1 ;;\n'
    printf '  sync) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
}

# Write a jq mock that echoes a fixed value.
# Usage: mock_jq_value VALUE
mock_jq_value() {
  # Drains stdin first: real jq consumes its input, and a mock that exits without
  # reading closes the pipe under a still-writing `bw`, which takes SIGPIPE. With
  # `set -o pipefail` in the script under test that fails the whole pipeline, so
  # not draining here makes tests fail nondeterministically on timing alone.
  # The drain is a bash builtin loop, not `cat`: only_mocks_on_path strips PATH
  # down to MOCK_BIN, where no external tool exists.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'while IFS= read -r _; do :; done\n'
    printf 'printf "%%s\\n" %q\n' "$1"
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
}

# Write a jq mock that dispatches on the filter expression (the last argument).
# Each argument is a PATTERN=VALUE pair; PATTERN is glob-matched against the filter.
# Usage: mock_jq_dispatch ".status=unlocked" ".sshKey.privateKey=KEY_CONTENT"
mock_jq_dispatch() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'while IFS= read -r _; do :; done\n'
    printf 'FILTER="${@: -1}"\n'
    printf 'case "$FILTER" in\n'
    for mapping in "$@"; do
      printf '  *%s*) printf "%%s\\n" %q ;;\n' "${mapping%%=*}" "${mapping#*=}"
    done
    printf '  *) printf "jq mock: unmatched filter: %%s\\n" "$FILTER" >&2; exit 1 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
}

# Write an ssh mock responding to `ssh -G <host>` (config detection) and
# `ssh -T git@github.com` (auth verification).
# Usage: mock_ssh MODE [VERIFY_BANNER] [IDENTITIES_ONLY]
#   MODE (github config presence, drives `ssh -G`):
#     direct — github.com → IdentityFile ~/.ssh/svc-github.com
#     none   — no github-specific config (only default keys)
#     alias  — a `github` alias (NOT github.com) resolves to a github-named
#              key (e.g. ~/.ssh/svc-github); github.com itself stays
#              unrouted. Simulates another tool (fleet-control) provisioning
#              an alias without covering the literal host.
#     path:P — github.com → IdentityFile P, printed verbatim (unexpanded, as
#              the real `ssh -G` does), e.g. path:~/.ssh/github_personal.
#              P may be several paths joined by `|`, printed in that order
#              (the order ssh tries them), e.g. path:~/.ssh/a|~/.ssh/b.
#   VERIFY_BANNER (drives `ssh -T`, optional):
#     authed   — emit the "successfully authenticated" banner (default)
#     denied   — emit a permission-denied banner
#   IDENTITIES_ONLY (github.com's `identitiesonly` in `ssh -G`, optional):
#     yes (default) | no
mock_ssh() {
  local mode="${1:-none}" verify="${2:-authed}" idonly="${3:-yes}"
  local id_github_com id_github_alias
  case "$mode" in
    direct) id_github_com="~/.ssh/svc-github.com";  id_github_alias="~/.ssh/id_rsa" ;;
    none)   id_github_com="~/.ssh/id_rsa";  id_github_alias="~/.ssh/id_rsa" ;;
    alias)  id_github_com="~/.ssh/id_rsa";  id_github_alias="~/.ssh/svc-github" ;;
    path:*) id_github_com="${mode#path:}";  id_github_alias="~/.ssh/id_rsa" ;;
    *) printf 'mock_ssh: unknown mode %s\n' "$mode" >&2; return 1 ;;
  esac
  local banner
  case "$verify" in
    authed) banner="Hi juangalt! You've successfully authenticated, but GitHub does not provide shell access." ;;
    denied) banner="git@github.com: Permission denied (publickey)." ;;
    *) printf 'mock_ssh: unknown verify %s\n' "$verify" >&2; return 1 ;;
  esac
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [[ "$1" == "-G" ]]; then\n'
    printf '  case "$2" in\n'
    local -a ids
    IFS='|' read -r -a ids <<<"$id_github_com"
    printf '    github.com) printf "identityfile %%s\\n"'
    printf ' %q' "${ids[@]}"
    printf '; printf "identitiesonly %%s\\n" %q ;;\n' "$idonly"
    printf '    github)     printf "identityfile %%s\\n" %q ;;\n' "$id_github_alias"
    printf '    *)          printf "identityfile ~/.ssh/id_rsa\\n" ;;\n'
    printf '  esac\n'
    printf '  exit 0\n'
    printf 'fi\n'
    # Anything else is treated as the `ssh -T` auth probe: GitHub exits non-zero.
    printf 'printf "%%s\\n" %q >&2\n' "$banner"
    printf 'exit 1\n'
  } > "$MOCK_BIN/ssh"
  chmod +x "$MOCK_BIN/ssh"
}

# GitHub's real published host keys (public, not secrets) — real key blobs so the
# unmocked `ssh-keygen -F` accepts them.
GH_ED25519="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
GH_ECDSA="ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="

# Mock GitHub's meta API for ensure_known_hosts(): a curl that records its URL
# and exits RC, and a jq dispatch that yields KEYS (newline-separated) for
# `.ssh_keys[]`. Extra jq mappings (e.g. ".status=unlocked") pass through.
# `ssh-keygen` is deliberately NOT mocked: `-F` is a read-only lookup on the
# test's own known_hosts, and matching hashed entries means reproducing its HMAC.
# Usage: mock_github_meta RC KEYS [JQ_MAPPING...]
mock_github_meta() {
  local rc="$1" keys="$2"; shift 2
  {
    printf '#!/usr/bin/env bash
'
    printf 'printf "%%s\n" "$*" >> %q
' "$BATS_TEST_TMPDIR/curl.calls"
    printf 'printf "{}\n"
'
    printf 'exit %s
' "$rc"
  } > "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"
  mock_jq_dispatch ".ssh_keys=$keys" "$@"
}

# Write a git mock for identity config. Backed by a flat key/value store file so
# `git config --global user.X <v>` writes and `git config --global user.X` reads.
# All calls captured to $BATS_TEST_TMPDIR/git.calls.
# Usage: mock_git_identity   (start with no identity set)
mock_git_identity() {
  local store="$BATS_TEST_TMPDIR/gitconfig.store"
  : > "$store"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/git.calls"
    printf 'STORE=%q\n' "$store"
    printf 'if [[ "$1" == "config" && "$2" == "--global" ]]; then\n'
    printf '  key="$3"; shift 3\n'
    printf '  if [[ $# -ge 1 ]]; then\n'           # write
    printf '    grep -v "^${key}=" "$STORE" > "$STORE.tmp" 2>/dev/null || true\n'
    printf '    mv "$STORE.tmp" "$STORE"\n'
    printf '    printf "%%s=%%s\\n" "$key" "$1" >> "$STORE"\n'
    printf '    exit 0\n'
    printf '  else\n'                               # read
    printf '    line=$(grep "^${key}=" "$STORE" | tail -n1)\n'
    printf '    [[ -z "$line" ]] && exit 1\n'
    printf '    printf "%%s\\n" "${line#*=}"\n'
    printf '    exit 0\n'
    printf '  fi\n'
    printf 'fi\n'
    printf 'exit 0\n'
  } > "$MOCK_BIN/git"
  chmod +x "$MOCK_BIN/git"
}

# Pre-seed the mock_git_identity store with an existing identity.
# Usage: seed_git_identity NAME EMAIL   (call after mock_git_identity)
seed_git_identity() {
  local store="$BATS_TEST_TMPDIR/gitconfig.store"
  printf 'user.name=%s\nuser.email=%s\n' "$1" "$2" >> "$store"
}

# Default sudo blocker — any test needing sudo opts in with mock_sudo_passthrough.
mock_sudo_blocker() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "test attempted real sudo: %%s\\n" "$*" >&2\n'
    printf 'exit 99\n'
  } > "$MOCK_BIN/sudo"
  chmod +x "$MOCK_BIN/sudo"
}

# Guarded sudo passthrough: `sudo foo …` runs `foo …` only when foo resolves to
# this test's mock bin, refusing to reach any real host-mutating tool.
mock_sudo_passthrough() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cmd="$1"\n'
    printf 'resolved="$(command -v -- "$cmd" 2>/dev/null || true)"\n'
    printf 'case "$resolved" in\n'
    printf '  %q/*) exec "$@" ;;\n' "$MOCK_BIN"
    printf '  *) printf "refusing sudo passthrough to non-mocked command: %%s\\n" "$cmd" >&2; exit 99 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/sudo"
  chmod +x "$MOCK_BIN/sudo"
}
