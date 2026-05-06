# Documentation sync rules

Any change to a `.claude/commands/cairn-*.md` file (flags, output format, behaviour) must be reflected in the README.md before the change is committed:
- If a flag is added or removed → update the quick reference table in README.md
- If the output format changes → regenerate the sample output block in README.md
- If install steps change → update the Install section in README.md

# Changelog rules

Every non-trivial change to this repo requires a CHANGELOG.md entry under the correct version heading (Added, Changed, Fixed, or Removed). Bump the version in CHANGELOG.md when adding an entry.

Dogfooding: use `/cairn-commit` to generate commit messages for all commits to this repo.

# Testing rules

Before marking any implementation task complete, verify the command works end-to-end: stage a real change in a test repo, run the relevant cairn command, and confirm the output is correct.
