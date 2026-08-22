# baseline-access backlog
<!-- next-id: 2 -->

## Open

## Done / won't-do

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
