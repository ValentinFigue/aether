---
name: bonsai-first
description: >
  Redirects structural code operations on Python and TypeScript files to the correct
  bonsai AST tool. Use before reaching for sed, grep, awk, or find on .py/.ts/.tsx files.
  Covers renaming, moving, finding references, signature changes, and dead-code detection
  across both languages.
when_to_use: >
  Triggered when about to rename a symbol, move a file or symbol, find all usages,
  change a function signature, detect dead code, or search for a pattern in
  .py, .ts, or .tsx files. Prefer bonsai AST tools over sed/awk/grep/find on
  these files — text tools miss imports, re-exports, and type references.
allowed-tools: mcp__bonsai-py__pyrename, mcp__bonsai-py__pymove, mcp__bonsai-py__pymovesymbol, mcp__bonsai-py__pyfindrefs, mcp__bonsai-py__pycallers, mcp__bonsai-py__pyfindunused, mcp__bonsai-py__pysignature, mcp__bonsai-py__pygrep, mcp__bonsai-ts__tsrename, mcp__bonsai-ts__tsmove, mcp__bonsai-ts__tsmovesymbol, mcp__bonsai-ts__tsfindrefs, mcp__bonsai-ts__tssignature
---

# Bonsai-first: use AST tools, not text tools

`sed`, `awk`, `grep`, and `find` on `.py`/`.ts`/`.tsx` files are discouraged. Use the bonsai tool that matches the intent:

| Intent | Python | TypeScript |
|---|---|---|
| Rename a symbol | `pyrename` | `tsrename` |
| Move a file | `pymove` | `tsmove` |
| Move a symbol to another module | `pymovesymbol` | `tsmovesymbol` |
| Find all usages of a symbol | `pyfindrefs` | `tsfindrefs` |
| Find only call sites | `pycallers` | `tsfindrefs` (filter by kind) |
| Change a function signature | `pysignature` | `tssignature` |
| Detect dead code / unused imports | `pyfindunused` | — |
| Text search (non-structural) | `pygrep` | `pygrep` |

## Why not sed/grep/find for code operations?

- **False matches**: `grep 'save'` hits local variables, string literals, comments, and unrelated methods with the same name.
- **Missed sites**: imports, re-exports, decorator references, and type annotations are invisible to text search.
- **Import paths not updated**: moving a file with `mv` + `grep`/`sed` leaves stale import paths. `pymove`/`tsmove` rewrites them all.
- **No type awareness**: `grep 'User.save'` can't distinguish `User.save` from `Document.save`. `tsfindrefs` can.

## Dry-run first

All mutating bonsai tools (`pyrename`, `pymove`, `pymovesymbol`, `pysignature`, `tsrename`, `tsmove`, `tsmovesymbol`, `tssignature`) accept `dry_run=True`. Always preview the blast radius before applying.
