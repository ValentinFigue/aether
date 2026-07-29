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
| `/draft-commit` | Generate a Conventional Commits message from staged diff |
| `/draft-pr` | Generate a PR title and description from branch diff |
| `/draft-changelog` | Generate a CHANGELOG entry from a commit range |
| `/draft-summary` | Plain-language standup, Slack message, or formal summary |

---

## Install

cairn ships as part of the [aether suite](../../README.md). Clone once, then install
either the whole suite or cairn alone.

**Whole suite** — whetstone, bonsai, temper and cairn behind one hook:

```bash
git clone https://github.com/ValentinFigue/aether
cd aether && bash install.sh --global --claude-md
```

**cairn alone** — global, available in every project:

```bash
git clone https://github.com/ValentinFigue/aether
cd aether/plugins/cairn && bash install.sh global
```

This installs all four cairn commands, the `cairn` CLI to `~/.local/bin/`, the
`enforce-cairn` (PreToolUse) and `post-cairn` (PostToolUse) hooks, and the required
`Bash`, `Read` and `Write` permissions in `~/.claude/settings.json` so git commands run
without permission prompts.

**With documentation rules** — also injects project behaviour rules into `~/.claude/CLAUDE.md`:

```bash
bash install.sh global --claude-md
```

**Local only** — available in this project only:

```bash
bash install.sh
```

The installer reads everything from the clone, so keep it around — or re-run it after
moving it. There is no `curl | bash` one-liner: the script copies files out of the
repository and cannot work when piped.

Restart Claude Code. The cairn commands are immediately available.

**To uninstall:**

```bash
bash uninstall.sh global --claude-md   # global
bash uninstall.sh                      # local
```

**Hook bypass:**

The hooks are non-blocking nudges. To silence a specific nudge, append a bypass marker to the git command:

```bash
git commit -m "wip"        # cairn:skip   — silence cairn only
git push origin main       # suite:skip   — silence all suite hooks
```

`# cairn:skip` silences cairn's nudge for that command. `# suite:skip` silences all installed suite hooks (cairn, temper, whetstone, bonsai) simultaneously. Bash treats these as comments, so the command runs unchanged.

---

## Usage

### `/draft-commit` — commit messages

Stage your changes, then run `/draft-commit` in Claude Code:

```
git add src/auth/token.py
/draft-commit
```

### `/draft-pr` — PR descriptions

On your feature branch, run `/draft-pr`:

```
/draft-pr
/draft-pr --base=develop
```

### `/draft-changelog` — CHANGELOG entries

```
/draft-changelog
/draft-changelog --from=v0.1.0 --version=0.2.0
```

### `/draft-summary` — standup and status updates

```
/draft-summary
/draft-summary --format=slack
/draft-summary --from=v0.1.0 --format=paragraph
```

---

## Quick reference

| Command | What it does |
|---|---|
| `/draft-commit` | Conventional Commits message from staged diff |
| `/draft-commit --style=plain` | Plain imperative-mood message |
| `/draft-commit --off` | Skip this run |
| `/draft-pr` | PR title + description (auto-detects base branch) |
| `/draft-pr --base=develop` | Diff against `develop` instead of `main` |
| `/draft-pr --style=plain` | Plain PR title |
| `/draft-pr --apply` | Generate, then push the description to the PR via `gh pr edit` |
| `/draft-pr --apply --title` | Also set the PR title (opt-in — titles are often hand-edited) |
| `/draft-pr --apply --pr=42` | Target a specific PR instead of the current branch's |
| `/draft-changelog` | CHANGELOG entry from last tag to HEAD |
| `/draft-changelog --from=v0.1.0 --version=0.2.0` | Specify range and version |
| `/draft-changelog --style=plain` | Flat bullet list, no type grouping |
| `/draft-summary` | Standup summary of yesterday's commits |
| `/draft-summary --format=slack` | Slack-ready paragraph |
| `/draft-summary --format=paragraph` | Formal prose summary |
| `/draft-summary --from=v0.1.0` | Summary from a specific tag |

---

## What you get

### `/draft-commit`

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

### `/draft-pr`

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

### `/draft-changelog`

```markdown
## [0.2.0] — 2026-05-06

### Added

- Token expiry validation with configurable ceiling in the auth flow
- Lifecycle diagram updated to reflect new expiry model

### Fixed

- Tokens no longer accepted past their expiry window when clock-skew tolerance exceeds 30s
```

### `/draft-summary`

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
| `enabled` | `true` | Enable/disable `/draft-commit` at runtime |
| `style` | `conventional` | Default style for `/draft-commit` |
| `pr.base` | auto | Default base branch for `/draft-pr` |
| `pr.style` | `conventional` | Default PR title style |
| `pr.template_file` | — | Path to PR description template (e.g. `.github/pull_request_template.md`) |
| `pr.rules_file` | — | Path to prose generation rules (e.g. `.cairn/pr-rules.md`) |
| `changelog.style` | `conventional` | Default changelog grouping style |
| `changelog.extra_types` | — | Comma-separated extra conventional types (e.g. `hotfix,release`) |
| `changelog.exclude_paths` | — | Comma-separated path prefixes to exclude |
| `summary.format` | `standup` | Default output format for `/draft-summary` |
| `summary.window` | `1 day ago` | Default time window for `/draft-summary` |

### Example `cairn.config`

```
enabled: true
style: conventional
pr.base: develop
pr.rules_file: .cairn/pr-rules.md
summary.format: slack
```

### PR rules file

The `pr.rules_file` is freeform prose that shapes how `/draft-pr` generates descriptions. Example `.cairn/pr-rules.md`:

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

cairn disable local                               # silence /draft-commit for this project
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

- [x] `/draft-commit` — generate a Conventional Commits message from staged diff
- [x] `/draft-pr` — generate a full PR title and description from the branch diff vs base
- [x] `/draft-changelog` — generate a CHANGELOG entry from a commit range
- [x] `/draft-summary` — plain-language standup summary of what changed and why
- [x] `cairn.config` support for extra conventional types, exclude paths, and per-command settings
- [x] `cairn disable` / `enable` respected by the command file at runtime
- [ ] MCP server upgrade for richer git integration
- [ ] Workflow guide: run `/critique-diff` to review the diff → `/draft-commit` to narrate it (temper→cairn handoff)

---

## Works well with

Cairn is part of a four-tool suite. Each tool covers a different moment in the development loop:

| Tool | When | What it does |
|---|---|---|
| [**whetstone**](../whetstone/) | Before you build | Critiques plans — sharpens the approach before any code is written |
| [**bonsai**](../bonsai/) | While you build | AST-safe rename, move, and dead-code detection for Python and TypeScript |
| [**temper**](../temper/) | After you build | Critiques diffs before commit — catches issues while context is live |
| **cairn** | When you ship | Narrates commits, PRs, and changelogs from the actual diff |

The highest-value handoff in the suite: after temper finds no blockers, run `/draft-commit` immediately — the review is fresh and the staged diff is ready.

---

## License

MIT — see [LICENSE](LICENSE).
