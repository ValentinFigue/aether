"""FastMCP server exposing all bonsai refactoring tools as MCP endpoints."""

import contextlib
import io
import sys
from collections.abc import Callable

from mcp.server.fastmcp import FastMCP

from .pycallers import main as _pycallers_main
from .pyfindrefs import main as _pyfindrefs_main
from .pyfindunused import main as _pyfindunused_main
from .pygrep import main as _pygrep_main
from .pymove import main as _pymove_main
from .pymovesymbol import main as _pymovesymbol_main
from .pyrename import main as _pyrename_main
from .pysignature import main as _pysignature_main

mcp = FastMCP("pytools")


def _run(main_fn: Callable[[], None], argv: list[str]) -> str:
    """Invoke *main_fn* with *argv* and return its combined stdout/stderr output.

    Captures stdout and stderr via ``contextlib.redirect_*``, temporarily
    replaces ``sys.argv``, and suppresses ``SystemExit`` so CLI tools can be
    called safely from within the MCP server process.

    Args:
        main_fn: A CLI ``main()`` function that reads ``sys.argv``.
        argv: Argument vector to set (``argv[0]`` is the program name).

    Returns:
        Stripped combined output string, or ``"Done."`` when the tool produced
        no output.
    """
    buf = io.StringIO()
    err = io.StringIO()
    old_argv = sys.argv
    sys.argv = argv
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
            try:
                main_fn()
            except SystemExit:
                pass
    finally:
        sys.argv = old_argv
    out = buf.getvalue().rstrip()
    error_out = err.getvalue().rstrip()
    if error_out:
        return f"{out}\n{error_out}".strip()
    return out or "Done."


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
    argv = ["pyfindrefs", target]
    if project_root:
        argv += ["--project-root", project_root]
    return _run(_pyfindrefs_main, argv)


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
    argv = ["pycallers", target]
    if project_root:
        argv += ["--project-root", project_root]
    return _run(_pycallers_main, argv)


@mcp.tool()
def pyfindunused(
    project_root: str | None = None,
    dead_code: bool = True,
    params: bool = True,
    imports: bool = True,
    file_path: str | None = None,
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
        file_path: Restrict --params or --imports analysis to a specific file or directory
    """
    argv = ["pyfindunused"]
    if dead_code:
        argv.append("--dead-code")
    if params:
        argv.append("--params")
    if imports:
        argv.append("--imports")
    if project_root:
        argv += ["--project-root", project_root]
    if file_path:
        argv.append(file_path)
    return _run(_pyfindunused_main, argv)


@mcp.tool()
def pymove(
    source: str,
    destination: str,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Move or rename a Python file/package and rewrite all import references across the project. For moving a single function or class between files, use pymovesymbol instead.

    Args:
        source: Path to the Python file or package directory to move (relative or absolute)
        destination: New location — a file path or a directory
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    argv = ["pymove", source, destination]
    if project_root:
        argv += ["--project-root", project_root]
    if dry_run:
        argv.append("--dry-run")
    return _run(_pymove_main, argv)


@mcp.tool()
def pymovesymbol(
    target: str,
    dest_module: str,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Move a single Python function or class to a different module, rewriting all imports. For moving an entire file or package, use pymove instead.

    Args:
        target: Symbol in 'module:Symbol' format. E.g. 'src.utils.helpers:format_date'
        dest_module: Destination module in dotted notation. E.g. 'src.utils.dates'
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    argv = ["pymovesymbol", target, dest_module]
    if project_root:
        argv += ["--project-root", project_root]
    if dry_run:
        argv.append("--dry-run")
    return _run(_pymovesymbol_main, argv)


@mcp.tool()
def pyrename(
    target: str,
    new_name: str,
    project_root: str | None = None,
    dry_run: bool = False,
) -> str:
    """Scope-aware rename of a Python symbol (function, class, method, variable, constant) across the entire project. Does not rename unrelated local variables that happen to share the name — only the symbol at the specified module path.

    Args:
        target: Symbol in 'module:Symbol' or 'module:Class.method' format. E.g. 'src.models:User'
        new_name: The new name for the symbol
        project_root: Absolute path to project root (auto-detected if omitted)
        dry_run: Preview changes without modifying any files
    """
    argv = ["pyrename", target, new_name]
    if project_root:
        argv += ["--project-root", project_root]
    if dry_run:
        argv.append("--dry-run")
    return _run(_pyrename_main, argv)


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
    argv = ["pysignature", target]
    for item in add or []:
        if isinstance(item, dict):
            parts = [item["name"]]
            if "type" in item:
                parts.append(item["type"])
            if "default" in item:
                parts.append(str(item["default"]))
        else:
            parts = item.split()
        argv += ["--add"] + parts
    for name in remove or []:
        argv += ["--remove", name]
    for pair in rename or []:
        if isinstance(pair, dict):
            argv += ["--rename", pair["from"], pair["to"]]
        else:
            argv += ["--rename"] + pair.split()
    if reorder:
        argv += ["--reorder"] + reorder
    for item in set_default or []:
        if isinstance(item, dict):
            parts = [item["name"], str(item["value"])]
            if "type" in item:
                parts.append(item["type"])
        else:
            parts = item.split()
        argv += ["--set-default"] + parts
    if project_root:
        argv += ["--project-root", project_root]
    if dry_run:
        argv.append("--dry-run")
    return _run(_pysignature_main, argv)


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
    argv = ["pygrep", pattern]
    if not case_sensitive:
        argv.append("--ignore-case")
    if project_root:
        argv += ["--project-root", project_root]
    return _run(_pygrep_main, argv)
