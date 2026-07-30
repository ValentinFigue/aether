Survey this repository and write the aether config it implies (trellis).

Parse $ARGUMENTS for flags:

| Flag | Effect |
|---|---|
| `--global` | write `~/.aether/config` instead of `.aether/config` |
| `--dry-run` | print what would be written, change nothing |
| `--only=project,git` | write only these sections |
| `--force` | overwrite keys that are already set (default: never) |
| `--off` | print "trellis disabled for this run." and stop |
| `--help` | print this flag table and stop |

---

**Step 0 — Config check**

```bash
aether config show trellis --raw 2>/dev/null || true
```

If `enabled` is `false`, print `trellis is disabled. Run \`aether trellis enable\` to re-enable.` and stop.

Then read what is already set, because **an existing value is never overwritten**
unless `--force` is given:

```bash
aether config show --raw 2>/dev/null || true
aether config path 2>/dev/null; aether config path global 2>/dev/null
```

---

**Step 1 — Is this one project or several?**

Decide this before detecting any command, because it changes what you write.

```bash
ls .github/workflows/*.y*ml 2>/dev/null
grep -n 'working-directory:' .github/workflows/*.y*ml 2>/dev/null
grep -nA8 'filters:' .github/workflows/*.y*ml 2>/dev/null
find . -maxdepth 3 \( -name package.json -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml \) \
  -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null
```

Two signals mean this repo has **areas**, each with its own toolchain:

- CI jobs with different `working-directory:` values — the strongest signal, because
  it is CI telling you where each command must run.
- A paths filter (`web/**`, `backend/**`) deciding which jobs run — CI already scopes
  by path, and that is exactly the scoping to copy.
- Failing both: a manifest in more than one subdirectory.

**One area → one `[project]` section, exactly as before.** Do not invent areas for a
single-language repo; a plain `[project]` is the right answer and adding sections
would make it worse.

**Several → one `[project:<path>]` per area**, where `<path>` is the directory the
commands must run in. Write no commands in the bare `[project]` section: a command
there is root-relative and is not inherited by an area, so it would be dead config.

**Step 1b — Detect each area's commands**

For each area, in this order, and record which source each key came from.

**CI first.** A `run:` line under a job with `working-directory: <area>` is a command
that provably works in a clean checkout — someone maintains it and it fails loudly
when it rots.

```bash
sed -n '/<job-name>:/,/^  [a-z]/p' .github/workflows/ci.yml
```

Also check `.gitlab-ci.yml`, `.circleci/config.yml`, `azure-pipelines.yml`,
`Jenkinsfile`. Skip `run:` lines that are setup rather than verification —
`actions/checkout`, `pip install`, `npm ci`, `bun install`, `uv sync`, cache warming,
artifact upload — and anything that deploys or pushes.

**Then that area's manifest**, read from inside the area: its `package.json`,
`pyproject.toml`, `Makefile`, `justfile`.

**Then convention**, only if nothing above matched, and marked as a guess.

**Map to keys:**

| Key | Looks like |
|---|---|
| `test` | pytest, jest, vitest, `go test`, `cargo test`, `make test`, `npm test` |
| `lint` | ruff check, eslint, flake8, golangci-lint, clippy |
| `format` | `ruff format --check`, `prettier --check`, `gofmt -l`, `cargo fmt --check` |
| `typecheck` | mypy, pyright, `tsc --noEmit` |
| `build` | `npm run build`, `cargo build`, `go build`, `make` |
| `coverage` | `pytest --cov`, `jest --coverage`, `go test -cover` |
| `check.<name>` | a CI step that fits none of the above but is a real check — a lockfile check (`uv lock --check`), a single-migration-head check, a dependency dedupe check. Name it after what it verifies |

Several commands under one key: join them with `&&`. Four lint-ish CI steps usually
split naturally across `lint`, `format` and `typecheck` — only genuinely paired ones
share a key.

**Never select any of these, whatever the source:**

- anything with `watch`, `--watch`, `-w`, `serve`, `dev`, `start`, `nodemon`
- anything that deploys, publishes, releases, or pushes
- anything interactive, or that reads stdin
- anything with `-u`, `--update-snapshots`, `--fix`, `--write` — a critic must not
  modify the working tree it is reviewing
- an aggregate script that begins with an install (`"ci": "bun install && …"`)

A watch-mode script never terminates. Selecting one would hang a critic
indefinitely, so this rule holds even when it is the only candidate: leave the key
unset and say so.

**Step 2 — Detect the git conventions (`[git]`)**

