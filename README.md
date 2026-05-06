# cairn

**Mark where you've been.** Cairn reads your diff, understands the intent behind the changes, and writes your commit messages, PR descriptions, changelogs, and standup summaries — so the trail is always readable.

No dependencies. No MCP server. No build step.

---

## Why

Git history is a graveyard of `fix`, `wip`, and `misc`.

Not because the work was unclear — because writing a good commit message after finishing a feature takes context you've already moved past. Cairn reads what you actually changed and writes the message for you: semantic, conventional, and ready to paste.

---

## Commands

| Command | What it does |
|---|---|
| `/cairn-commit` | Generate a Conventional Commits message from staged diff |
| `/cairn-pr` | Generate a PR title and description from branch diff |
| `/cairn-changelog` | Generate a CHANGELOG entry from a commit range |
| `/cairn-summary` | Plain-language standup, Slack message, or formal summary |

---

## Install

**Recommended — global, available in every project:**

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash -s global
```

This installs all four cairn commands, the `cairn` CLI to `~/.local/bin/`, the `enforce-cairn` hook, and configures the required `Bash`, `Read`, and `Write` permissions in `~/.claude/settings.json` so git commands run without permission prompts.

**With documentation rules** — also injects project behaviour rules into `~/.claude/CLAUDE.md`:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash -s global --claude-md
```

**Local only** — available in this project only:

```bash
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash
```

**Manual one-liner** (no script):

```bash
# Global
mkdir -p ~/.claude/commands
for cmd in cairn-commit cairn-pr cairn-changelog cairn-summary; do
  curl -fsSL -o ~/.claude/commands/${cmd}.md \
    https://raw.githubusercontent.com/ValentinFigue/cairn/main/.claude/commands/${cmd}.md
done

# Local
mkdir -p .claude/commands
for cmd in cairn-commit cairn-pr cairn-changelog cairn-summary; do
  curl -fsSL -o .claude/commands/${cmd}.md \
    https://raw.githubusercontent.com/ValentinFigue/cairn/main/.claude/commands/${cmd}.md
done
```

If installing manually, add `"Bash"`, `"Read"`, and `"Write"` to `permissions.allow` in the relevant `settings.json` to avoid prompts when cairn reads diffs.

Restart Claude Code. The cairn commands are immediately available.

**To uninstall:**

```bash
# Global
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/uninstall.sh | bash -s global --claude-md

# Local
curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/uninstall.sh | bash
```

---

## Usage

### `/cairn-commit` — commit messages

Stage your changes, then run `/cairn-commit` in Claude Code:

```
git add src/auth/token.py
/cairn-commit
```

### `/cairn-pr` — PR descriptions

On your feature branch, run `/cairn-pr`:

```
/cairn-pr
/cairn-pr --base=develop
```

### `/cairn-changelog` — CHANGELOG entries

```
/cairn-changelog
/cairn-changelog --from=v0.1.0 --version=0.2.0
```

### `/cairn-summary` — standup and status updates

```
/cairn-summary
/cairn-summary --format=slack
/cairn-summary --from=v0.1.0 --format=paragraph
```

---

## Quick reference

| Command | What it does |
|---|---|
| `/cairn-commit` | Conventional Commits message from staged diff |
| `/cairn-commit --style=plain` | Plain imperative-mood message |
| `/cairn-commit --off` | Skip this run |
| `/cairn-pr` | PR title + description (auto-detects base branch) |
| `/cairn-pr --base=develop` | Diff against `develop` instead of `main` |
| `/cairn-pr --style=plain` | Plain PR title |
| `/cairn-changelog` | CHANGELOG entry from last tag to HEAD |
| `/cairn-changelog --from=v0.1.0 --version=0.2.0` | Specify range and version |
| `/cairn-changelog --style=plain` | Flat bullet list, no type grouping |
| `/cairn-summary` | Standup summary of yesterday's commits |
| `/cairn-summary --format=slack` | Slack-ready paragraph |
| `/cairn-summary --format=paragraph` | Formal prose summary |
| `/cairn-summary --from=v0.1.0` | Summary from a specific tag |

---

## What you get

### `/cairn-commit`

```
feat(auth): add token expiry validation on login

Tokens were accepted past their expiry window when the clock skew
tolerance was set above 30s. Adds a hard ceiling regardless of tolerance.

Closes #412
```

If your staged diff spans multiple unrelated areas, cairn flags it and suggests separate commits:

```
Commit 1 — auth:
git commit -m "feat(auth): add token expiry validation on login"

Commit 2 — docs:
git commit -m "docs: update token lifecycle diagram"

Consider splitting this into separate commits.
```

### `/cairn-pr`

