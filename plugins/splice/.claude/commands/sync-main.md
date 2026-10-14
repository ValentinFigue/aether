Merge the base branch into the current branch and resolve the conflicts (splice).

Parse $ARGUMENTS for flags. Supported flags:

| Flag | Effect |
|------|--------|
| `--base=<branch>` | Sync from this branch instead of the auto-detected base |
| `--rebase` | Rebase onto the base instead of merging |
| `--force` | With `--rebase`, proceed although the branch has a pushed upstream |
| `--dry-run` | Report what would conflict, touching nothing |
| `--abort` | Abort the merge or rebase currently in progress |
| `--off` | Print "splice disabled for this run." and stop |
| `--help` | Print this flag table and stop |

`/critique-pr` reviews what someone is about to merge. This command *performs*
a merge — base into the current branch — with the conflicts resolved rather
than left as markers, and nothing pushed at the end.

---

## The contract

- **Never push.** The merge commit is local; the push is the user's.
- **Never force anything, never auto-stash.** A dirty tree stops the run.
- **Unresolved stays unresolved.** A conflict whose sides cannot be read with
  confidence keeps its markers, stays unstaged, and is reported.
- **`--abort` is always available** while a merge or rebase is in progress.

---

## Configuration

Run this single Bash command:

```bash
aether config show splice --raw 2>/dev/null || true
```

Each line is `key: value`, already resolved. If it prints nothing (aether
missing or not installed), use the documented defaults and continue rather than
failing. Honour `enabled: false` by printing "splice is disabled for this
project. Run `aether enable splice` to re-enable." and stopping.

Resolve the base branch, highest first:

1. `--base=<branch>` in $ARGUMENTS
2. `base` from the `[git]` section (`aether config show git --raw 2>/dev/null`)
3. Auto-detect, same as `/draft-pr`:

```bash
git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || \
git rev-parse --verify origin/master >/dev/null 2>&1 && echo "master" || \
git rev-parse --verify main >/dev/null 2>&1 && echo "main" || \
echo "master"
```

Store the result as `<base>`, and `<remote-base>` as `origin/<base>` when
`git rev-parse --verify origin/<base>` succeeds, `<base>` otherwise.

## Step 1 — Preflight

Refuse to run — say which gate failed, and stop — unless every check passes:

```bash
git rev-parse --abbrev-ref HEAD    # must not be <base>
git status --porcelain             # must be empty
```

On the base branch itself, print "Already on <base> — sync a working branch,
not the base itself." and stop. On a dirty tree, list the offending paths and
stop: the user commits or stashes. This command never stashes on anyone's
behalf, because a stash the command cannot restore is worse than a refused run.

Then fetch:

```bash
git fetch origin
```

In `--rebase` mode, check the upstream before anything else:

```bash
git rev-parse --abbrev-ref @{u} 2>/dev/null
```

If that succeeds the branch has been pushed, and a rebase rewrites commits the
remote already has. Stop with that message, and say `--rebase --force` re-runs
it with the rewrite made explicit — the force-push that follows is still the
user's, and this command never performs one.

## Step 2 — Measure

```bash
git rev-list --count HEAD..<remote-base>
git log --oneline HEAD..<remote-base>
```

Zero incoming commits: print "Already up to date with <remote-base>." and stop.
Otherwise report the count and the incoming commits before merging — that list
is what the conflict resolution will be read against in Step 5.

## Step 3 — Merge (or rebase)

Default:

```bash
git merge <remote-base>
```

With `--rebase`:

```bash
git rebase <remote-base>
```

A rebase replays *this branch's* commits onto the base, so a conflict appears
once per replayed commit that touches the same lines — a branch behind by ten
commits can present the same conflict ten times, and `git rebase --continue`
moves to the next. Say so when it happens, and recommend a merge (`/sync-main`
without `--rebase`) on the next run when the branch is far behind: a merge
presents each conflict once.

If the merge or rebase completes with no conflict, skip to Step 6.

## Step 4 — Dry-run

With `--dry-run`, Steps 1–2 run, then:

```bash
git merge-tree --write-tree HEAD <remote-base>
```

`--write-tree` computes the merge in the object database — the working tree,
the index and HEAD are untouched. It needs git 2.38 or newer; on an older git,
print "dry-run needs git ≥ 2.38, this checkout has $(git --version)" and stop
rather than touching the tree to find out.