```bash
git log --pretty=format:'%s' -200
git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'
git log --pretty=format:'%(trailers:only,unfold)' -50 | sort -u | head
```

- `types` and `scopes` — parse `type(scope):` prefixes out of the subjects. Only
  emit them if **at least 60% of the last 200 commits** follow the pattern;
  below that the project does not have a convention and inventing one is worse
  than leaving it unset. Emit the scopes that actually appear, most frequent
  first, dropping any that appear once.
- `ticket` — if subjects or branch names carry a recurring ID, emit the regex
  that matches it. Verify the regex against the sample before writing it.
- `trailers` — any trailer appearing in more than a third of recent commits.
- `base` — the remote default branch, only if it is neither `main` nor `master`;
  auto-detection already handles those two and a redundant key is noise.

---

**Step 3 — Per-plugin defaults**

Only where the repository gives real evidence. A default that matches the
built-in one must not be written: a config file full of restated defaults is
harder to read than one with three lines in it.

- `temper.auto_nudge_lines` — the 75th percentile of recent commit sizes, rounded
  to the nearest 100, if it differs from 200 by more than 100:
  ```bash
  git log --shortstat -60 --pretty=format: | grep -E 'insertion|deletion' | awk '{s=0; for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) s+=$i; print s}' | sort -n
  ```
- `temper.critical_paths` — add patterns for directories that actually exist here
  and are not already covered by the default: migration directories, IaC paths,
  anything named for auth or secrets.
- `cairn.style` — `plain` if fewer than 60% of commits are Conventional.

---

**Step 4 — Ask about the gaps, and only the gaps**

For each `[project]` key with no detected value, ask once, in a single grouped
question with the candidates you rejected and why:

```
I could not find a typecheck command.

  package.json has:  tsc --noEmit --watch   (rejected: watch mode)
  Nothing in CI runs a type check.

  What should `typecheck` be?  (Enter to leave it unset)
```

Do not ask about keys you detected — show them and move on. Do not ask about
`[git]` keys: an absent convention is a legitimate answer and the user can add
one later.

If nothing at all is missing, say so and skip to Step 5.

---

**Step 5 — Write it**

Write each key with `aether config set`, which preserves comments and ordering
and adds the schema's own doc line above the key:

```bash
aether config set project.test "uv run pytest"                      # single-area repo
aether config set project:backend.test "uv run --frozen pytest"     # one area of several
aether config set project:web.typecheck "bun run tsc"
```

`aether config set` takes `<section>.<key>`, and a path area is just a section — so
`project:web.typecheck` is unambiguous even though the path itself contains no dot.
For a path containing a dot, edit the file directly and say you did.

Then append the source comment for each key you wrote, so the file records where
the value came from:

```
[project]
# Shell command that runs the test suite — lets Coverage report real failures…
# trellis: from .github/workflows/ci.yml
test: uv run pytest
# trellis: guessed from pyproject.toml — verify this
typecheck: mypy src
```

With `--global`, pass `global` to every `aether config set` call.

With `--dry-run`, print the file you would produce and write nothing.

**Then a starter `rules.md`**, only if one does not already exist. Import any
prose the user already had:

```bash
aether config get cairn.pr.rules_file
```

If it points at a real file, copy its contents into a `[draft-pr]` section.
Otherwise write the section headers with a comment in each, so the shape is
obvious and nothing is invented:

```markdown
[all]
<!-- Anything every critic should know about this project. -->

[critique-diff]
<!-- e.g. "We use event sourcing — flag anything that bypasses the event log." -->

[draft-pr]
<!-- e.g. "Always mention the ticket ID in the first line." -->
```

---

**Step 6 — Report, and say what happens next**

```
Wrote .aether/config

  [project]
    test        uv run pytest              from .github/workflows/ci.yml
    lint        uvx ruff check             from .github/workflows/ci.yml
    typecheck   —                          not found, and you skipped it
  [git]
    scopes      cli, hooks, plugins        from 200 commits (81% conventional)
    types       feat, fix, docs, refactor   from 200 commits
  [temper]
    auto_nudge_lines  400                  75th percentile of recent commits

  Skipped 2 candidates:
    npm run test:watch   watch mode
    npm run deploy       deploys

Nothing runs yet. `[project]` holds shell commands, so a critic will only
execute them once you have reviewed and trusted them:

  aether trust
```

The last line is not optional. trellis writes commands that a critic would later
run, and a user who does not know about `aether trust` will assume Coverage is
measuring when it is still inferring.
