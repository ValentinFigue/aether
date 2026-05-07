### temper review — HEAD — 2026-05-07

Secrets scan: clean.

| # | Critic | Severity | Finding | Recommendation |
|---|---|---|---|---|
| 1 | Correctness | 🔴 | `_dry` calls use `$([ '$MODE' = 'global' ] && echo 'global')` — `$MODE` inside single quotes in a subshell never expands; `global` arg never passed to plugin installers | Pre-evaluate: `[ "$MODE" = "global" ] && scope_arg="global" \|\| scope_arg=""` then use `$scope_arg` in _dry strings |
| 2 | Design | 🟡 | README still shows broken `pip install bonsai` command (was FIXME'd in install.sh but not README) | Replace with bonsai skip message or repo URL |
| 3 | Design | 🟡 | `aether status` hardcodes "(global)" for hook scope regardless of actual install scope | Read scope from manifest via `_manifest_get "scope"` |
| 4 | Risk | 🟡 | `set -euo pipefail` in enforce-suite.sh means unexpected gate errors block operations rather than fail open | Wrap dispatch block in `{ ... } \|\| true` |
| 5 | Risk | 🟡 | `eval "$@"` in `_dry()` evaluates shell metacharacters — unsafe pattern | Replace with explicit `if $DRY_RUN` at each call site |
| 6 | Coverage | 🟡 | No bats/shell tests for hook dispatch, bypass detection, or idempotent install | Add minimal bats test suite |
| 7 | Correctness | 🟢 | `gate_bonsai` in Write/Edit dispatch is dead code (self-guards on Bash tool) | Remove from Write/Edit dispatch branch |
| 8 | Correctness | 🟢 | `_temper_config` nested function is bash-global; name could clash | Rename to `_gate_temper_config` |
| 9 | Design | 🟢 | Dispatch comment misleadingly covers both Bash and Write/Edit blocks | Split into two labelled comments |
| 10 | Risk | 🟢 | Local uninstall silently skips CLI removal with no output | Add explanatory note to uninstall output |

Blockers: 1  |  Significant: 4  |  Minor: 5