The output names every conflicted file. Report them as the files to expect —
grouped by conflict type (both-modified, deleted-by-one-side, renamed) — and
stop. A dry-run resolves nothing.

## Step 5 — Resolve the conflicts

List them:

```bash
git diff --name-only --diff-filter=U
git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU)'
```

For each conflicted file, in three passes:

**Read intent before text.** Both sides did something on purpose; the resolution
is what both sides were trying to do, arriving together.

```bash
MB=$(git merge-base HEAD <remote-base>)
git show :1:<path>                          # what both sides started from
git show :2:<path>                          # this branch's version
git show :3:<path>                          # the base's version
git log --oneline $MB..HEAD -- <path>       # what this branch did
git log --oneline $MB..<remote-base> -- <path>   # what the base did
```

During a rebase these logs lie: HEAD has already moved onto the base, so the
branch tip is `ORIG_HEAD`, set when the rebase started. Read the intent from
`$MB..ORIG_HEAD` instead of `$MB..HEAD`.

**Resolve by combining.** Write the file so both intents survive. When one
side's change makes the other's meaningless — the base extracted the function
this branch also moved, say — the resolution is the semantic join: the
extracted function, with this branch's changes applied. Not a line-level splice
of conflict markers.

**Stop when you cannot state both intents.** If you cannot say, in one sentence
each, what this branch wanted and what the base wanted, you do not understand
the conflict well enough to resolve it. Leave the markers, leave the file
unstaged, and record it in the report as left for the user. A guessed
resolution is worse than a marker: the marker is honest.

Special cases:

| Case | Rule |
|------|------|
| Lockfiles (`uv.lock`, `package-lock.json`, …) | Never hand-merge. If the lock command is unambiguous from the project's manifests (`uv lock`, `npm install`), take one side, regenerate, and say you did. Otherwise leave for the user. |
| Deleted by one side (DU/UD) | The deletion usually wins when the deleting side removed the file deliberately — read its commit. Flag it in the report when the surviving side kept building on the file. |
| Binary | Take one side, and say which and why. |
| Generated files | Regenerate from source rather than merging the output, when the generator is unambiguous. Otherwise leave for the user. |

After resolving each file, check that it still parses before staging it —
`python3 -m py_compile` for Python, the project's typecheck for TypeScript, or
the bonsai MCP servers' parse when they are configured. A resolution that does
not parse is a wrong resolution: redo it, or leave the markers.

## Step 6 — Verify

On the resolved files, through the project's own commands:

```bash
aether check <resolved files> --raw 2>/dev/null || true
```

`aether check` resolves each file to its monorepo area and runs that area's
test and build commands in its own directory — the only thing that executes
`[project]` commands. If the check printed nothing — the CLI is absent or the
project is not trusted — say that plainly: "verified: nothing — aether
absent" — a reading of the diff is not a test run.

During a rebase, verify once at the end, not once per replayed commit.

## Step 7 — Finalize and report

Stage only what was resolved:

```bash
git add <resolved paths>
```

Then close the operation:

```bash
git commit --no-edit      # merge — the default message names both sides
git rebase --continue     # rebase — if more commits replay, back to Step 5
```

If files are still left for the user, do not run `git commit`: the merge stays
open, `git merge --abort` still works, and the user finishes by hand. Print the
report either way:

```
sync <remote-base> → <branch>   <n> commits, <m> files conflicted
  resolved:  <n>   trivial <t>, semantic <s>
  left:      <n>   markers intact, unstaged — merge still open, --abort available
  verified:  test ✓  build ✓ (project:web)    |    nothing — aether absent
```

Mark each resolution **trivial** (one side did not touch the region, or the two
sides are adjacent) or **semantic** (both sides changed the same region and you
joined them). The semantic ones are a judgement rather than a fact — naming them
tells the user where to look. Every resolution in the report carries its file
path and, in one line, what each side wanted.

**Do not push.** The push after a clean verification is the user's.

## Abort

`--abort` runs, whichever operation is in progress:

```bash
git rev-parse -q --verify MERGE_HEAD && git merge --abort
GD=$(git rev-parse --git-dir)
[ -d "$GD/rebase-merge" ] || [ -d "$GD/rebase-apply" ] && git rebase --abort
```

`git rev-parse --git-dir` rather than a hard-coded `.git` — in a linked
worktree `.git` is a file, and the rebase state lives in the real git dir.

Report what was rolled back, and that the working tree is back to where the run
started. If nothing is in progress, say so and stop.
