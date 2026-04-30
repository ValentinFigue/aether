---
name: bonsai:enforce
description: >
  Redirects structural code operations on Python and TypeScript files to the correct
  bonsai AST tool. Use before reaching for sed, grep, or awk on .py/.ts/.tsx files.
  Covers renaming, moving, finding references, signature changes, and dead-code detection
  across both languages.
when_to_use: >
  Triggered when about to rename a symbol, move a file or symbol, find all usages,
  change a function signature, detect dead code, or do any text replacement on
  .py, .ts, or .tsx files. sed/awk on these files is blocked by the PreToolUse hook —
  this skill fires first so the right tool is chosen before the block is hit.
allowed-tools: mcp__bonsai_py__pyrename, mcp__bonsai_py__pymove, mcp__bonsai_py__pymovesymbol, mcp__bonsai_py__pyfindrefs, mcp__bonsai_py__pycallers, mcp__bonsai_py__pyfindunused, mcp__bonsai_py__pysignature, mcp__bonsai_py__pygrep, mcp__bonsai_ts__tsrename, mcp__bonsai_ts__tsmove, mcp__bonsai_ts__tsmovesymbol, mcp__bonsai_ts__tsfindrefs, mcp__bonsai_ts__tssignature
---

# Bonsai-first: use AST tools, not text tools

`sed` and `awk` on `.py`/`.ts`/`.tsx` files are blocked. Use the bonsai tool that matches the intent:

| Intent | Python | TypeScript |
|---|---|---|
| Rename a symbol | `pyrename` | `tsrename` |
| Move a file | `pymove` | `tsmove` |
| Move a symbol to another module | `pymovesymbol` | `tsmovesymbol` |
| Find all usages of a symbol | `pyfindrefs` | `tsfindrefs` |
| Find only call sites | `pycallers` | `tsfindrefs` (filter by kind) |
| Change a function signature | `pysignature` | `tssignature` |
| Detect dead code / unused imports | `pyfindunused` | — |
| Text search (non-structural) | `pygrep` | Bash `grep` |

## Why not sed/grep for code operations?

- **False matches**: `sed 's/save/persist/g'` renames local variables, string literals, and comments that happen to contain `save`.
- **Missed sites**: imports, re-exports, decorator references, and type annotations are invisible to text substitution.
- **Import paths not updated**: moving a file with `mv` + `sed` leaves stale import paths. `pymove`/`tsmove` rewrites them all.

`grep` for plain text search (string literals, TODO markers, log patterns) is fine and not blocked.

## Dry-run first

All mutating bonsai tools (`pyrename`, `pymove`, `pymovesymbol`, `pysignature`, `tsrename`, `tsmove`, `tsmovesymbol`, `tssignature`) accept `dry_run=True`. Always preview the blast radius before applying.
