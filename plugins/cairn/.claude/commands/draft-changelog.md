Draft a CHANGELOG entry — from a commit range, from fragment files, or from the [Unreleased] section, whichever the config declares (cairn).

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
aether config show cairn --raw 2>/dev/null || true
```

Each line is `key: value`, already resolved — global `~/.aether/config`, then the
project's `.aether/config`, per key, with declared defaults filled in. Nothing
left to merge. If it prints nothing (aether missing or pre-1.1), use the
documented fallbacks below and continue rather than failing.

Resolve:
- `changelog.style` — default style if `--style` not in $ARGUMENTS; fallback to `style:`; fallback to `conventional`
- `changelog.extra_types` — comma-separated extra conventional type names (e.g. `hotfix,release`) to treat as valid types
- `changelog.exclude_paths` — comma-separated path prefixes to exclude from the changed-files context
- `changelog.fragments` — the changelog model: `dir` (one fragment file per change), `unreleased` (entries accumulate under an `[Unreleased]` heading), or empty/`none` (release-time commit range)
- `changelog.fragments_dir` — the directory fragment files land in, when the model is `dir`

**Step 2 — Resolve the changelog model**

Three models. The config decides which one this project uses; `--version` decides which end of it you are on.

- **`changelog.fragments` empty or `none`** — the range model: keep reading, Steps 3 to 5 below are the whole command.
- **`dir`** — fragments live as files under `changelog.fragments_dir`:
  - *Without `--version`* (a user-visible change just landed): write one fragment file `<fragments_dir>/<slug>.<type>.md`, where `<slug>` follows the pattern visible in existing fragment names (towncrier-style issue numbers if the directory uses them, otherwise a short kebab-case slug), and `<type>` is `feature`, `fix`, `doc`, or `removal`. The file contains the single bullet, imperative mood, no heading. Print the file path and its content; the user (or you, on their instruction) creates it.
  - *With `--version=<v>`* (release): read every fragment file in `<fragments_dir>`, group by type into the Keep-a-Changelog sections (`feature`→Added, `fix`→Fixed, `doc`→Changed, `removal`→Removed, unknown suffix→Changed), and within a section order by filename. Print the assembled `## [<version>] — <date>` entry, then list the consumed fragment files: they are deleted **only after** the entry has been saved to `CHANGELOG.md` — pasting first, deleting second, never the other order.
- **`unreleased`** — entries accumulate under `## [Unreleased]` in `CHANGELOG.md`:
  - *Without `--version`*: print the bullet(s) for this change, imperative mood, to append under the `[Unreleased]` heading.
  - *With `--version=<v>`* (release): read `CHANGELOG.md`, print the `[Unreleased]` section retitled to `## [<version>] — <date>` followed by a fresh empty `## [Unreleased]` heading, ready to paste over the old section.

In both fragment models an empty set at release time (no fragment files, no `[Unreleased]` section) prints: "Nothing to assemble for `<version>`." and stops.

Change-time needs no existing set — an empty fragments directory or a missing `[Unreleased]` heading is the normal first-change state:

- `dir`: create `<fragments_dir>` if it does not exist, and write the first fragment into it.
- `unreleased`: if `CHANGELOG.md` has no `[Unreleased]` heading, print the bullet and note that the heading must be created above the latest version heading.

The write-nothing rule below applies to every model: the command prints; files are created and fragments deleted by explicit instruction, never as a side effect.

**Step 3 — Resolve range**

Determine `<from>`:
- Use `--from=<ref>` if provided
- Otherwise: `git describe --tags --abbrev=0 2>/dev/null` (last tag)
- If no tags exist: `git rev-list --max-parents=0 HEAD` (first commit)

Determine `<to>`:
- Use `--to=<ref>` if provided, otherwise `HEAD`

Determine `<version>`:
- Use `--version=<semver>` if provided, otherwise `[Unreleased]`

**Step 4 — Read git data**

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

**Step 5 — Generate CHANGELOG entry**

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

**Step 6 — Output**

Print the CHANGELOG entry in a single fenced markdown block, ready to paste into `CHANGELOG.md`.

Do not write any files. Do not run `git commit`.
