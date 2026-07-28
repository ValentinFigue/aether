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

---

# Review — main..HEAD (monorepo consolidation) — 2026-07-28

Critics: correctness, design, risk, coverage (no `temper.config`, so all four).
Reviewed surface: 47 files, +2417/−1316, excluding the four unmodified subtree imports.

Secrets scan: clean. The only matches are documentation of the patterns themselves
(`sk-`, `AKIA`, `ghp_`) in CHANGELOG.md and `plugins/temper/.claude/commands/temper.md`.

| # | Critic | Severity | Finding | Resolution |
|---|--------|----------|---------|------------|
| 1 | Risk | 🔴 | **A corrupt gate file blocked every tool call.** `enforce-suite.sh` sourced the four gates while `set -e` was still active, so a half-written or malformed gate aborted the hook with exit 2 — which Claude Code treats as *block the tool call*, not *nudge*. One bad file locked the user out of every Bash, Write and Edit. Introduced by this change: the monolithic hook had no separate files to corrupt. Reproduced with corrupt, truncated and empty gate files. | **Fixed.** `set +e` moved above the loading loop and gates sourced with stderr discarded, so a broken gate degrades to silence and the healthy ones still run. `aether status` now `bash -n`s each gate and names any that fail to parse, since the hot path is deliberately quiet. Regression tests cover all three corruption modes. |
| 2 | Correctness | 🟡 | **The jq permission branch reordered the user's config.** It deduplicated with `unique`, which sorts, so the jq path produced a different `settings.json` from the python3 and node paths and shuffled permissions the user already had. | **Fixed.** Replaced with an order-preserving `reduce`. |
| 3 | Coverage | 🟡 | **The node and jq fallbacks were unreachable by any test.** All three JSON helpers pick python3 whenever it exists, which is always on a dev machine and in CI, so two of three branches could rot silently — and finding 2 shows they had. | **Fixed.** Added `AETHER_JSON_BACKEND` to pin a backend, plus a test that runs a full install under each and asserts byte-identical `settings.json`. This is what surfaced finding 2. |
| 4 | Risk | 🟡 | **Predictable `/tmp` filenames for install logs.** `/tmp/aether-install-<plugin>.log` could be pre-created as a symlink by another user on a shared machine; the installer would then clobber the target. | **Fixed.** Single `mktemp -d` with a `trap … EXIT` cleanup. |
| 5 | Design | 🟢 | `_backup` overwrites `.bak` on every run, so a second install replaces the pre-first-install snapshot. It is a within-run guard against a truncating `> tmp && mv`, not a version history. | Left as is; documented in the function comment. |
| 6 | Coverage | 🟢 | bonsai's `--suite` install is not in the automated suite — its uv/npm build is too slow for CI. Only the prerequisite-missing skip path is tested. | Verified manually instead: build artifacts produced, MCP servers registered at absolute in-clone paths, and both servers answer an MCP handshake (bonsai-py 8 tools, bonsai-ts 5). |

**Blockers:** 1 (fixed) **Significant:** 3 (fixed) **Minor:** 2 (1 documented, 1 verified manually)

## Notes

- The 🔴 was self-inflicted by this change and is exactly the class of bug the
  consolidation was meant to reduce: splitting one file into five created a new
  partial-failure mode. It is now the most heavily tested path in the suite.
- Findings 2 and 3 compound: the untestable branch was also the wrong one. Making
  it testable found the defect in the same step.
- Test suite grew from 0 to 186 assertions across gates, dispatcher, installer and CLI.

All findings resolved or accepted. Good to ship.
