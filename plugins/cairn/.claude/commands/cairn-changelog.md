Parse $ARGUMENTS for flags. Supported flags:
- `--from=<ref>` — starting ref (tag, SHA, or branch); default: last tag
- `--to=<ref>` — ending ref; default: `HEAD`
- `--version=<semver>` — version string for the heading; default: `[Unreleased]`
- `--style=conventional` (default) — group entries by Keep-a-Changelog section (Added, Changed, Fixed)
- `--style=plain` — flat bulleted list, no grouping

---

**Step 1 — Read config**

Run:

```bash
{ cat ./cairn.config 2>/dev/null; echo "---CAIRN_SEP---"; cat "$HOME/.claude/cairn.config" 2>/dev/null; }
```

Split on `---CAIRN_SEP---`. Local config takes precedence.

Resolve:
- `changelog.style` — default style if `--style` not in $ARGUMENTS; fallback to `style:`; fallback to `conventional`
- `changelog.extra_types` — comma-separated extra conventional type names (e.g. `hotfix,release`) to treat as valid types
- `changelog.exclude_paths` — comma-separated path prefixes to exclude from the changed-files context

**Step 2 — Resolve range**

Determine `<from>`:
- Use `--from=<ref>` if provided
- Otherwise: `git describe --tags --abbrev=0 2>/dev/null` (last tag)
- If no tags exist: `git rev-list --max-parents=0 HEAD` (first commit)

Determine `<to>`:
- Use `--to=<ref>` if provided, otherwise `HEAD`

Determine `<version>`:
- Use `--version=<semver>` if provided, otherwise `[Unreleased]`

**Step 3 — Read git data**

Run these Bash commands:

```bash
# Commit subjects for grouping
git log --pretty=format:"%s" <from>..<to>

# Date of the earliest commit for the heading
git log --pretty=format:"%ad" --date=short <from>..<to> | tail -1

# Changed files (for context, excluding exclude_paths)
git diff --name-only <from>..<to>
```

If the commit list is empty, print: "No commits found between `<from>` and `<to>`." and stop.

**Step 4 — Generate CHANGELOG entry**

Resolve style:
1. `--style=<x>` in $ARGUMENTS
2. `changelog.style` from config
3. Default: `conventional`

**Conventional style** — map each commit subject to a Keep-a-Changelog section:

| Conventional type | Section |
|---|---|
| `feat` | Added |
| `fix` | Fixed |
| `docs`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`, `style` | Changed |
| Any extra types from `changelog.extra_types` | Changed |
| Non-conventional format | Changed (fallback) |
| `BREAKING CHANGE` in footer | prepend ⚠️ to its bullet and put first in Changed |

Apply `changelog.exclude_paths`: if a commit only touches excluded paths, omit it.

Format:
```markdown
## [<version>] — <date>

### Added

- <bullet from feat commits>

### Changed

- <bullet from other commits>

### Fixed

- <bullet from fix commits>
```

Omit any section that has no entries.

**Plain style** — flat list, no sections:
```markdown
## [<version>] — <date>

- <bullet for each commit, one per line>
```

Rules for all bullets:
- Imperative mood
- Strip the conventional type prefix — write the intent, not the commit subject verbatim
- Merge closely related commits into a single bullet if they describe the same logical change

**Step 5 — Output**

Print the CHANGELOG entry in a single fenced markdown block, ready to paste into `CHANGELOG.md`.

Do not write any files. Do not run `git commit`.
