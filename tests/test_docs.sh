#!/usr/bin/env bash
# tests/test_docs.sh — `aether docs`.
#
# The 1.5.0 documentation audit found ten defects by hand. Eight were mechanically
# detectable, and this is the mechanism. Two properties matter more than any single
# check, because together they are what "works in any repo" means:
#
#   1. It runs against a repository that is not this one, because the schema and the
#      subcommand list come from the installed engine rather than the working directory.
#   2. It catches prose contradicting `[project]`, which is the family that is both the
#      highest value and unique to aether — no generic markdown linter knows what your
#      real test command is.
#
# The other governing constraint is **do not cry wolf**. A doc check that reports
# plausible-but-wrong findings gets deleted from the config within a week, so every
# family here has a negative case: a correct document must be silent.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"
FIXTURES=()
cleanup() { for f in "${FIXTURES[@]}"; do rm -rf "$f"; done; }
trap cleanup EXIT

# fixture <<'EOF' … EOF   — a throwaway repo that is emphatically not this one.
# Writes README.md from stdin, echoes the directory.
fixture() {
  local d; d=$(mktemp -d); FIXTURES+=("$d")
  mkdir -p "$d/.aether"
  cat > "$d/README.md"
  printf '%s' "$d"
}

# [project] commands are ignored until the project is trusted, so a fixture that
# declares them has to consent the way a real one does. Without this the family
# that compares prose against the declared commands cannot run.
trust_fixture() { ( cd "$1" && env HOME="$1/home" AETHER_REPO="$REPO" bash "$CLI" trust >/dev/null 2>&1 ); }

# docs <dir> → the report; sets $DOCS_RC
docs() {
  local out; out=$( cd "$1" && env HOME="$1/home" AETHER_REPO="$REPO" bash "$CLI" docs 2>&1 )
  DOCS_RC=$?
  printf '%s' "$out"
}

reports() {   # reports <dir> <needle> <label>
  local out; out=$(docs "$1")
  assert_contains "$out" "$2" "$3"
}
silent() {    # silent <dir> <label>
  local out; out=$(docs "$1")
  case "$out" in
    *"nothing to report"*) pass "$2" ;;
    *) fail "$2" "expected silence, got: $(printf '%s' "$out" | grep -E '✗|!' | head -2 | tr '\n' ' ')" ;;
  esac
}

# ── the property that makes this useful anywhere ─────────────────────────────
suite "runs in a repo that is not this one"
D=$(fixture <<'EOF'
# Somebody Else's Project

```bash
aether nonsense --wat
```
EOF
)
reports "$D" "aether nonsense" "a foreign repo still gets its aether claims checked"
reports "$D" "not a subcommand" "…because the subcommand list comes from the install"

# ── docs contradicting [project] ─────────────────────────────────────────────
# The headline family: `[project]` declares how the repo really runs, so prose
# saying otherwise is drift — and it is what a new joiner follows on day one.
suite "docs contradict [project]"
D=$(fixture <<'EOF'
# Project

Run the tests:

```bash
pytest
```
EOF
)
printf '[project]\ntest: uv run --frozen pytest\n' > "$D/.aether/config"; trust_fixture "$D"
reports "$D" "uv run --frozen pytest" "a doc omitting the declared wrapper is reported"
reports "$D" "runs this as" "…saying what the config actually declares"

D=$(fixture <<'EOF'
# Project

```bash
uv run --frozen pytest
```
EOF
)
printf '[project]\ntest: uv run --frozen pytest\n' > "$D/.aether/config"; trust_fixture "$D"
silent "$D" "a doc matching the declared command is silent"

# A monorepo: one command correct for one area and wrong for the other.
suite "docs contradict [project:<area>]"
D=$(fixture <<'EOF'
# Monorepo

```bash
bun run lint-ci
npm run lint-ci
```
EOF
)
printf '[project:web]\nlint: bun run lint-ci\n' > "$D/.aether/config"; trust_fixture "$D"
reports "$D" "uses bun, this says npm" "a different runner for the same job is reported"

# ── config examples ──────────────────────────────────────────────────────────
suite "config examples"
D=$(fixture <<'EOF'
# Project

```
[temper]
critical_paths: *auth*, *token*
```
EOF
)
reports "$D" "pipe-separated" "a comma-separated patternlist is reported"
reports "$D" "matches nothing" "…and says why it matters"

D=$(fixture <<'EOF'
# Project

```
[temper]
critical_paths: *auth*|*token*
```
EOF
)
silent "$D" "a pipe-separated patternlist is silent"

D=$(fixture <<'EOF'
# Project

```
[temper]
auto_nudge_line: 400
```
EOF
)
reports "$D" "no plugin declares this key" "a misspelled key is reported"

D=$(fixture <<'EOF'
# Project

```
[cairn]
style: shouting
```
EOF
)
reports "$D" "must be one of" "a value outside an enum is reported"

