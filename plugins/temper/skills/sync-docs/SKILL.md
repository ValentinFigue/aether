---
name: sync-docs
description: >
  Keep documentation true to the code, in the same change that alters it. Use before or
  while editing a flag, subcommand, config key, default value, exit code, hook matcher,
  threshold, environment variable or public function signature. This is a rule to follow
  while editing — it does not generate or regenerate documentation.
when_to_use: >
  Triggered when a change alters something a document is likely to state: renaming or
  removing a CLI flag or subcommand, changing a config key or its default, changing an
  exit code or return contract, widening a matcher, moving or deleting a file that docs
  link to, or changing what a command prints. Also when deleting a feature, since the
  prose describing it usually outlives the code.
---

# A document that lies is worse than no document

A reader who trusts a false sentence does not go looking for the truth. Missing
documentation makes someone ask; wrong documentation makes them confidently do the wrong
thing, and they only find out later.

**Documentation is part of the change, not a follow-up.** The moment you are editing the
code is the only moment you reliably know what the docs should say.

## Before you finish the change

Grep for the thing you changed. Not the file you expect to be wrong — the *string*:

```bash
git grep -n -- '--old-flag'         # a flag you renamed or removed
git grep -n 'old_key'               # a config key
git grep -n 'oldSubcommand'         # a subcommand
git grep -n 'path/that/moved'       # a file docs link to
```

Then fix every hit in the same commit. If a hit is deliberately historical — a changelog
entry, a migration note, a "before v1.1" aside — leave it and make sure the surrounding
sentence says so.

## What drifts, in rough order of how often

| Changed | Where it is usually also written down |
|---|---|
| A flag or subcommand | README usage block, `--help` text, the CLI reference, per-plugin docs |
| A config key, or its default | The README's config example, the key's own `doc:` string in a manifest, any file the tool generates from it |
| An exit code or return contract | The header comment of the file, the prose that says what "blocks" or "fails" |
| A default value or threshold | Every example that shows the old number |
| A matcher, glob or pattern | Docs quoting the pattern verbatim |
| A file path | Relative markdown links, and commands in fenced blocks |
| What a command prints | Sample output in fenced blocks, which nobody re-runs |

## Two traps

**Sample output goes stale silently.** A fenced block showing `$ mycmd` and its output is
a claim about behaviour. Nothing re-runs it. When you change what a command prints, the
transcript in the docs is now fiction.

**A "deleted" feature usually leaves prose behind.** Removing code removes the behaviour;
it does not remove the paragraph describing it, the roadmap item promising it, or the
example using it.

## Check it, do not just believe it

If the project uses aether, the mechanical half is one command:

```bash
aether docs
```

It reports documented commands and flags that do not exist, config examples whose values
are invalid, prose that contradicts the project's declared `[project]` commands, and dead
links. It cannot judge whether a sentence is still *true* — that is what
`/critique-diff` reads the diff for.
