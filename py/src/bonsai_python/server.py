"""FastMCP server exposing all bonsai refactoring tools as MCP endpoints."""

import contextlib
import io
import logging
from collections.abc import Callable
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from ._common import collect_python_files, find_project_root, load_config
from .pyfindrefs import Ref, find_refs
from .pyfindunused import UnusedResult, find_dead_code, find_unused_imports, find_unused_params
from .pygrep import GrepResult, grep
from .pymove import do_move
from .pymovesymbol import do_move_symbol
from .pyrename import do_rename
from .pysignature import SignatureChange, do_signature

logging.basicConfig(format="%(levelname)s: %(message)s")

mcp = FastMCP("pytools")


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _capture_output(fn: Callable, *args, **kwargs) -> str:
    """Call *fn* capturing stdout/stderr. Raises ``ValueError`` on tool failure.

    Used for mutation tools that print their own progress summaries. Safe for
    single-threaded asyncio; mutation tools should not run concurrently anyway
    since they modify the same files.
    """
    buf = io.StringIO()
    err = io.StringIO()
    result = None
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
        try:
            result = fn(*args, **kwargs)
        except SystemExit as e:
            if e.code not in (0, None):
                msg = err.getvalue().strip() or f"tool exited with code {e.code}"
                raise ValueError(msg) from None
    if result is False:
        msg = err.getvalue().strip() or "tool returned failure with no error message"
        raise ValueError(msg)
    out = buf.getvalue().strip()
    extra = err.getvalue().strip()
    return f"{out}\n{extra}".strip() if extra else out or "Done."


_REF_ORDER = ["definition", "import", "call", "decorator", "base_class", "name", "attribute"]


def _fmt_refs(refs: list[Ref]) -> str:
    """Format refs grouped by type (definition > import > call > ...)."""
    if not refs:
        return "No references found."
    by_type: dict[str, list[Ref]] = {}
    for ref in refs:
        by_type.setdefault(ref.ref_type, []).append(ref)
    lines: list[str] = []
    total = 0
    for ref_type in _REF_ORDER:
        group = by_type.get(ref_type, [])
        if not group:
            continue
        lines.append(f"\n{ref_type.upper()} ({len(group)})")
        for ref in sorted(group, key=lambda r: (r.filepath, r.line)):
            loc = f"{ref.filepath}:{ref.line}"
            lines.append(f"  {loc:<60}  {ref.snippet[:80]}")
            total += 1
    lines.append(f"\n{total} reference{'s' if total != 1 else ''} found.")
    return "\n".join(lines)


def _fmt_grep(results: list[GrepResult]) -> str:
    """Format grep results as filepath:line: text."""
    if not results:
        return "No matches found."
    lines = [f"{r.filepath}:{r.line}: {r.snippet}" for r in results]
    lines.append(f"\n{len(results)} match{'es' if len(results) != 1 else ''} found.")
    return "\n".join(lines)


def _fmt_unused(results: list[UnusedResult]) -> str:
    """Format unused-symbol results grouped by kind."""
    if not results:
        return "No unused symbols found."
    by_kind: dict[str, list[UnusedResult]] = {}
    for r in results:
        by_kind.setdefault(r.kind, []).append(r)
    kind_labels = {
        "dead_code": "DEAD CODE",
        "unused_param": "UNUSED PARAMS",
        "unused_import": "UNUSED IMPORTS",
    }
    lines: list[str] = []
    total = 0
    for kind in ("dead_code", "unused_param", "unused_import"):
        group = by_kind.get(kind, [])
        if not group:
            continue
        lines.append(f"\n{kind_labels[kind]} ({len(group)})")
        for r in sorted(group, key=lambda r: (r.filepath, r.line)):
            loc = f"{r.filepath}:{r.line}"
            detail = f"  [{r.detail}]" if r.detail else ""
            lines.append(f"  {loc:<60}  {r.name}{detail}")
            total += 1
    lines.append(f"\n{total} unused symbol{'s' if total != 1 else ''} found.")
    return "\n".join(lines)


# ─── Query tools (parallel-safe: no global state mutation) ────────────────────


