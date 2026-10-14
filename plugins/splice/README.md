# splice

Merges the base branch into your working branch and resolves the conflicts —
reading what both sides intended, joining them, and verifying the result.

> **Same commands on Vibe Code and Codex.** `bash install.sh --vibe` / `--codex`
> from the repo root install `/sync-main` as a portable skill with the
> AGENTS.md discipline block, in every project. splice has no gate or hook on
> any agent — see the
> [suite README's Agents section](../../README.md#agents--what-works-where).

```bash
/sync-main               # merge origin/main into this branch, resolve, verify
/sync-main --dry-run     # report what would conflict, touch nothing
/sync-main --rebase      # rebase onto the base instead of merging
/sync-main --abort       # roll back the merge or rebase in progress
```

## Why it exists

"Merge main and resolve the conflicts" is a frequent ask with a repeatable
protocol, done ad hoc every time. The failure mode is not the merge — it is the
resolution: an agent staring at conflict markers resolves them with fabricated
confidence, because nothing tells it which resolutions are safe to make and
which must stay with the human.

splice names that line and refuses to cross it silently.

## What it does

Reads both sides' intent before their text — the three stages of each conflict,
plus the commits each side made to the file — then writes the join. A resolution
that is a fact (one side untouched) is marked **trivial**; one that is a
judgement (both sides changed the same region) is marked **semantic**. The
report says which is which, so the human knows where to look.

What it never does:

- **Never pushes.** The merge commit is local; the push is yours.
- **Never forces anything, never auto-stashes.** A dirty tree stops the run.
- **Never resolves a conflict it cannot explain.** Cannot state what both sides
  wanted → the markers stay, the file stays unstaged, and the report says so.
- **Never hand-merges a lockfile** — regenerate, or leave it for you.

Rebase mode exists (`--rebase`) but is gated: on a branch with a pushed
upstream it refuses unless `--force` makes the history rewrite explicit. A
merge is recoverable; a rebase of pushed history is a force-push waiting at the
end of it.

## Install

splice ships no installer, like trellis — a manifest and a command file:

```bash
aether install splice          # local
aether install splice global
aether uninstall splice
```

MIT.
