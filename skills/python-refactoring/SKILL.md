---
name: python-refactoring
description: >
  AST-based Python refactoring for Claude Code via bonsai. Use for: renaming
  classes/functions/methods/variables, moving files and symbols between modules,
  finding all reference sites for a symbol, detecting dead code and unused imports,
  changing function signatures and updating all call sites. Prefers AST analysis
  over grep/sed for accurate Python identifier operations — no false matches from
  comments or string literals.
when_to_use: >
  Triggered by: rename a class/function/method/variable/constant; move a file or
  extract a class to another module; find all usages/callers of a symbol; detect
  dead code or unused imports; add/remove/rename a parameter and update call sites;
  find where a symbol is imported or subclassed.
allowed-tools: mcp__bonsai_py__pyrename, mcp__bonsai_py__pymove, mcp__bonsai_py__pymovesymbol, mcp__bonsai_py__pyfindrefs, mcp__bonsai_py__pycallers, mcp__bonsai_py__pyfindunused, mcp__bonsai_py__pysignature, mcp__bonsai_py__pygrep
---

# Python Refactoring with Bonsai

## When to Use Bonsai Instead of grep/sed

Use bonsai AST tools (not grep or sed) whenever:

- **Renaming a symbol**: `pyrename` finds all true references (imports, calls, decorators,
  base class uses) and skips local variables with the same name that shadow it.
- **Moving a file or symbol**: `pymove` / `pymovesymbol` rewrites import paths project-wide.
- **Finding call sites**: `pycallers` filters to call-type refs only, grouped by file.
- **Finding all references**: `pyfindrefs` returns every import, call, decorator, and base
  class usage, grouped by reference type.
- **Auditing dead code**: `pyfindunused` catches unreferenced top-level symbols, unused
  imports, and params that are never read in the function body.
- **Changing a function signature**: `pysignature` rewrites the definition and all call sites.

Use grep/sed only for: string literals, comments, TODO markers, or patterns that are
intentionally not Python identifiers.

## Symbol Reference Notation

All bonsai tools that accept a `target` use one of two notations:

**Module path form** (preferred):
```
module.submodule:SymbolName
module.submodule:ClassName.method_name
```
Examples:
- `src.api.views:create_user`
- `src.models:User`
- `src.models:User.save`

**File path form** (also accepted):
```
path/to/file.py:SymbolName
```
Examples:
- `src/models.py:User`
- `src/api/views.py:create_user`

The colon separates the module (or file path) from the symbol name.
For methods, the dot separates the class name from the method name.

## Dry-Run Workflow for Mutating Tools

The mutating tools (`pyrename`, `pymove`, `pymovesymbol`, `pysignature`) all support
`dry_run=True`. Always follow this pattern:

1. Call the tool with `dry_run=True` — review the preview showing which files would be
   modified and what the edits look like.
2. Confirm the blast radius looks correct (number of files, changed lines).
3. Call the tool again with `dry_run=False` to apply.

Never apply a mutation without first running a dry-run review step.

## Structured `pysignature` Arguments

When calling `pysignature`, always use the dict form for `add`, `rename`, and `set_default`.
The string form is legacy and fragile.

**Adding a parameter:**
```python
pysignature("src.api:create_user", add=[{"name": "timeout", "type": "int", "default": "30"}], dry_run=True)
```

**Renaming a parameter:**
```python
pysignature("src.api:create_user", rename=[{"from": "user_id", "to": "uid"}], dry_run=True)
```

**Changing a default:**
```python
pysignature("src.api:create_user", set_default=[{"name": "retries", "value": "5", "type": "int"}], dry_run=True)
```

**Removing a parameter** (plain string — no ambiguity):
```python
pysignature("src.api:create_user", remove=["legacy_flag"], dry_run=True)
```

**Reordering** (list of names):
```python
pysignature("src.api:create_user", reorder=["name", "email", "role"], dry_run=True)
```

## AST Limitations and False Positives

Bonsai performs static AST analysis — it has **no type inference**.

### `pycallers` false positives
`pycallers` on `src.models:User.save` returns **all** `.save()` call sites in the project,
regardless of whether the receiver is actually a `User`. Any object with a `.save()` method
will appear in results. Review call sites manually to confirm class membership before treating
the full list as ground truth.

### `pyfindrefs` attribute matches
Refs with `ref_type="attribute"` may include false positives — the tool cannot determine
the receiver's type from AST alone. Refs with `ref_type` in `["definition", "import",
"base_class"]` are reliable. Review `"attribute"` and `"call"` results manually in codebases
with many same-named methods.

### `pyfindunused` dead code skip rules
Dead code detection skips: private symbols (leading `_`), framework-decorated functions
(`@staticmethod`, `@route`, `@fixture`, `@task`, etc.), symbols in `__all__`, and known
entry-point names (`main`, `handler`, `lambda_handler`, etc.). It also skips `migrations/`,
`tests/`, and `alembic/` directories entirely. A function that only appears inside a test
file may not be flagged even if it has no callers outside tests.

Use `dead_code=False, imports=True` or `dead_code=False, params=True` for file-scoped checks
that do not apply these exclusions.