# A key exactly one section declares can be attributed without a header; one that
# several declare cannot, and must not be guessed at.
D=$(fixture <<'EOF'
# Project

```
critical_paths: *auth*, *token*
enabled: banana
```
EOF
)
out=$(docs "$D")
assert_contains "$out" "critical_paths" "a section-less example is checked when the key is unambiguous"
case "$out" in
  *"enabled"*) fail "an ambiguous section-less key is not guessed at" "reported 'enabled'" ;;
  *) pass "an ambiguous section-less key is not guessed at" ;;
esac

# ── aether's own claims ──────────────────────────────────────────────────────
suite "aether CLI claims"
D=$(fixture <<'EOF'
# Project

```bash
aether install --suite
temper config set auto_nudge_lines 300
```
EOF
)
reports "$D" "--suite is not a flag" "a flag no command parses is reported"
out=$(docs "$D")
case "$out" in
  *"config set"*) fail "a real plugin subcommand is not reported" "flagged config set" ;;
  *) pass "a real plugin subcommand is not reported" ;;
esac

D=$(fixture <<'EOF'
# Project

```bash
bonsai enable-hook
```
EOF
)
reports "$D" "not a plugin subcommand" "an invented plugin subcommand is reported"

# ── dead references ──────────────────────────────────────────────────────────
suite "dead references"
D=$(fixture <<'EOF'
# Project

See [the guide](docs/guide.md) and [the top](#project).

Also [nowhere](#no-such-heading).
EOF
)
reports "$D" "docs/guide.md" "a link to a missing file is reported"
reports "$D" "no-such-heading" "a link to a missing anchor is reported"
out=$(docs "$D")
case "$out" in
  *"#project"*) fail "a valid anchor is not reported" "flagged #project" ;;
  *) pass "a valid anchor is not reported" ;;
esac

# GitHub does not collapse runs of whitespace when slugifying, so an em dash
# between words leaves two hyphens. Collapsing them reported every such anchor.
D=$(fixture <<'EOF'
# Project

Jump to [areas](#monorepos--projectpath).

### Monorepos — `[project:<path>]`
EOF
)
silent "$D" "an anchor with a double hyphen from a dropped em dash resolves"

# ── transcripts are output, not commands ─────────────────────────────────────
# `$ aether status` followed by its output made every output line look like an
# unknown subcommand — the noise that would get this check switched off.
suite "transcripts"
D=$(fixture <<'EOF'
# Project

```
$ aether status
aether v1.5.0

  bonsai       enabled
  whetstone    enabled
```
EOF
)
silent "$D" "output lines in a prompted block are not read as commands"

# ── a block that cds first ───────────────────────────────────────────────────
suite "relative paths after a cd"
D=$(fixture <<'EOF'
# Project

```bash
cd sub
bash script.sh
```
EOF
)
mkdir -p "$D/sub" && printf '#!/bin/sh\n' > "$D/sub/script.sh"
silent "$D" "a path that exists relative to the block's cd is not reported"

D=$(fixture <<'EOF'
# Project

```bash
bash scripts/gone.sh
```
EOF
)
reports "$D" "no such file" "a path that exists nowhere is reported"

# ── legacy paths ─────────────────────────────────────────────────────────────
suite "retired paths"
D=$(fixture <<'EOF'
# Project

Create `temper.config` in your project root.
EOF
)
reports "$D" "was replaced by" "a pre-1.1 config path is reported"

D=$(fixture <<'EOF'
# Project

## Upgrading

`aether migrate` folds `temper.config` into the new sectioned file.
EOF
)
silent "$D" "…but not inside a migration note"

# ── scoping and exit codes ───────────────────────────────────────────────────
suite "scoping"
D=$(fixture <<'EOF'
# Project

[gone](nope.md)
EOF
)
printf '[docs]\nignore: README.md\n' > "$D/.aether/config"
out=$(docs "$D")
assert_contains "$out" "No documentation to check" "[docs] ignore removes a file from the scan"

D=$(fixture <<'EOF'
# Project

[gone](nope.md)
EOF
)
docs "$D" >/dev/null
assert_exit 1 "$DOCS_RC" "a problem exits 1, so CI can use it"

D=$(fixture <<'EOF'
# Project

Nothing to see.
EOF
)
docs "$D" >/dev/null
assert_exit 0 "$DOCS_RC" "a clean repo exits 0"

# An untrusted project cannot have its [project] commands read, so the check must
# say so rather than quietly checking less than the config implies.
suite "untrusted projects are told"
D=$(fixture <<'EOF'
# Project

```bash
pytest
```
EOF
)
printf '[project]\ntest: uv run --frozen pytest\n' > "$D/.aether/config"
out=$(docs "$D")
assert_contains "$out" "not trusted" "an untrusted project is told the family did not run"
assert_contains "$out" "aether trust" "…and how to fix it"

# ── this repo, which was audited by hand two commits ago ─────────────────────
suite "the repo's own docs"
out=$( cd "$REPO" && bash "$CLI" docs 2>&1 ); e=$?
assert_exit 0 "$e" "aether's own documentation passes"
assert_contains "$out" "nothing to report" "…with nothing to report"

summary
