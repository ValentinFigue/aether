<!-- bonsai:start -->
## AST Refactoring with Bonsai

When editing `.py`, `.ts`, or `.tsx` files, prefer bonsai MCP tools over text tools (`grep`, `sed`, `awk`, `find`). Text tools miss re-exports, aliased imports, and type references — they silently break code when renaming or moving symbols.

| Operation | Python | TypeScript |
|---|---|---|
| Find all references | `pyfindrefs` | `tsfindrefs` |
| Rename a symbol | `pyrename` | `tsrename` |
| Move a file (update imports) | `pymove` | `tsmove` |
| Move a symbol between modules | `pymovesymbol` | `tsmovesymbol` |
| Change a function signature | `pysignature` | `tssignature` |
| Find dead code | `pyfindunused` | — |
| Regex search | `pygrep` | — |

For mutating tools (`rename`, `move`, `signature`), always request a dry-run preview first, review the diff, then apply.
<!-- bonsai:end -->
