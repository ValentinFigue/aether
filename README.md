# temper

Harden your code before it ships. Temper runs four adversarial critics against your diff — catching logic errors, design drift, production risks, and coverage gaps at review time, not incident time.

It is the symmetric counterpart to [whetstone](https://github.com/ValentinFigue/whetstone): where whetstone critiques *plans*, temper critiques *diffs*.

> Tempering is the hardening process applied *after* forging. The metal has been shaped — now we make sure it holds.

---

## What it does

Run `/temper` before committing or pushing. Temper reads your staged diff (or any diff you point it at), runs four critic personas against the code, and produces a structured review with severity ratings:

```
### Review report

| # | Critic      | Severity | Finding                                         | Recommendation                        |
|---|-------------|----------|-------------------------------------------------|---------------------------------------|
| 1 | Correctness | 🔴       | Missing nil check on user.email before send()   | Add guard: if user.email is None: ...  |
| 2 | Risk        | 🟡       | New endpoint has no rate limiting               | Add @rate_limit decorator             |
| 3 | Coverage    | 🟢       | Happy path tested but empty-list case is not    | Add test for empty input              |

Blockers: 1
Significant: 1
Minor: 1
```

If blockers are found, temper gates the push until they're resolved.

---

## The four critics

| Critic | Focus |
|--------|-------|
| **Correctness** | Logic errors, null dereferences, off-by-ones, unhandled errors |
| **Design** | Coupling, misleading names, duplication, premature complexity |
| **Risk** | Security vulnerabilities, data loss, breaking API changes, missing observability |
| **Coverage** | Untested paths, invalidated tests, untestable code |

---

## Install

### Quick start (this project)

```bash
bash install.sh
```

### Global install (all projects)

```bash
bash install.sh global
```

### With proactive CLAUDE.md rules

Adds behavioral guidelines to your CLAUDE.md that teach Claude Code to proactively suggest `/temper` based on session scope, bonsai refactoring, and critical file patterns:

```bash
bash install.sh --claude-md          # local
bash install.sh global --claude-md   # global
```

### No dependencies

No Python, npm, or build step required. Just bash and Claude Code.

---

## Usage

```
/temper                     Review staged changes (default)
/temper --diff=all          Review all changes since HEAD
/temper --diff=HEAD~3       Review last 3 commits
/temper --only=risk         Run only the Risk critic
/temper --skip=coverage     Run all critics except Coverage
/temper --severity=red      Report only blockers
/temper --target=src/auth.py  Scope to one file
```

---

## When the hook fires

The `enforce-temper.sh` PreToolUse hook blocks the following operations and asks you to run `/temper` first:

| Operation | Condition |
|-----------|-----------|
| `git push` | Always (except `--dry-run`) |
| `git commit` | Staged diff > 200 lines or > 10 files, or critical path file matched |
| `git merge` | Merging into main / master / develop / trunk |
| `git rebase -i` | Range touches > 5 commits |
| `git stash pop` | Stash diff > 200 lines |

**Bypass:** append `# temper:skip` to any command to silence the hook for that run.

```bash
git push origin main  # temper:skip
```

---

## Configuration

Create `temper.config` in your project root (local) or `~/.claude/temper.config` (global):

```
enabled: true
critics: correctness, design, risk, coverage
skip:
severity: red, yellow
diff: staged
auto_nudge_lines: 200
auto_nudge_files: 10
critical_paths: *auth*, *permission*, *token*, migrations/, *alembic*, *.sql, *schema*, *secret*, *credential*, *.env
```

### CLI

```
temper status                          Show install state and effective config
temper enable  [local|global]          Enable temper
temper disable [local|global]          Disable temper
temper config set auto_nudge_lines=300
temper config set critics=correctness,risk --global
temper config reset local
temper update                          Re-download latest temper.md
temper uninstall [global] [--claude-md]
```

---

## Two-tier gate model

**Tier 1 — Proactive (CLAUDE.md rules)**
When installed with `--claude-md`, behavioral guidelines teach Claude Code to suggest `/temper` before you even reach a git command — based on session scope, critical file patterns, and bonsai refactoring activity. These are soft instructions, not hard blocks.

**Tier 2 — Reactive (enforce-temper.sh hook)**
The hook is the hard gate. It intercepts high-risk git operations and blocks them until you acknowledge the risk via `/temper` or `# temper:skip`.

---

## Severity contract

| Rating | Meaning |
|--------|---------|
| 🔴 Blocker | Do not push. Fix first. |
| 🟡 Significant | Fix before the next session or document the exception in the commit message. |
| 🟢 Minor | Fix when convenient. Worth noting. |

---

## Uninstall

```bash
bash uninstall.sh               # local
bash uninstall.sh global        # global
bash uninstall.sh global --claude-md  # also remove CLAUDE.md section
```

---

## The suite

| Plugin | Purpose | When |
|--------|---------|------|
| [whetstone](https://github.com/ValentinFigue/whetstone) | Critique plans | Before you build |
| [bonsai](https://github.com/ValentinFigue/bonsai) | AST refactoring | While you build |
| **temper** | Critique diffs | After you build |
| [cairn](https://github.com/ValentinFigue/cairn) | Git narration | When you ship |
