# baseline-access backlog
<!-- next-id: 4 -->

## Open

## Done / won't-do

### B-3 — known_hosts not idempotent when hashed, trusted on first use; key mode inherited — **done**

- `ensure_known_hosts` grepped for `^github.com`, which never matches hashed
  entries (`HashKnownHosts yes`, the Debian/Ubuntu default), so every re-run
  appended the keys again. It also took the keys from `ssh-keyscan`, trusting
  whatever answered on port 22.
- `save_github_key` truncated an existing `~/.ssh/svc-github.com` in place, so
  the file kept whatever mode it already had (`umask` only applies on create)
  and a symlink was written through.

**Fix:** host keys come from `https://api.github.com/meta` (`.ssh_keys`) over TLS;
presence is checked per key with `ssh-keygen -F`, appending only missing keys and
never touching existing entries. The key is written to a `mktemp` file (0600) and
renamed into place; a newly created `~/.ssh` is 0700. Verified against the live
API: three keys added, a hashed re-run adds none, and `ssh` with
`StrictHostKeyChecking=yes` authenticates against them.

### B-2 — `curl | bash` one-liner cannot prompt; pinned tag stale — **done**

Under `curl … | bash`, stdin is the script pipe, so `read` (git identity) and
bw's own login/unlock prompts read EOF instead of the operator's keystrokes. The
identity `read` then failed under `set -e` and the script exited 1 with **no
message**. Separately, the README pinned `v0.2.0`, which predates B-1, the
`github.com` alias-detection fix, and the `svc-github.com` key path.

**Fix:** prompts go through `with_prompt_in`, which uses stdin when it is a tty,
else the controlling terminal (`/dev/tty`), else stdin; a missing answer now
dies with the "not provided" message. Verified under a real pty with the script
piped into bash (identity read from the terminal; pre-fix exits silently). The
README pin moves to `v0.3.0`, cut from the merge of this fix.

### B-1 — flaky bats suite — **done**

`tests/run` intermittently failed about 2 runs in 6, with the failing test moving
between the `bw_login_or_unlock` cases (#35–#38) and `provision` (#50).

**Root cause — a real bug in the provisioner, not just the tests.** The vault
status was read as:

```bash
bw_st=$(bw status 2>/dev/null | jq -r '.status // "unknown"' || echo "error")
```

with the `|| echo "error"` fallback *inside* the command substitution. When the
pipeline both printed and failed, the fallback **appended** to the output rather
than replacing it, so `$bw_st` became two lines — `$'unauthenticated\nerror'` —
which matches no `case` branch and dies with a mangled multi-line
`Unexpected bw status: unauthenticated` / `error`.

The suite hit that path via SIGPIPE: `mock_jq_value` printed and exited without
reading stdin, so a still-writing mock `bw` took SIGPIPE, and `set -o pipefail`
failed the pipeline. Whether `bw` lost that race was pure timing — hence the
wandering failures. Real `jq` drains stdin, so production never tripped the
SIGPIPE path, but any genuine `bw status` failure would produce the same garbage
status.

**Fix (two parts):**

1. `baseline-access.sh` — moved the fallback outside the substitution, so a
   failing pipeline cleanly *replaces* the value with the `error` sentinel:
   `bw_st=$(…) || bw_st="error"`.
2. `tests/helpers/mocks.bash` — `mock_jq_value` / `mock_jq_dispatch` now drain
   stdin before printing, matching real `jq` and removing the artificial race.
   The drain is a bash builtin loop, not `cat`, because `only_mocks_on_path`
   strips PATH down to `MOCK_BIN`.

**Verification:** a new regression test, `bw_login_or_unlock: a printing-but-
failing status pipeline yields a clean sentinel`, drives a `bw` that prints a
valid status then exits non-zero. It fails against the pre-fix script with
exactly the observed two-line signature and passes after. Suite went from ~2
failures in 6 runs to 20 consecutive clean runs at 52/52.
