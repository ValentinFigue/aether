# Critique — what-do-you-think-linear-seal.md — 2026-07-28

Plan: consolidate the aether suite into a single repo.
Critics run: `impl`, `arch`, `risk` (no `whetstone.config` present → all defaults, all severities).

| # | Critic | Sev | Finding | Recommendation |
|---|--------|-----|---------|----------------|
| 1 | Impl | 🔴 | **PostToolUse hooks installed then silently deleted.** `bonsai/install.sh:193-214` registers a PostToolUse reference-drift hook (`post-bonsai.sh`) — bonsai's newest feature, HEAD `78a95a5`. cairn registers `post-cairn.sh` (post-temper → `/cairn-commit`; version bump → `/cairn-changelog`). `enforce-suite.sh` has **zero** PostToolUse coverage, yet the `STALE` list strips both. Under Phase 4, aether installs bonsai → bonsai registers the hook → step 3b deletes it. Deterministic loss, newly introduced (today aether skips bonsai entirely). | Remove `post-cairn` / `post-bonsai` from the `STALE` array; let the two per-plugin PostToolUse hooks stand. |
| 2 | Impl | 🟡 | **`mcp__bonsai_py__*` underscore bug is wider than recorded.** Also present in `bonsai/.claude-plugin/hooks.json` as matchers `mcp__bonsai_py__(pyrename\|pymove\|pymovesymbol\|pysignature)`, so the dry-run confirmation prompt on mutating refactors never fires. | Repo-wide `grep -rn 'bonsai_py\|bonsai_ts'` sweep rather than a two-file fix. |
| 3 | Impl | 🟡 | **`--suite` flag self-inconsistent.** Phase 3 adds it to all four installers; Phase 4 called bonsai without it. bonsai's arg parser ends in `*) echo "Unknown option"; exit 1` — the other three silently ignore unknown flags, bonsai hard-fails. | Pass `--suite` to bonsai too, and update its `case`. |
| 4 | Impl | 🟡 | **No automated tests.** Verification was a 9-step manual checklist. aether has zero tests (TEMPER.md item 6, still open) for a repo whose entire product is shell installers. | Add a bats suite; script the throwaway-HOME install as a repeatable test. |
| 5 | Arch | 🟡 | **Gate logic stays triple-duplicated.** `enforce-suite.sh` reimplements each plugin's gate inline instead of sourcing `plugins/*/hooks/enforce-*.sh`. Every future gate change must be hand-mirrored. The monorepo makes dedup possible for the first time. | Source the plugin gates under `SUITE_MODE=1`, or record an explicit deferral. |
| 6 | Arch | 🟡 | **Two version schemes would coexist.** aether 1.0.0 alongside `plugins/cairn` 0.3.1 and `plugins/bonsai` 0.1.0, each with its own CHANGELOG; `cairn --version` would disagree with `aether version`. | Pick one scheme. |
| 7 | Risk | 🟡 | **`export HOME=$(mktemp -d)` poisons the interactive shell.** Everything afterwards, including Claude Code's own `~/.claude` reads, silently targets the temp dir. | Scope it: `env HOME="$(mktemp -d)" bash install.sh …`. |
| 8 | Risk | 🟡 | **No backup before mutating `~/.claude/settings.json` and `~/.claude/CLAUDE.md`.** Every helper is `python3 … > "$f.tmp" && mv "$f.tmp" "$f"`; partial output on error truncates and overwrites the real file. | `cp "$f" "$f.bak"` before the first mutation. |
| 9 | Impl | 🟢 | bonsai's install runs `uv sync` and `npm install && npm run build --silent` — minutes of silence inside aether's installer. | Print a progress line before invoking. |
| 10 | Arch | 🟢 | Rollback for the subtree import is implicit in the `feat/monorepo` branch but never stated. | State it: no merge to `main` until verification passes. |
| 11 | Risk | 🟢 | Archived repos' installers freeze and silently diverge from the monorepo. | Pointer READMEs should state the frozen version. |

**Blockers:** 1 **Significant:** 7 **Minor:** 3

## Checks that came back clean

- All four sibling repos are on `main` with zero dirty files → `git subtree add` will capture complete state.
- Keeping `hooks/` at the repo root (not `plugins/suite/hooks/`) preserves the
  `raw.githubusercontent.com/.../aether/main/hooks/enforce-suite.sh` self-update URL for existing 0.1.0 installs.
- Removing `curl … | bash` from the install path closes a remote-code-execution vector — worth a CHANGELOG callout.

## Resolution

All findings accepted and folded into the plan before approval.

| Finding | Resolution |
|---|---|
| 1 🔴 | **Resolved** — Phase 6: stop stripping; both PostToolUse hooks stand. No `post-suite.sh` created. |
| 2, 3 | Folded into Phase 7 item 2 and Phase 3 respectively. |
| 4 | Elevated to its own Phase 10 (bats suite), gated on Phase 5's refactor size. |
| 5 | **Fixed in this change** (user chose not to defer) — new Phase 5. |
| 6 | Unify everything to 1.0.0, one root CHANGELOG — new Phase 9. |
| 7, 8 | Verification step 5 now uses `env HOME=…`; backup added to Phase 7 item 5. |
| 9, 10, 11 | Folded into Phase 4, Phase 1, and Phase 11 respectively. |

No blockers outstanding at approval time.

## Follow-up critique of the revised plan

Re-critique of the newly added Phase 5 surfaced three design defects in the sourcing
approach, all corrected in the plan before approval:

- Sourcing only *defines* the gate functions; the loop must run above the dispatch block
  at line 450, and the inline definitions must be deleted first or they shadow the
  sourced ones.
- `SUITE_MODE=1 . file` as an assignment prefix on the `.` special builtin behaves
  differently in bash's POSIX vs default mode — use `export SUITE_MODE=1` before the loop.
- `gate_whetstone_write` has no counterpart in whetstone's own hook, which handles both
  Bash and Write/Edit by branching on `$tool_name`. The two collapse into one
  `gate_whetstone`.
