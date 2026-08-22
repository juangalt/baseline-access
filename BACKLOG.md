# baseline-access backlog
<!-- next-id: 2 -->

## Open

### B-1 — flaky bats suite (pre-existing)

`tests/run` intermittently reports one failure per run — roughly 2 in 6 runs —
and the failing test *moves*: observed on `bw_login_or_unlock: skips login when
BW_SESSION set and vault unlocked` (#35), `calls bw login when vault
unauthenticated` (#36), `calls bw unlock when vault locked` (#37), `refreshes
BW_SESSION when vault unlocked but no session` (#38), and once on `provision:
succeeds overall even when GitHub verify fails` (#50).

Reproduced on an unmodified `main` checkout, so it predates the SSH/HTTPS docs
work. A wandering failure across tests that share the mock-`bw` and PATH-prepend
fixtures points at a race or leaked state in the mock setup (shared temp paths
between concurrently-running tests), not at the provisioner logic.

Impact: the suite is not trustworthy as a green/red gate until this is fixed —
a single failure currently tells you nothing about whether a change broke
something. Worth fixing before the suite guards anything load-bearing.

## Done / won't-do
