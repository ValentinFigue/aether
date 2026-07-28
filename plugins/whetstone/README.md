# whetstone

**Find the flaws in your plan before your code does.**

A Claude Code custom command that runs adversarial critics against your plan before a single line of code is written — catching implementation gaps, architectural risks, and production landmines at the moment they're cheapest to fix.

No dependencies. No MCP server. No build step.

---

## Why

Claude Code's plan mode is powerful. But a plan written by one perspective has blind spots.

`/autocritic` runs independent passes against your plan:

- An **implementation critic** that asks *"how exactly would this be built?"* — and flags what's missing
- An **architecture critic** that looks for coupling, leaky abstractions, and things that will be painful to change
- A **risk critic** that hunts for security holes, data loss scenarios, and 2am surprises

Each finding is rated by severity. No revisions, no rewrites — just a clear table of what needs attention before you commit to building.

---

## Install

**Recommended — global, available in every project:**

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/install.sh | bash -s global
```

This installs the `/autocritic` command, the `whetstone` CLI to `~/.local/bin/`, and configures the required `Read`/`Write` permissions in `~/.claude/settings.json` so the critic runs without permission prompts.

**With auto-trigger** — also injects the planning discipline into `~/.claude/CLAUDE.md`:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/install.sh | bash -s global --claude-md
```

**Local only** — available in this project only:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/install.sh | bash
```

**Manual one-liner** (no script):

```bash
# Global
mkdir -p ~/.claude/commands
curl -fsSL -o ~/.claude/commands/autocritic.md \
  https://raw.githubusercontent.com/ValentinFigue/whetstone/main/.claude/commands/autocritic.md

# Local
mkdir -p .claude/commands
curl -fsSL -o .claude/commands/autocritic.md \
  https://raw.githubusercontent.com/ValentinFigue/whetstone/main/.claude/commands/autocritic.md
```

If installing manually, also add `"Read"` and `"Write"` to `permissions.allow` in the relevant `settings.json` (`~/.claude/settings.json` for global, `.claude/settings.json` for local) to avoid permission prompts when the critic reads config files or writes `CRITIQUE.md`.

Restart Claude Code. The `/autocritic` command is immediately available.

**To uninstall:**

```bash
# Global (removes CLI binary, command file, permissions, and optionally CLAUDE.md section)
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/uninstall.sh | bash -s global --claude-md

# Local
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/uninstall.sh | bash
```

---

## Make it automatic

Add [templates/CLAUDE.md](templates/CLAUDE.md) to your project's `CLAUDE.md` to make the critic run automatically after every plan — no manual invocation needed. Use `--claude-md` during install (above), or manually:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/install.sh | bash -s --claude-md
```

With this in place, Claude Code runs `/autocritic` after presenting any plan and blocks implementation if blockers are found. Use `/autocritic --off` to skip a specific run without disabling it globally.

---

## Quick reference

| Command | What it does |
|---|---|
| `/autocritic` | Full critique — all three critics, all severities |
| `/autocritic --only=risk` | Risk pass only |
| `/autocritic --only=impl,arch` | Skip the risk critic |
| `/autocritic --skip=arch` | All defaults except architecture |
| `/autocritic --severity=red` | Blockers only |
| `/autocritic --severity=red,yellow` | Blockers and significant findings |
| `/autocritic --off` | Skip this run (useful when auto-trigger is active) |
| `/autocritic --help` | Print the flag reference |

Optional deep-dive critics (off by default):

| Command | What it does |
|---|---|
| `/autocritic --only=testing` | Test strategy and coverage gaps |
| `/autocritic --only=complexity` | Over-engineering and YAGNI violations |
| `/autocritic --only=api` | Breaking changes and versioning gaps |
| `/autocritic --only=cost` | Cloud cost and ops surprises |

---

## What you get

```
### Critique report

| # | Critic | Severity | Finding                                      | Recommendation                          |
|---|--------|----------|----------------------------------------------|-----------------------------------------|
| 1 | Impl   | 🔴       | No rollback path if migration fails mid-run  | Add a dry-run flag and a revert script  |
| 2 | Arch   | 🟡       | UserService now owns both auth and billing   | Split into two services or use a facade |
| 3 | Risk   | 🔴       | API keys logged in plain text on error paths | Redact before passing to the logger     |
| 4 | Impl   | 🟢       | Missing test for the empty-list edge case    | Add a unit test for results = []        |

Blockers: 2
Significant: 1
Minor: 1
```

