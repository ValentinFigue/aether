# trellis

Surveys a repository and writes the config the rest of the suite reads.

```bash
/draft-config          # detect, ask about the gaps, write .aether/config
/draft-config --global # write ~/.aether/config instead
/draft-config --dry-run
```

## Why it exists

`[project]` is the section that upgrades temper's Coverage critic from inferring
that tests exist to running them. It is also the section nobody fills in, because
writing five shell commands by hand is exactly the sort of task that gets
postponed.

trellis fills it in from evidence and asks only about what it could not find.

## Where it looks, in order

**CI workflows first.** `run:` lines in `.github/workflows/*.yml` are the
commands that provably work in a clean checkout — someone maintains them, and
they fail loudly when they rot. Manifest scripts are noisier: this repository's
own `package.json` offers `test:watch`, which a critic must never run.

**Then manifests** — `pyproject.toml`, `package.json`, `Makefile`, `justfile` —
skipping anything that watches, serves, deploys, publishes, or takes an
interactive prompt.

**Then the repo itself**, for the per-plugin defaults: how large commits tend to
be, which paths look security-sensitive, whether commits follow Conventional
Commits, what scopes are actually in use.

Every key it writes carries a comment naming where the value came from, so you
can tell a detected command from a guess.

## What it does not do

- It does not run anything it detects. Detection reads files; `aether trust` is
  what allows a critic to execute them, and that is your decision.
- It does not overwrite a key you have already set.
- It never selects a watch-mode, server, or deploy script.

## Install

trellis ships no installer, which is the point:

```bash
aether install trellis          # local
aether install trellis global
aether uninstall trellis
```

MIT.
