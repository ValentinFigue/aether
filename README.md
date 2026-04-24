# claude-pytools

AST-based Python refactoring tools packaged as a Claude Code MCP plugin.

## Tools

| Tool | What it does |
|------|-------------|
| `pyfindrefs` | Find all references to a symbol: definitions, imports, calls, decorators, base classes |
| `pycallers` | Find every call site of a function or method |
| `pyfindunused` | Detect dead functions/classes, unused parameters, and unused imports |
| `pymove` | Move/rename a Python file or package and rewrite all imports |
| `pymovesymbol` | Move a single function or class to a different module |
| `pyrename` | Scope-aware rename across the entire project |
| `pysignature` | Change a function's signature and update all call sites |

## Install

### Option A — from GitHub (no PyPI account needed)

```bash
pip install git+https://github.com/valentinfigue/claude-pytools
python -m claude_pytools --install
```

Restart Claude Code. All 7 tools are immediately available as `mcp__pytools__*`.

### Option B — zero-install with uvx (after PyPI publish)

```bash
uvx claude-pytools --install
```

## Usage in Claude Code

Once installed, Claude can call the tools directly — no slash commands or Bash permissions needed:

```
mcp__pytools__pyfindrefs("src.models:User")
mcp__pytools__pyrename("src.models:User", "Account", dry_run=True)
mcp__pytools__pysignature("src.api:create_user", add=["timeout int 30"], dry_run=True)
```

## Publish to PyPI

```bash
pip install hatch
hatch build
hatch publish
```

After publishing, `uvx claude-pytools --install` works for anyone with `uv` installed.