Whetstone does not rewrite your plan. It surfaces findings. You decide what to act on.

The critique is also written to `CRITIQUE.md` in your project root — an audit trail that accumulates across sessions and pairs naturally with git history.

See [plans/](plans/) for a real-world example plan and its critique output.

---

## The critics

**Default** (always run unless overridden):

| Critic | Flag | Looks for |
|--------|------|-----------|
| **Implementation** | `impl` | Missing details, unhandled edge cases, untested paths, wrong assumptions, dependency conflicts |
| **Architecture** | `arch` | Coupling violations, scalability landmines, leaky abstractions, maintainability risks, missing migration strategy |
| **Risk** | `risk` | Security vulnerabilities, data loss scenarios, breaking changes, observability gaps, 2am surprises |

**Optional** (activated via `--only=` or `--skip=`):

| Critic | Flag | Looks for |
|--------|------|-----------|
| **Testing** | `testing` | Test strategy gaps, untestable designs, missing edge case coverage, CI/prod divergence |
| **Complexity** | `complexity` | Over-engineering, premature abstractions, YAGNI violations, simpler alternatives |
| **API Contract** | `api` | Breaking changes, missing versioning, implicit consumer contracts, deprecation paths |
| **Cost / Ops** | `cost` | Surprise cloud costs, query load, missing rate limiting, manual ops steps |

Severity ratings:
- 🔴 **Blocker** — fix this before building
- 🟡 **Significant** — worth addressing; will cause pain if ignored
- 🟢 **Minor** — good to know; fix when convenient

---

## Configuration

Whetstone resolves settings in three layers, lowest to highest priority:

**1. Global config** (`~/.claude/whetstone.config`) — your personal defaults across all projects  
**2. Local config** (`./whetstone.config`) — project-level overrides  
**3. Per-run flags** (`$ARGUMENTS`) — always win, override both config files

Config file format (key-value, one per line):

```
enabled: true
critics: impl, risk
skip: arch
severity: red, yellow
```

**Project-specific critic instructions** — create `whetstone.config.md` in your project root to give the critics prose context:

```markdown
# whetstone config

This project uses event sourcing. Flag any plan that bypasses the event log.
All writes must go through the `EventStore` service — direct DB writes are a blocker.

Treat all observability gaps as 🔴 blockers (this team is on-call).
```

Whetstone reads this before every critique and applies it across all passes.

---

## whetstone CLI

A global install also provides a `whetstone` command for managing your setup:

```bash
whetstone status                              # install state + effective config

whetstone disable local                       # silence for this project
whetstone disable global                      # silence everywhere
whetstone enable local                        # restore

whetstone config set --only=risk              # risk-only for this project
whetstone config set --skip=arch              # drop arch critic locally
whetstone config set --severity=red --global  # blockers-only everywhere
whetstone config reset local                  # wipe project overrides

whetstone update                              # pull latest autocritic.md
whetstone uninstall global --claude-md        # full removal
```

Run `whetstone help` for the full reference.

---

## Bypassing whetstone

Three ways to skip the critic, in order of scope:

| Method | Scope | When to use |
|--------|-------|-------------|
| `/autocritic --off` | This run only | Quick iteration on a plan you're actively editing |
| `# whetstone:skip` in the plan heading | This plan only (auto-trigger) | Spike or throwaway plan that doesn't need full critique |
| `# suite:skip` in the plan heading | All suite hooks for this plan | Coordinated skip across temper, cairn, and whetstone |

`--off` affects only the current `/autocritic` invocation. The skip markers are read by the auto-trigger in `CLAUDE.md` — they have no effect when running `/autocritic` directly.

---

## Works well with

| Plugin | What it does |
|--------|-------------|
| [**temper**](https://github.com/ValentinFigue/temper) | Reviews the diff before every commit |
| [**cairn**](https://github.com/ValentinFigue/cairn) | Narrates commits with structured changelogs |
| [**bonsai**](https://github.com/ValentinFigue/bonsai) | Finds dead Python code and suggests renames |
| [**whetstone**](https://github.com/ValentinFigue/whetstone) | ← you are here — sharpens plans before code is written |

---

## License

MIT — see [LICENSE](LICENSE).