@mcp.tool()
def pyfindrefs(target: str, project_root: str | None = None) -> str:
    """Find all usages of a Python class, function, method, or variable across the project.

    Use this instead of grep whenever you need to know where a symbol is imported, called,
    subclassed, decorated, or assigned. Returns results grouped by reference type:
    definitions, imports, calls, decorators, base classes, and plain name usages.

    Accepts 'module:Symbol', 'module:Class.method', OR a file-path variant
    'path/to/file.py:Symbol' (absolute or relative to the project root).

    Note: Refs with ref_type "attribute" may include false positives — AST analysis cannot
    determine the receiver's type. Refs with ref_type "definition", "import", and "base_class"
    are reliable. Review "attribute" and "call" results manually in codebases with many
    same-named methods.

    Args:
        target: E.g. 'src.models:User', 'src.models:User.save', or 'src/models.py:User'
        project_root: Absolute path to project root (auto-detected from cwd if omitted)
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    try:
        refs = find_refs(target, root)
    except SystemExit:
        return f"Error: invalid target {target!r} — expected 'module:Symbol' or 'module:Class.method'"
    return _fmt_refs(refs)


@mcp.tool()
def pycallers(target: str, project_root: str | None = None) -> str:
    """Find every call site of a Python function or method across the project.

    Use this when you want only the places where a function is *called* — not its
    definition or import lines. For all reference types (imports, base classes, decorators
    etc.) use pyfindrefs instead.

    Accepts 'module:function', 'module:Class.method', or 'path/to/file.py:function'.

    Note: pycallers uses AST analysis without type inference. It returns ALL `.method_name()`
    call sites in the project, regardless of which class the receiver belongs to. For example,
    `pycallers("src.models:User.save")` will match any `obj.save()` call, not only those where
    `obj` is a `User`. Review results manually to confirm class membership.

    Args:
        target: E.g. 'src.api.views:create_user' or 'src/api/views.py:create_user'
        project_root: Absolute path to project root (auto-detected from cwd if omitted)
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    try:
        refs = find_refs(target, root)
    except SystemExit:
        return f"Error: invalid target {target!r} — expected 'module:function' or 'module:Class.method'"
    calls = [r for r in refs if r.ref_type == "call"]
    if not calls:
        return "No call sites found."
    lines = [f"  {r.filepath}:{r.line:<4}  {r.snippet[:80]}" for r in sorted(calls, key=lambda r: (r.filepath, r.line))]
    lines.append(f"\n{len(calls)} call site{'s' if len(calls) != 1 else ''} found.")
    return "\n".join(lines)


