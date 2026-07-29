Critique a plan before implementation — surfaces blockers while they are still cheap (whetstone).

# critique-plan

## Configuration

Resolve settings in three steps, lowest to highest priority:

**Step 1 — Read config files:**
Run:

```bash
aether config show whetstone --raw 2>/dev/null || true
```

Each line is `key: value`, already resolved — `~/.aether/config`, then the
project's `.aether/config`, per key, with declared defaults filled in. If it
prints nothing, use the defaults documented below and continue.

Each file is key-value, one entry per line:
```
enabled: true
critics: impl, risk
skip: arch
severity: red, yellow
```

**Step 2 — Parse `$ARGUMENTS`** (overrides config files):

| Flag | Effect |
|------|--------|
| `--only=impl,arch` | Run only these critics |
| `--skip=risk` | Run all defaults except the named one(s) |
| `--severity=red` | Report only 🔴 findings |
| `--severity=red,yellow` | Report 🔴 and 🟡 findings |
| `--off` | Print "whetstone disabled for this run." and stop |
| `--help` | Print this flag table and stop |

If `$ARGUMENTS` is empty and no config files exist, run all three defaults (`impl`, `arch`, `risk`) and show all severities.
If an unrecognised flag is passed, print a warning and fall back to defaults.

**Step 3 — Check enabled state:**
If `enabled: false` is set in the resolved config, print "whetstone is disabled for this project. Run `whetstone enable` to re-enable." and stop immediately.

---

## Context gathering

Before critiquing, collect available project context. Read the following if they exist — skip silently if absent:

1. `package.json` or `pyproject.toml` — dependency landscape and versions
2. `ARCHITECTURE.md` or any `.md` files in an `ADR/` directory — existing architectural decisions
3. Project prose for the critics. Global first, then the project — prose
   **concatenates** rather than overriding, so house style survives a repo
   adding one line:

   ```bash
   { cat "$HOME/.aether/rules.md" 2>/dev/null; printf '\n'; cat .aether/rules.md 2>/dev/null; }
   ```

   Use the `[all]` and `[critique-plan]` sections; ignore sections named for
   other commands. Pre-1.1 installs kept this in `./whetstone.config.md`, which
   is still read if `.aether/rules.md` is absent.

Use this context to ground findings: flag dependency version conflicts, note contradictions with existing ADRs, apply any project-specific instructions from `rules.md`.

---

## Plan discovery

Find the plan to critique using this order:
1. `PLAN.md` in the project root
2. `PLAN_MODE_HANDOFF.md` in the project root
3. Any `.md` files inside a `plans/` directory
4. If none found, ask the user to paste the plan directly

---

## Critic 1 — Implementation (run if: `impl` selected or no arguments)

You are a senior engineer focused purely on implementation feasibility.

Critique the plan for:
- Missing implementation details (what file, what function, what change exactly?)
- Unhandled edge cases and error paths
- Missing or underspecified tests
- Incorrect assumptions about existing code or libraries
- Dependency conflicts or version issues

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 2 — Architecture (run if: `arch` selected or no arguments)

You are a systems architect.

Critique the plan for:
- Coupling and separation-of-concerns violations
- Scalability or performance landmines
- Incorrect or leaky abstractions
- Maintainability risks (things that will be painful to change later)
- Missing rollback or migration strategy

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 3 — Risk (run if: `risk` selected or no arguments)

You are a cautious senior engineer focused on what can go wrong in production.

Critique the plan for:
- Security vulnerabilities or trust boundary violations
- Data loss or corruption scenarios
- Breaking changes to APIs, contracts, or user-facing behaviour
- Observability gaps (missing logs, metrics, alerts)
- Anything that would be a bad surprise at 2am

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 4 — Testing (run if: `testing` in arguments)

You are a QA engineer and testing advocate.

Critique the plan for:
- Missing or underspecified test strategies
- Untestable designs (tight coupling, hidden dependencies, no seams for injection)
- Inadequate coverage of edge cases and failure modes
- Absence of integration, contract, or end-to-end test plans
- Tests that would pass locally but fail in CI or production environments

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 5 — Complexity (run if: `complexity` in arguments)

You are an engineer who values simplicity above all else.

Critique the plan for:
- Over-engineering relative to the stated requirements
- Abstractions introduced before they're needed (YAGNI violations)
- Patterns or frameworks that add ceremony without proportional benefit
- Simpler alternatives that would meet the same goals with less code or fewer moving parts
- Complexity that will slow down future contributors

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 6 — API Contract (run if: `api` in arguments)

You are a platform engineer responsible for API stability.

Critique the plan for:
- Breaking changes to public APIs, REST endpoints, GraphQL schemas, or SDK interfaces
- Missing versioning strategy for breaking changes
- Implicit contracts that consumers may rely on (field names, ordering, error shapes)
- Missing deprecation paths for removed functionality
- Changes that would silently corrupt clients on old versions

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Critic 7 — Cost / Ops (run if: `cost` in arguments)

You are a cloud infrastructure and reliability engineer.

Critique the plan for:
- New cloud resources or services not accounted for in cost estimates
- Query patterns that could cause unexpected database load or egress costs
- Missing autoscaling, rate limiting, or circuit breakers
- Infrastructure changes that require manual ops steps
- Anything that will cause an alert or a surprise bill on first deploy

Rate each finding: 🔴 blocker / 🟡 significant / 🟢 minor

---

## Report format

After all selected passes, output:

### Critique report

| # | Critic | Severity | Finding | Recommendation |
|---|--------|----------|---------|----------------|
| 1 | Impl   | 🔴       | …       | …              |
| … |        |          |         |                |

**Blockers:** N
**Significant:** N
**Minor:** N

> If no blockers or significant findings: state "Plan looks solid — only minor observations." and list them briefly.

Do not revise the plan. Surface findings only. The user will decide what to act on.

---

## Persist output

After printing the report, determine where to write it:
- If the project has a `.aether/` directory → write to `.aether/out/CRITIQUE.md`
- Otherwise → write to `~/.aether/out/CRITIQUE.md`

Create the directory if it does not exist. `enforce-whetstone.sh` looks for the
file at exactly this path to decide whether a plan has been critiqued, so writing
it elsewhere leaves the gate nudging forever. Pre-1.1 installs used
`.claude/plans/CRITIQUE.md`; the gate still honours that path when it exists, and
`aether migrate` moves it.

Prepend a header: `# Critique — <source file name> — <current date>`

If `CRITIQUE.md` already exists at the resolved path, append rather than overwrite, so the file accumulates a history of critiques over time.

---

## Post-critique gate

If any 🔴 blocker findings were found:
- Do NOT proceed to implementation
- State clearly: "**X blocker(s) found.** Resolve these or say `override blockers` before continuing."
- Wait for the user's response

If all findings are 🟡 or 🟢, state the finding counts and confirm the plan is clear to proceed.
