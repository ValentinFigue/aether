# bonsai

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/ValentinFigue/bonsai/actions/workflows/ci.yml/badge.svg)](https://github.com/ValentinFigue/bonsai/actions/workflows/ci.yml)

Static-analysis refactoring tools for Claude Code — Python (AST) and TypeScript (compiler API).

> **Status: early alpha.** The tools work but the project is new — expect rough edges. Feedback and bug reports welcome.

## What's inside

Two MCP servers, one repo:

| Server | Language | Key advantage |
|---|---|---|
| `bonsai-py` | Python 3.10+ | AST-based, no type inference needed, zero extra deps |
| `bonsai-ts` | TypeScript / JavaScript | TypeScript compiler API — fully type-aware, no false positives from same-named methods |

## Repository layout

```
bonsai/
├── py/                        # Python MCP server
│   ├── src/bonsai_python/     # source modules
│   ├── tests/                 # pytest suite + fixtures
│   └── pyproject.toml         # Python packaging (hatchling)
├── ts/                        # TypeScript MCP server
│   ├── src/                   # TypeScript source modules
│   └── tests/                 # vitest suite + fixtures
├── scripts/                   # dev helper scripts
├── skills/                    # Claude Code skill definitions
├── .claude-plugin/            # plugin manifest, hooks, marketplace config
└── .mcp.json                  # registers both MCP servers for local dev
```

---

## Developing locally

### 1. Clone and build

```bash
git clone https://github.com/ValentinFigue/bonsai
cd bonsai
bash scripts/setup.sh
```

`setup.sh` installs Python deps via uv (into `py/.venv`), builds the TypeScript server, and registers the enforcement hook at user scope in `~/.claude.json`. `sed`, `awk`, `grep`, and `find` on `.py`/`.ts`/`.tsx` files will be blocked everywhere and redirected to the appropriate bonsai tool. Restart Claude Code to pick up the hook.

### 2. Connect Claude Code to your local build

The `.mcp.json` at the repo root registers both servers from your local build.
Open the `bonsai/` directory in Claude Code — both servers connect automatically.

Verify in Claude Code Settings → MCP: both `bonsai-py` and `bonsai-ts` should show **✓ Connected**.

If a server fails to connect, test it manually:

```bash
uv run --directory py bonsai-py  # Python server
node ts/dist/server.js            # TypeScript server
```

Then restart Claude Code.

### 3. Run the tests

```bash
bash scripts/test.sh
```

Or per-language:

```bash
# Python only
cd py && uv run pytest tests/ -v

# TypeScript only
cd ts && npm test
```

### 4. Iterating

- **Python:** edit `py/src/bonsai_python/`, re-run pytest. No server restart needed.
- **TypeScript:** edit `ts/src/`, run `cd ts && npm run build`. Restart Claude Code to pick up the new build.

### 5. Clean up local dev

To remove all local dev artifacts (virtual env, TS build output, and the local hook config):

```bash
bash scripts/clean.sh
```

To also remove globally-registered MCP servers pointing to your local build:

```bash
claude mcp remove bonsai-py --scope user
claude mcp remove bonsai-ts --scope user
```

### 6. Use the tools in other projects

The `.mcp.json` only activates when you open the `bonsai/` directory. To use your local build in any project, register it globally once:

```bash
claude mcp add bonsai-py --scope user -- uv run --directory "$(pwd)/py" bonsai-py
claude mcp add bonsai-ts --scope user -- node "$(pwd)/ts/dist/server.js"
```

When you publish and want to switch to the released packages:

```bash
claude mcp add bonsai-py --scope user -- uvx bonsai-py
claude mcp add bonsai-ts --scope user -- npx --yes bonsai-ts
```

---

## Install

### Option A — Manual install (recommended for now)

**Python server:**
```bash
# With uv (recommended):
claude mcp add bonsai-py --scope user -- uvx bonsai-py

# With pip:
pip install bonsai-py
claude mcp add bonsai-py --scope user -- python -m bonsai_python
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
- `/bonsai:setup` registers both MCP servers (`bonsai-py` and `bonsai-ts`) in `~/.claude.json`.

Then restart Claude Code.

---

## Publishing

> What needs to happen before end-users can install bonsai without cloning the repo.

### Current blockers

| Blocker | Status |
|---|---|
| `bonsai-py` not yet published to PyPI | ❌ |
| `bonsai-ts` not yet published to npm | ❌ |

### Step 1 — Publish the Python package to PyPI

```bash
cd py
uv build
uv publish   # set PYPI_TOKEN env var or pass --token
```

Verify: `uvx bonsai-py --help`

### Step 2 — Publish the TypeScript package to npm

```bash
cd ts
npm run build
npm publish --access public   # requires npm login
```

Verify: `npx --yes bonsai-ts --help`

### Step 3 — Switch `.mcp.json` to published packages

Once both packages are live, update `.mcp.json` to the published form:

```json
{
  "mcpServers": {
    "bonsai-py": {
      "command": "uvx",
      "args": ["bonsai-py"]
    },
    "bonsai-ts": {
      "command": "npx",
      "args": ["--yes", "bonsai-ts@latest"]
    }
  }
}
```

At that point the plugin install flow in `## Install → Option B` works end-to-end.

---

## Python tools (`bonsai-py`)

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
claude mcp add bonsai-py --scope user -- uvx bonsai-py
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

## License

MIT — see [LICENSE](LICENSE).