```
PR Title:
feat(auth): add token expiry validation and clock-skew ceiling

Description:
## Summary
- Add hard ceiling on token expiry regardless of clock-skew tolerance
- Fix accepted-past-expiry bug when tolerance exceeded 30s
- Update token lifecycle diagram in docs

## Changes
- `src/auth/token.py` — validates expiry window with ceiling
- `docs/token-lifecycle.md` — updated diagram

## Test plan
- [ ] Run `pytest tests/auth/` — all tests pass
- [ ] Manual test: set tolerance > 30s, verify expired token is rejected
- [ ] Review token lifecycle diagram renders correctly
```

### `/cairn-changelog`

```markdown
## [0.2.0] — 2026-05-06

### Added

- Token expiry validation with configurable ceiling in the auth flow
- Lifecycle diagram updated to reflect new expiry model

### Fixed

- Tokens no longer accepted past their expiry window when clock-skew tolerance exceeds 30s
```

### `/cairn-summary`

```
Yesterday:
- Added hard token expiry ceiling to the auth flow — expired tokens now rejected regardless of tolerance
- Fixed the clock-skew edge case that was causing intermittent auth failures in staging
- Updated the token lifecycle diagram and related docs

Today:
- (fill in your plans)
```

Cairn also warns before generating if it detects common secret patterns in your diff — API keys, tokens, or PEM blocks staged by accident.

---

## Configuration

Cairn resolves settings in three layers, lowest to highest priority:

**1. Global config** (`~/.claude/cairn.config`) — your personal defaults across all projects
**2. Local config** (`./cairn.config`) — project-level overrides
**3. Per-run flags** (`$ARGUMENTS`) — always win, override both config files

### Config key reference

| Key | Default | Description |
|---|---|---|
| `enabled` | `true` | Enable/disable `/cairn-commit` at runtime |
| `style` | `conventional` | Default style for `/cairn-commit` |
| `pr.base` | auto | Default base branch for `/cairn-pr` |
| `pr.style` | `conventional` | Default PR title style |
| `pr.template_file` | — | Path to PR description template (e.g. `.github/pull_request_template.md`) |
| `pr.rules_file` | — | Path to prose generation rules (e.g. `.cairn/pr-rules.md`) |
| `changelog.style` | `conventional` | Default changelog grouping style |
| `changelog.extra_types` | — | Comma-separated extra conventional types (e.g. `hotfix,release`) |
| `changelog.exclude_paths` | — | Comma-separated path prefixes to exclude |
| `summary.format` | `standup` | Default output format for `/cairn-summary` |
| `summary.window` | `1 day ago` | Default time window for `/cairn-summary` |

### Example `cairn.config`

```
enabled: true
style: conventional
pr.base: develop
pr.rules_file: .cairn/pr-rules.md
summary.format: slack
```

### PR rules file

The `pr.rules_file` is freeform prose that shapes how `/cairn-pr` generates descriptions. Example `.cairn/pr-rules.md`:

```markdown
- Emphasize WHY changes were made, not just what changed
- Keep the summary to 3 bullets maximum
- If the branch name contains a ticket number (e.g. PROJ-123), include it in the PR title
- Omit the "Changes" file list if fewer than 3 files changed
- Use technical language appropriate for code review
```

---

## cairn CLI

A global install also provides a `cairn` command for managing your setup:

```bash
cairn status                                      # install state + config summary
cairn config show                                 # full effective config with sources

cairn disable local                               # silence /cairn-commit for this project
cairn disable global                              # silence everywhere
cairn enable local                                # restore

cairn config set --style=plain                    # plain style for this project
cairn config set --style=conventional --global    # conventional everywhere
cairn config set --pr-base=develop                # default PR base branch
cairn config set --pr-rules=.cairn/pr-rules.md    # set rules file
cairn config set "--summary-window=1 week ago"    # widen summary window
cairn config reset local                          # wipe project overrides

cairn update                                      # pull latest command files
cairn uninstall global --claude-md                # full removal
```

Run `cairn help` for the full reference.

---

## Roadmap

- [x] `/cairn-commit` — generate a Conventional Commits message from staged diff
- [x] `/cairn-pr` — generate a full PR title and description from the branch diff vs base
- [x] `/cairn-changelog` — generate a CHANGELOG entry from a commit range
- [x] `/cairn-summary` — plain-language standup summary of what changed and why
- [x] `cairn.config` support for extra conventional types, exclude paths, and per-command settings
- [x] `cairn disable` / `enable` respected by the command file at runtime
- [ ] MCP server upgrade for richer git integration

---

## Works well with

[**bonsai**](https://github.com/ValentinFigue/bonsai) — AST-powered refactoring for Claude Code. Bonsai makes the cuts; cairn records them.

[**whetstone**](https://github.com/ValentinFigue/whetstone) — Plan critic. Whetstone sharpens the plan before you build; cairn narrates what you built.

---

## License

MIT — see [LICENSE](LICENSE).
