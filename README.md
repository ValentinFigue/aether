# bonsai

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/ValentinFigue/bonsai/actions/workflows/ci.yml/badge.svg)](https://github.com/ValentinFigue/bonsai/actions/workflows/ci.yml)

AST-based Python refactoring tools for Claude Code.

> **Status: early alpha.** The tools work but the project is new — expect rough edges. Feedback and bug reports are welcome. Find symbol references, detect dead code, rename identifiers, move files and symbols, and update function signatures — driven by static analysis, with no language server or type-checking daemon required.

## Install

### Option A — Claude Code plugin system (recommended)

Run these slash commands inside Claude Code:

```
/plugin marketplace add ValentinFigue/bonsai
/plugin install bonsai
/bonsai:setup
```

- The first line adds this repo as a plugin marketplace (one-time, saved globally).
- The second installs the plugin (skills auto-load on next restart).
- `/bonsai:setup` registers the MCP server in `~/.claude.json` — this is the step
  that makes the 8 tools available. It survives plugin updates because it writes
  outside the plugin directory.

**Restart Claude Code** after running `/bonsai:setup`.

### Option B — Direct URL install

No marketplace setup needed:

```
/plugin install https://github.com/ValentinFigue/bonsai
```

Then run `/bonsai:setup` and restart.

### Option C — Manual (no plugin system)

Registers only the MCP server, without skills or plugin management:

```bash
# With uv (recommended — no global install needed):
claude mcp add bonsai-refactor --scope user -- uvx bonsai-refactor

# With pip:
pip install bonsai-refactor
claude mcp add bonsai-refactor --scope user -- python -m bonsai_refactor
```

**Restart Claude Code** after running. Verify it worked:

```bash
python -m bonsai_refactor --verify
```

> Option C skips the plugin skills layer. Claude will still use the MCP tools when
> you explicitly ask, but won't auto-invoke them for refactoring tasks the way the
> skills layer enables.

## How it works

`bonsai-refactor` runs as an MCP server that Claude Code connects to over stdio. When you describe a refactoring in natural language, Claude picks the right tool, calls it with the correct arguments, and shows you the result. No slash commands, no Bash permissions needed for the tools.

The tools use Python's `ast` module to parse source files directly — the only runtime dependency is `mcp[cli]`. They work on any Python 3.10+ project regardless of framework.

## Tools

| Tool | What it does |
|------|-------------|
| `pyfindrefs` | Find all usages of a class, function, or variable: definitions, imports, calls, decorators, base classes |
| `pycallers` | Find every call site of a function or method (call-type only; for all reference types use `pyfindrefs`) |
| `pyfindunused` | Detect dead top-level functions/classes, unused parameters, and unused imports |
| `pygrep` | Search for a text pattern (regex) across all Python files |
| `pymove` | Move or rename a Python file/package and rewrite all imports |
| `pymovesymbol` | Move a single function or class to a different module |
| `pyrename` | Scope-aware rename across the entire project |
| `pysignature` | Change a function's signature and update all call sites |

## Usage examples

Say these things to Claude Code — no special syntax required:

**Find references**
> "Where is `User` used across the project?"
> "Find all usages of the `Word` class defined in `src/geometry/text_box.py`."

Claude calls: `pyfindrefs("src.models:User")` or `pyfindrefs("src/geometry/text_box.py:Word")`

Both formats work — you can pass a dotted module name or a file path.

**Find callers only**
> "Who calls `send_email`?"
> "What calls `PaymentService.charge`?"

Claude calls: `pycallers("src.services.email:send_email")`

**Find dead code**
> "Find unused functions in this project."
> "What imports are never used in `utils.py`?"

Claude calls: `pyfindunused(dead_code=True, imports=True)`

**Move a file**
> "Move `src/utils/helpers.py` to `src/core/helpers.py` and fix all imports."

Claude calls: `pymove("src/utils/helpers.py", "src/core/helpers.py", dry_run=True)`, shows the diff, then applies on confirmation.

**Move a symbol**
> "Move the `format_date` function from `src.utils` to `src.utils.dates`."

Claude calls: `pymovesymbol("src.utils:format_date", "src.utils.dates")`

**Rename**
> "Rename `User` to `Account` everywhere."
> "Rename the `save` method on `User` to `persist`."

Claude calls: `pyrename("src.models:User", "Account", dry_run=True)`

**Change a signature**
> "Add a `timeout: int = 30` parameter to `create_user`."
> "Remove the `legacy_flag` parameter from `process_payment` and update all call sites."

Claude calls: `pysignature("src.api:create_user", add=[{"name": "timeout", "type": "int", "default": "30"}], dry_run=True)`

**Search for text patterns**
> "Find all TODO comments in the project."
> "Where does the string 'deprecated' appear?"

Claude calls: `pygrep("TODO")` or `pygrep("deprecated", case_sensitive=False)`

All mutating tools (`pymove`, `pymovesymbol`, `pyrename`, `pysignature`) support `dry_run=True`. Claude uses dry-run by default and asks for confirmation before applying changes.

## Troubleshooting

**Tools don't appear in Claude Code after install**

Run `python -m bonsai_refactor --verify` to check the configuration, then restart Claude Code. If that doesn't help, re-run `claude mcp add bonsai-refactor --scope user -- uvx bonsai-refactor` and restart again.

**`uvx` not found**

Install uv first, then retry `/bonsai:setup`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Or use the pip form: `claude mcp add bonsai-refactor --scope user -- python -m bonsai_refactor`.

**Wrong Python / virtual environment**

If using `claude mcp add ... -- python -m bonsai_refactor`, make sure it's the Python Claude Code will invoke. The `uvx bonsai-refactor` form is usually safer since uv manages the environment automatically.

**`pyfindrefs` returns "No references found" for a valid symbol**

Pass the `project_root` explicitly if your project is not at the current working directory:
```
pyfindrefs("src.models:User", project_root="/abs/path/to/project")
```

## Limitations

- **No type inference.** Method attribution is best-effort: `pycallers("src.models:User.save")` finds all `.save()` calls, not just those on `User` instances. It may include false positives from other classes with a `save` method.
- **No runtime analysis.** Dynamic patterns like `getattr(obj, method_name)()` are invisible to AST analysis.
- **Public symbols only for dead-code detection.** `pyfindunused --dead-code` skips private symbols (names starting with `_`), framework-decorated functions, and test files — but may still produce false positives if symbols are referenced dynamically.
- **Single project tree.** All tools operate on a project rooted at `pyproject.toml` / `.git`. For monorepos, pass `project_root` explicitly.

## Configuration

Add a `[tool.bonsai]` section to your project's `pyproject.toml` to customise dead-code detection.

Each setting has two variants:

- **`extra_*`** — merged with the built-in defaults (additive)
- **base key** — replaces the built-in defaults entirely

```toml
[tool.bonsai]
# Extend the built-in decorator list (get, post, route, task, fixture, classmethod, …)
dead_code_extra_decorators = ["api_view", "login_required", "permission_classes"]

# Replace the built-in decorator list entirely
# dead_code_decorators = ["route", "task"]

# Extend the built-in entry-point list (main, handler, lambda_handler, setUp, upgrade, …)
dead_code_extra_entry_points = ["run", "execute", "on_ready"]

# Replace the built-in entry-point list entirely
# dead_code_entry_points = ["main", "handler"]

# Extend the built-in skip-dirs list (migrations, tests, test, alembic)
dead_code_extra_skip_dirs = ["fixtures", "scripts"]

# Replace the built-in skip-dirs list entirely (e.g. to scan test files)
# dead_code_skip_dirs = ["migrations", "alembic"]
```

## Development

```bash
git clone https://github.com/valentinfigue/bonsai
cd bonsai
pip install -e .
```

Run the MCP server directly:

```bash
python -m bonsai_refactor  # start the stdio MCP server (used by Claude Code via stdio)
```

Register in dev (writes to `~/.claude.json`):

```bash
claude mcp add bonsai-refactor --scope user -- python -m bonsai_refactor
```

## Roadmap

### TypeScript / JavaScript support

The current toolset is Python-only. A TypeScript/JS equivalent is planned, addressing the most common mixed-codebase gap:

| Planned tool | Equivalent | Description |
|---|---|---|
| `tsfindrefs` | `pyfindrefs` | Find all usages of a symbol across `.ts`/`.tsx`/`.js`/`.jsx` files |
| `tsrename` | `pyrename` | Scope-aware rename using the TypeScript compiler API |
| `tsmove` | `pymove` | Move/rename a file or module and rewrite all imports |
| `tsmovesymbol` | `pymovesymbol` | Move a single function or class to a different module |
| `tssignature` | `pysignature` | Change a function signature and update all call sites |

**Implementation approach:**
- Parse using the [TypeScript compiler API](https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API) (via `ts-morph` for a higher-level wrapper) — gives full type-aware AST with symbol resolution, eliminating the false-positive problem that affects the Python tools.
- Ship as a second MCP server (`bonsai-ts`) that Claude Code connects to alongside `bonsai`, or fold into the same server with a `language` parameter.
- Node.js runtime required (no Python dependency for the TS tools).

The type-aware AST is the key advantage over the Python implementation: `ts-morph` can resolve that `.save()` on a `User` is distinct from `.save()` on a `Document`, which the Python AST cannot.

Contributions welcome — see [Issues](https://github.com/ValentinFigue/bonsai/issues) for the tracking issue.

## License

MIT — see [LICENSE](LICENSE).
