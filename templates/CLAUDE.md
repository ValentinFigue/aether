# Documentation sync rules

Any change to `.claude/commands/cairn.md` (flags, output format, behaviour) must be reflected in the README.md Usage and Quick reference sections before the change is committed.

If a flag is added or removed → update the quick reference table in README.md.
If the output format changes → regenerate the sample output block in README.md.
If install steps change → update the Install section in README.md.

# Changelog rules

Every non-trivial change to this repo requires a CHANGELOG.md entry under the correct version heading (Added, Changed, Fixed, or Removed). Bump the version in CHANGELOG.md when adding an entry.

Dogfooding: use `/cairn` to generate commit messages for all commits to this repo (applies after v0.1.0 is tagged).

# Testing rules

Before marking any implementation task complete, verify the command works end-to-end: stage a real change in a test repo, run `/cairn`, and confirm the output is a valid commit message.
