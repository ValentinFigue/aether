# bonsai

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/ValentinFigue/bonsai/actions/workflows/ci.yml/badge.svg)](https://github.com/ValentinFigue/bonsai/actions/workflows/ci.yml)

Static-analysis refactoring tools for Claude Code — Python (AST) and TypeScript (compiler API).

> **Status: early alpha.** The tools work but the project is new — expect rough edges. Feedback and bug reports welcome.

## What's inside

Two MCP servers, one repo:

| Server | Language | Key advantage |
|---|---|---|
| `bonsai-python` | Python 3.10+ | AST-based, no type inference needed, zero extra deps |
| `bonsai-ts` | TypeScript / JavaScript | TypeScript compiler API — fully type-aware, no false positives from same-named methods |

## Repository layout

```
bonsai/
├── py/                        # Python MCP server
│   ├── src/bonsai_python/     # source modules
│   └── tests/                 # pytest suite + fixtures
├── ts/                        # TypeScript MCP server
│   ├── src/                   # TypeScript source modules
│   └── tests/                 # vitest suite + fixtures
├── skills/                    # Claude Code skill definitions
├── .claude-plugin/            # plugin manifest, hooks, marketplace config
├── .mcp.json                  # registers both MCP servers for local dev
└── pyproject.toml             # Python packaging (hatchling)
```

---

## Install

### Option A — Manual install (recommended for now)

**Python server:**
```bash
# With uv (recommended):
claude mcp add bonsai-python --scope user -- uvx bonsai-python

# With pip:
pip install bonsai-python
claude mcp add bonsai-python --scope user -- python -m bonsai_python
```

**TypeScript server:**
```bash
claude mcp add bonsai-ts --scope user -- npx --yes bonsai-ts
```

Verify Python setup:
```bash
python -m bonsai_python --verify
```

> This option skips the plugin skills layer. Claude will still invoke the tools when asked,
> but won't auto-select them for refactoring tasks the way the skills layer enables.

### Option B — Claude Code plugin system

```
/plugin marketplace add ValentinFigue/bonsai
/plugin install bonsai@ValentinFigue/bonsai
/bonsai:setup
```

- Line 1 registers this repo as a plugin marketplace (one-time).
- Line 2 installs the `bonsai` plugin from that marketplace — the `@ValentinFigue/bonsai` suffix tells Claude Code which marketplace to resolve the plugin against.
- `/bonsai:setup` registers both MCP servers (`bonsai-python` and `bonsai-ts`) in `~/.claude.json`.

Then restart Claude Code.

---

## Python tools (`bonsai-python`)

| Tool | What it does |
|---|---|
| `pyfindrefs` | Find all usages of a class, function, or variable: definitions, imports, calls, decorators, base classes |
| `pycallers` | Find every call site of a function or method (call-type only) |
| `pyfindunused` | Detect dead top-level functions/classes, unused parameters, and unused imports |
| `pygrep` | Search for a text pattern (regex) across all Python files |
| `pymove` | Move or rename a Python file/package and rewrite all imports |
| `pymovesymbol` | Move a single function or class to a different module |
| `pyrename` | Scope-aware rename across the entire project |
| `pysignature` | Change a function's signature and update all call sites |

### Symbol notation

All Python tools use one of two forms for `target`:

```
module.submodule:SymbolName           # dotted module path
module.submodule:ClassName.method     # method on a class
path/to/file.py:SymbolName            # file path (also accepted)
```

Examples: `src.models:User`  `src.models:User.save`  `src/api/views.py:create_user`

### Python usage examples

**Find references**
> "Where is `User` used across the project?"

Claude calls: `pyfindrefs("src.models:User")`

**Find callers**
> "What calls `PaymentService.charge`?"

Claude calls: `pycallers("src.services:PaymentService.charge")`

**Find dead code**
> "Find unused functions."  "What imports are never used in `utils.py`?"

Claude calls: `pyfindunused(dead_code=True, imports=True)`

**Move a file**
> "Move `src/utils/helpers.py` to `src/core/helpers.py` and fix all imports."

Claude calls: `pymove("src/utils/helpers.py", "src/core/helpers.py", dry_run=True)`, shows the diff, applies on confirmation.

**Rename**
> "Rename `User` to `Account` everywhere."

Claude calls: `pyrename("src.models:User", "Account", dry_run=True)`

**Change a signature**
> "Add a `timeout: int = 30` parameter to `create_user`."

Claude calls: `pysignature("src.api:create_user", add=[{"name": "timeout", "type": "int", "default": "30"}], dry_run=True)`

All mutating tools support `dry_run=True`. Claude uses dry-run by default and asks for confirmation.

### Python limitations

- **No type inference.** Method attribution is best-effort: `pycallers("src.models:User.save")` finds all `.save()` calls, including those on other classes. Use the TypeScript server for type-accurate method resolution.
- **No runtime analysis.** Dynamic patterns like `getattr(obj, method)()` are invisible to AST analysis.
- **Public symbols only** for dead-code detection. `pyfindunused` skips private symbols, framework-decorated functions, and test files.
- **Single project tree.** All tools operate on a project rooted at `pyproject.toml` / `.git`. Pass `project_root` explicitly for monorepos.

---

## TypeScript tools (`bonsai-ts`)

| Tool | Python equivalent | Key capability |
|---|---|---|
| `tsfindrefs` | `pyfindrefs` | Type-aware reference finder — no false positives from same-named methods |
| `tsrename` | `pyrename` | Language Service rename — rewrites all imports, calls, type annotations in one pass |
| `tsmove` | `pymove` | Move file/directory and rewrite all import paths project-wide |
| `tsmovesymbol` | `pymovesymbol` | Move a single function/class; adds backward-compat re-export |
| `tssignature` | `pysignature` | Change function signature and update all call sites |

### Symbol notation

TypeScript tools use path-style notation (maps directly to file paths):

```
path/to/module:Symbol           # top-level symbol (no extension)
path/to/module:Class.method     # method on a class
```

Examples: `src/models/user:User`  `src/models/user:User.save`  `src/services:createUser`

File extensions are stripped if provided: `src/models/user.ts:User` also works.

### TypeScript usage examples

**Find references (type-aware)**
> "Where is `User.save` called?"

Claude calls: `tsfindrefs("src/models/user:User.save")`

Unlike `pyfindrefs`, this correctly distinguishes `User.save` from `Document.save` — it only returns call sites where the receiver is actually a `User`.

**Rename**
> "Rename the `save` method on `User` to `persist` everywhere."

Claude calls: `tsrename("src/models/user:User.save", "persist", dry_run=true)`

**Move a file**
> "Move `src/utils.ts` to `src/helpers/utils.ts` and fix all imports."

Claude calls: `tsmove("src/utils.ts", "src/helpers/utils.ts", dry_run=true)`

**Move a symbol**
> "Move the `formatDate` helper from `src/utils` to `src/lib/dates`."

Claude calls: `tsmovesymbol("src/utils:formatDate", "src/lib/dates", dry_run=true)`

A backward-compatible re-export is added to the original file — existing imports continue to work.

**Change a signature**
> "Add an optional `timeout: number = 30` to `createUser`."

Claude calls: `tssignature("src/services:createUser", add=[{"name": "timeout", "type": "number", "default": "30"}], dry_run=true)`

### TypeScript limitations

- **Requires `tsconfig.json`** at the project root for full type resolution. Without it, the tools fall back to a glob-based project (reference finding works but loses type accuracy).
- **Dynamic `require()` strings** are not rewritten by `tsmove`.
- **`.d.ts`-less packages**: symbols from third-party packages without type declarations may be missed by reference finding.
- **TypeScript has no keyword arguments**: `tssignature` reorder rewrites positional arguments at call sites (not named arguments). Combined remove + reorder operations apply reorder on post-removal argument positions.

---

## Dry-run workflow (both servers)

All mutating tools accept `dry_run=true`. Always follow this pattern:

1. Call with `dry_run=true` — review the preview diff.
2. Confirm the blast radius (number of files, changed lines).
3. Call again with `dry_run=false` (or `false` by default) to apply.

Claude uses dry-run by default for all mutating operations.

---

## Troubleshooting

**Tools don't appear after install**

Run `python -m bonsai_python --verify`, then restart Claude Code. If that doesn't help:
```bash
claude mcp add bonsai-python --scope user -- uvx bonsai-python
claude mcp add bonsai-ts --scope user -- npx --yes bonsai-ts
```
Then restart.

**`uvx` not found**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```
Then retry `/bonsai:setup`.

**`pyfindrefs` / `tsfindrefs` returns "No references found" for a valid symbol**

Pass `project_root` explicitly if your project is not at the current working directory:
```
pyfindrefs("src.models:User", project_root="/abs/path/to/project")
tsfindrefs("src/models/user:User", project_root="/abs/path/to/project")
```

**`tsfindrefs` gives wrong results / misses references**

Confirm your project has a `tsconfig.json` at the root. Without it, bonsai-ts falls back to a non-type-aware mode and may miss or misclassify references.

---

## Configuration (Python)

Add a `[tool.bonsai]` section to `pyproject.toml` to customise dead-code detection:

```toml
[tool.bonsai]
# Extend the built-in decorator exempt list (get, post, route, task, fixture, …)
dead_code_extra_decorators = ["api_view", "login_required"]

# Extend the built-in entry-point list (main, handler, lambda_handler, …)
dead_code_extra_entry_points = ["run", "execute", "on_ready"]

# Extend the built-in skip-dirs list (migrations, tests, alembic)
dead_code_extra_skip_dirs = ["fixtures", "scripts"]
```

Each setting has an `extra_*` variant (merged with defaults) and a base variant (replaces defaults entirely).

---

## Development

```bash
git clone https://github.com/valentinfigue/bonsai
cd bonsai

# Python
pip install -e ".[dev]"
pytest py/tests/ -v

# TypeScript
cd ts && npm install && npm run build && npm test
```

**Run the MCP servers locally:**

```bash
python -m bonsai_python          # Python MCP server (stdio)
node ts/dist/server.js           # TypeScript MCP server (stdio)
```

**Register local dev versions:**

```bash
claude mcp add bonsai-python --scope user -- python -m bonsai_python
claude mcp add bonsai-ts --scope user -- node /path/to/bonsai/ts/dist/server.js
```

Or point Claude Code at `.mcp.json` in the repo root (already configured for both servers — use `npx --yes` for the published versions or update to `node ts/dist/server.js` for local builds).

---

## License

MIT — see [LICENSE](LICENSE).