@mcp.tool()
def pyfindunused(
    project_root: str | None = None,
    dead_code: bool = True,
    params: bool = True,
    imports: bool = True,
    path: str | None = None,
) -> str:
    """Find unused Python symbols: dead top-level functions/classes, unused parameters, unused imports.

    Note: Dead code detection skips private symbols (leading `_`), framework-decorated functions
    (@route, @fixture, @task, etc.), symbols listed in `__all__`, and known entry-point names
    (main, handler, lambda_handler, etc.). It also skips migrations/, tests/, and alembic/
    directories entirely. Use `dead_code=False` with `imports=True` or `params=True` for
    file-scoped checks that do not have these exclusions.

    Args:
        project_root: Absolute path to project root (auto-detected from cwd if omitted)
        dead_code: Find top-level functions/classes with no cross-module references
        params: Find function parameters never used in the body
        imports: Find imports never referenced in their file
        path: Restrict analysis to a specific file or directory (accepts files and directories)
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    scan_root = Path(path) if path else root
    all_files = collect_python_files(scan_root)
    config = load_config(root)
    results: list[UnusedResult] = []
    if dead_code:
        results += find_dead_code(all_files, root, config)
    if params:
        results += find_unused_params(all_files, root)
    if imports:
        results += find_unused_imports(all_files, root)
    return _fmt_unused(results)


@mcp.tool()
def pygrep(pattern: str, project_root: str | None = None, case_sensitive: bool = True) -> str:
    """Search for a text pattern across all Python files in the project.

    Use this for finding string literals, comments, or arbitrary text patterns.
    For finding usages of a specific class or function by name, prefer pyfindrefs
    (AST-based, more precise — won't match comments or unrelated identifiers).

    The pattern is a Python regular expression. Results include file path, line
    number, and the matching line.

    Args:
        pattern: Regular expression to search for. E.g. 'class Word' or 'TODO'
        project_root: Absolute path to project root (auto-detected from cwd if omitted)
        case_sensitive: Set to False for case-insensitive matching
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    try:
        results = grep(pattern, root, case_sensitive=case_sensitive)
    except SystemExit:
        return f"Error: invalid regex pattern {pattern!r}"
    return _fmt_grep(results)


# ─── Mutation tools (stdout-captured; should not run concurrently) ────────────


@mcp.tool()
def pymove(
    source: str,
    destination: str,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Move or rename a Python file/package and rewrite all import references across the project.

    For moving a single function or class between files, use pymovesymbol instead.

    Args:
        source: Path to the Python file or package directory to move (relative or absolute)
        destination: New location — a file path or a directory
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    src = Path(source)
    dst = Path(destination)
    root = Path(project_root).resolve() if project_root else None
    return _capture_output(do_move, src, dst, root, dry_run)


@mcp.tool()
def pymovesymbol(
    target: str,
    dest_module: str,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Move a single Python function or class to a different module, rewriting all imports.

    For moving an entire file or package, use pymove instead.

    Args:
        target: Symbol in 'module:Symbol' format. E.g. 'src.utils.helpers:format_date'
        dest_module: Destination module in dotted notation. E.g. 'src.utils.dates'
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    return _capture_output(do_move_symbol, target, dest_module, root, dry_run)


@mcp.tool()
def pyrename(
    target: str,
    new_name: str,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Scope-aware rename of a Python symbol (function, class, method, variable, constant) across the entire project.

    Does not rename unrelated local variables that happen to share the name —
    only the symbol at the specified module path.

    Args:
        target: Symbol in 'module:Symbol' or 'module:Class.method' format. E.g. 'src.models:User'
        new_name: The new name for the symbol
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    return _capture_output(do_rename, target, new_name, root, dry_run)


@mcp.tool()
def pysignature(
    target: str,
    add: list[dict[str, str] | str] | None = None,
    remove: list[str] | None = None,
    rename: list[dict[str, str] | str] | None = None,
    reorder: list[str] | None = None,
    set_default: list[dict[str, str] | str] | None = None,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Change a Python function's signature and update all call sites across the project.

    Args:
        target: Function in 'module:function' or 'module:Class.method' format
        add: Parameters to add. Preferred dict form: [{"name": "timeout", "type": "int", "default": "30"}].
             "type" and "default" are optional. Legacy string form also accepted: "timeout int 30".
        remove: Parameter names to remove. E.g. ['legacy_flag']
        rename: Parameters to rename. Preferred dict form: [{"from": "old_name", "to": "new_name"}].
                Legacy string form also accepted: "old_name new_name".
        reorder: New parameter order as a list of names. E.g. ['name', 'email', 'role']
        set_default: Change defaults. Preferred dict form: [{"name": "retries", "value": "5", "type": "int"}].
                     "type" is optional. Legacy string form also accepted: "retries 5 int".
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    root = Path(project_root) if project_root else find_project_root(Path.cwd())
    changes: list[SignatureChange] = []
    for item in add or []:
        if isinstance(item, dict):
            changes.append(
                SignatureChange(
                    action="add",
                    param_name=item["name"],
                    new_type=item.get("type"),
                    new_default=item.get("default"),
                )
            )
        else:
            parts = item.split()
            changes.append(
                SignatureChange(
                    action="add",
                    param_name=parts[0],
                    new_type=parts[1] if len(parts) > 1 else None,
                    new_default=parts[2] if len(parts) > 2 else None,
                )
            )
    for name in remove or []:
        changes.append(SignatureChange(action="remove", param_name=name))
    for pair in rename or []:
        if isinstance(pair, dict):
            changes.append(SignatureChange(action="rename", param_name=pair["from"], new_name=pair["to"]))
        else:
            parts = pair.split()
            changes.append(SignatureChange(action="rename", param_name=parts[0], new_name=parts[1]))
    if reorder:
        changes.append(SignatureChange(action="reorder", param_name="", new_order=reorder))
    for item in set_default or []:
        if isinstance(item, dict):
            changes.append(
                SignatureChange(
                    action="set_default",
                    param_name=item["name"],
                    new_default=str(item["value"]),
                    new_type=item.get("type"),
                )
            )
        else:
            parts = item.split()
            changes.append(
                SignatureChange(
                    action="set_default",
                    param_name=parts[0],
                    new_default=parts[1],
                    new_type=parts[2] if len(parts) > 2 else None,
                )
            )
    return _capture_output(do_signature, target, changes, root, dry_run)
