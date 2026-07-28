# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.5] - 2026-05-07

### Added

- `hooks/enforce-whetstone.sh` — new PreToolUse hook with two non-blocking gates:
  - **Gate 1 (Bash):** nudges on `git push`/`git commit` when the newest plan file in `.claude/plans/` is newer than `CRITIQUE.md` (stale critique) or when a plan exists with no critique at all
  - **Gate 2 (Write/Edit/MultiEdit):** nudges once per project on the first source-file write (`.py/.ts/.tsx/.js/.jsx/.mjs`) when no `CRITIQUE.md` exists; uses a `.whetstone-nudged` sentinel to fire only once
  - Bypass: `# whetstone:skip` or `# suite:skip` in the command silences both gates
- `install.sh`: downloads and installs `enforce-whetstone.sh`; registers it as a PreToolUse hook in `settings.json` via new `_json_add_hook()` function (Python/Node/jq fallback, deduplication-safe)
- `uninstall.sh`: removes hook file and deregisters from `settings.json` via new `_json_remove_hook()` function

### Changed

- `templates/CLAUDE.md`: replaced thin auto-trigger block with full planning discipline including explicit trigger/skip criteria, cross-suite integration rules (temper Design findings, bonsai dry-run surprises), plan file conventions, severity handoff table, and skip syntax documentation

---

## [0.1.4] - 2026-05-07

### Added

- `README.md`: "Bypassing whetstone" section documenting all three skip mechanisms (`/autocritic --off`, `# whetstone:skip`, `# suite:skip`) with scope and use-case table
- `README.md`: Expanded "Works well with" section into a full suite table covering temper, cairn, bonsai, and whetstone
- `templates/CLAUDE.md`: "Skipping the auto-trigger" section documenting `# whetstone:skip` and `# suite:skip` plan-heading markers

---

## [0.1.3] - 2026-05-06

### Changed

- `/autocritic` now writes `CRITIQUE.md` to `.claude/plans/CRITIQUE.md` instead of the project root. Resolution order: local `.claude/plans/` → global `~/.claude/plans/` → create `.claude/plans/` locally. This keeps critique output out of the project root and co-located with plan files. **Breaking:** existing `CRITIQUE.md` at the project root will no longer be updated; move it to `.claude/plans/CRITIQUE.md` to preserve your history.

---

## [0.1.2] - 2026-05-06

### Changed

- `templates/CLAUDE.md` now instructs Claude to re-run `/autocritic` after every user-requested plan modification, not just after the initial plan presentation

---

## [0.1.1] - 2026-05-06

### Changed

- `install.sh` and `uninstall.sh` now automatically inject and remove `Read`/`Write` permissions in the relevant `settings.json` (`~/.claude/settings.json` for global installs, `.claude/settings.json` for local) — eliminates permission prompts when reading config files or writing `CRITIQUE.md`
- Removed the "5 most recently modified files" step from context gathering in `/autocritic` — it added noise without improving critique quality

### Fixed

- Permission prompts triggered on every run when reading `whetstone.config` or writing `CRITIQUE.md`

---

## [0.1.0] - 2026-05-06

First public release.

### Added

- `/autocritic` Claude Code custom command — runs adversarial critics against a plan before implementation
- Three default critics: **implementation** (missing details, edge cases), **architecture** (coupling, abstractions), **risk** (security, data loss, ops surprises)
- Four optional deep-dive critics: **testing**, **complexity**, **API contract**, **cost/ops** — activated via `--only=` or `--skip=`
- Severity ratings: 🔴 blocker, 🟡 significant, 🟢 minor
- Per-run flags: `--only`, `--skip`, `--severity`, `--off`, `--help`
- `whetstone` CLI (`bin/whetstone`) for managing install state and config:
  - `whetstone status` — show install state and effective config
  - `whetstone enable/disable` — toggle globally or per project
  - `whetstone config set/reset` — write config flags to `whetstone.config`
  - `whetstone update` — pull latest `autocritic.md` from upstream
  - `whetstone uninstall` — full removal including optional CLAUDE.md cleanup
- Three-layer config resolution: global `~/.claude/whetstone.config` → local `./whetstone.config` → per-run flags
- `whetstone.config.md` support — prose instructions injected into every critique pass
- `install.sh` with `global` and `local` modes; `--claude-md` flag to inject planning discipline into `~/.claude/CLAUDE.md`
- `uninstall.sh` with symmetric global/local modes and optional CLAUDE.md section removal
- `templates/CLAUDE.md` — drop-in snippet for auto-triggering `/autocritic` after every plan
- `plans/CRITIQUE.md` and `plans/example-plan.md` — real-world example of a plan and its critique output
- MIT license
