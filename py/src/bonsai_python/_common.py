"""Shared utilities, data structures, and helpers for bonsai refactoring tools."""

import ast
import logging
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib  # type: ignore[no-remodule]
    except ImportError:
        tomllib = None  # type: ignore[assignment]


@dataclass
class PyToolsConfig:
    """Project-level configuration loaded from ``[tool.bonsai]`` in pyproject.toml.

    Fields set to ``None`` mean "use the built-in default set"; a ``frozenset``
    value replaces the default entirely. ``extra_*`` fields are always merged on
    top of whichever base set is active.
    """

    # None means "use the built-in default"; a frozenset replaces it entirely.
    dead_code_decorators: frozenset[str] | None = None
    dead_code_entry_points: frozenset[str] | None = None
    dead_code_skip_dirs: frozenset[str] | None = None
    # Always merged on top of whichever base set is active.
    dead_code_extra_decorators: frozenset[str] = frozenset()
    dead_code_extra_entry_points: frozenset[str] = frozenset()
    dead_code_extra_skip_dirs: frozenset[str] = frozenset()


def _opt_frozenset(section: dict, key: str) -> frozenset[str] | None:
    """Return ``frozenset(section[key])`` if *key* is present, else ``None``."""
    return frozenset(section[key]) if key in section else None


def load_config(root: Path) -> PyToolsConfig:
    """Read [tool.bonsai] from the project's pyproject.toml, if present."""
    pyproject = root / "pyproject.toml"
    if not pyproject.exists():
        return PyToolsConfig()
    if tomllib is None:
        return PyToolsConfig()
    try:
        with pyproject.open("rb") as f:
            data = tomllib.load(f)
    except (OSError, ValueError):
        return PyToolsConfig()
    section = data.get("tool", {}).get("bonsai", {})
    return PyToolsConfig(
        dead_code_decorators=_opt_frozenset(section, "dead_code_decorators"),
        dead_code_entry_points=_opt_frozenset(section, "dead_code_entry_points"),
        dead_code_skip_dirs=_opt_frozenset(section, "dead_code_skip_dirs"),
        dead_code_extra_decorators=frozenset(section.get("dead_code_extra_decorators", [])),
        dead_code_extra_entry_points=frozenset(section.get("dead_code_extra_entry_points", [])),
        dead_code_extra_skip_dirs=frozenset(section.get("dead_code_extra_skip_dirs", [])),
    )


SKIP_DIRS = {
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".tox",
    ".nox",
    ".venv",
    "venv",
    "env",
    ".env",
    "node_modules",
    ".eggs",
    "build",
    "dist",
    ".ruff_cache",
}


def find_project_root(start: Path) -> Path:
    """Walk up from *start* and return the first directory containing a project marker.

    Args:
        start: Starting path (file or directory).

    Returns:
        The project root directory, or the parent of *start* if no marker is found.
    """
    current = start.resolve()
    if current.is_file():
        current = current.parent
    for d in [current, *current.parents]:
        if any((d / m).exists() for m in ["pyproject.toml", "setup.py", "setup.cfg", ".git", "src"]):
            return d
    return start.resolve().parent


def collect_python_files(root: Path) -> list[Path]:
    """Recursively collect all ``.py`` files under *root*, skipping known non-source dirs.

    Args:
        root: Root directory to walk.

    Returns:
        Sorted list of absolute ``Path`` objects for every ``.py`` file found.
    """
    results = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for f in filenames:
            if f.endswith(".py"):
                results.append(Path(dirpath) / f)
    return results


def path_to_module(filepath: Path, root: Path) -> str | None:
    """Convert a filesystem path to a dotted Python module name relative to *root*.

    Args:
        filepath: Absolute or relative path to a ``.py`` file or package ``__init__.py``.
        root: Project root used as the import base.

    Returns:
        Dotted module name (e.g. ``"src.utils.helpers"``), or ``None`` if *filepath*
        is not under *root*.
    """
    try:
        rel = filepath.resolve().relative_to(root.resolve())
    except ValueError:
        return None
    parts = list(rel.parts)
    if not parts:
        return None
    if parts[-1].endswith(".py"):
        parts[-1] = parts[-1][:-3]
    if parts[-1] == "__init__":
        parts = parts[:-1]
    return ".".join(parts) if parts else None


def module_to_path(module: str, root: Path) -> Path | None:
    """Resolve a dotted module name to its source file path under *root*.

    Checks both ``module/last.py`` and ``module/last/__init__.py`` forms.

    Args:
        module: Dotted module name (e.g. ``"src.utils.helpers"``).
        root: Project root directory.

    Returns:
        Path to the module file, or ``None`` if not found.
    """
    parts = module.split(".")
    if len(parts) > 1:
        fp = root / Path(*parts[:-1]) / (parts[-1] + ".py")
    else:
        fp = root / (parts[0] + ".py")
    if fp.exists():
        return fp
    pkg = root / Path(*parts) / "__init__.py"
    return pkg if pkg.exists() else None


def read_source(path: Path) -> str | None:
    """Read *path* as UTF-8 text, returning ``None`` on decode or IO error."""
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def parse_file(path: Path) -> ast.Module | None:
    """Parse *path* into an AST, returning ``None`` on read or syntax error."""
    source = read_source(path)
    if source is None:
        return None
    try:
        return ast.parse(source, filename=str(path))
    except SyntaxError:
        return None


def get_lines(path: Path) -> list[str] | None:
    """Read *path* and return its lines (with line endings), or ``None`` on error."""
    source = read_source(path)
    if source is None:
        return None
    return source.splitlines(keepends=True)


def resolve_relative_import(importing_file: Path, root: Path, level: int, module: str | None) -> str | None:
    """Resolve a relative import to an absolute dotted module name.

    Args:
        importing_file: The file containing the relative import statement.
        root: Project root used to compute module names.
        level: Number of leading dots (``from . import x`` → 1, ``from .. import x`` → 2).
        module: The module part after the dots, or ``None`` for bare ``from . import x``.

    Returns:
        Absolute dotted module name, or ``None`` if resolution fails.
    """
    file_module = path_to_module(importing_file, root)
    if file_module is None:
        return None
    parts = file_module.split(".")
    if importing_file.name != "__init__.py":
        parts = parts[:-1]
    if level > len(parts):
        return None
    base_parts = parts[: len(parts) - (level - 1)]
    if module:
        return ".".join(base_parts + module.split("."))
    return ".".join(base_parts)


def normalize_target(target: str, root: Path) -> str:
    """Normalize a symbol target to ``module:Symbol`` format.

    Accepts either the canonical ``module:Symbol`` format or a file-path variant
    ``path/to/file.py:Symbol`` (absolute or relative to *root*).  File paths are
    detected by the presence of ``/`` or a ``.py`` suffix before the ``:``.

    Args:
        target: Symbol reference, e.g. ``"src/utils/helpers.py:format_date"`` or
            ``"src.utils.helpers:format_date"``.
        root: Project root used to make absolute paths relative.

    Returns:
        Canonical ``"dotted.module:Symbol"`` string.  Returns *target* unchanged
        if the module part does not look like a file path or cannot be resolved.
    """
    if ":" not in target:
        return target
    module_part, _, symbol_part = target.partition(":")
    # Detect file-path style: contains "/" or ends with ".py"
    if "/" not in module_part and not module_part.endswith(".py"):
        return target
    fp = Path(module_part)
    if not fp.is_absolute():
        fp = root / fp
    module_name = path_to_module(fp, root)
    if module_name is None:
        # Try against each python root
        for r in python_roots(root):
            module_name = path_to_module(fp, r)
            if module_name is not None:
                break
    if module_name is None:
        return target
    return f"{module_name}:{symbol_part}"


def parse_symbol_ref(ref: str) -> tuple[str, str, str | None]:
    """Parse a ``module:Symbol`` or ``module:Class.method`` reference string.

    Args:
        ref: Reference in ``"module:symbol"`` or ``"module:Class.method"`` format.

    Returns:
        A 3-tuple of ``(module_name, symbol_name, method_name_or_None)``.

    Raises:
        SystemExit: If *ref* does not contain a ``:``.
    """
    if ":" not in ref:
        logger.error("symbol reference must be 'module:symbol' (got %r)", ref)
        sys.exit(1)
    module, symbol_path = ref.split(":", 1)
    parts = symbol_path.split(".", 1)
    return module, parts[0], parts[1] if len(parts) > 1 else None


@dataclass
class FileEdit:
    """A single text replacement within a source file.

    All line and column indices are **0-based**. ``end_line`` is inclusive.
    ``end_col`` is the exclusive column of the last character to replace
    (i.e. ``lines[end_line][start_col:end_col]`` is the text being replaced).
    """

    start_line: int  # 0-indexed
    end_line: int  # 0-indexed, inclusive
    start_col: int
    end_col: int
    new_text: str
    description: str = ""


@dataclass
class FileChanges:
    """A collection of :class:`FileEdit` instances targeting a single file."""

    filepath: Path
    edits: list[FileEdit] = field(default_factory=list)

    def apply(self, lines: list[str]) -> list[str]:
        """Apply all edits to *lines* and return the modified line list.

        Edits are applied in reverse order (bottom-to-top) so that earlier
        line numbers remain valid throughout the process.

        Args:
            lines: Source lines of the file (with line endings preserved).

        Returns:
            New line list with all edits applied.
        """
        result = list(lines)
        for edit in sorted(self.edits, key=lambda e: (e.start_line, e.start_col), reverse=True):
            if edit.start_line == edit.end_line:
                line = result[edit.start_line]
                result[edit.start_line] = line[: edit.start_col] + edit.new_text + line[edit.end_col :]
            else:
                first = result[edit.start_line][: edit.start_col]
                last = result[edit.end_line][edit.end_col :]
                result[edit.start_line : edit.end_line + 1] = [first + edit.new_text + last]
        return result


@dataclass
class TrackedImport:
    """An import statement that brings a target symbol into scope.

    ``is_module_import`` is ``True`` when the file imports the module
    (``import mod``) rather than the symbol directly (``from mod import sym``).
    In that case ``module_alias`` holds the local name used for the module.
    ``lineno`` and ``end_lineno`` are 1-based AST line numbers.
    """

    node: ast.stmt
    local_name: str
    is_module_import: bool
    module_alias: str | None = None
    lineno: int = 0
    end_lineno: int = 0


def python_roots(root: Path) -> list[Path]:
    """Return project root plus nested Python source roots.

    Handles two cases:
    - Nested projects: immediate subdirectories that contain their own
      ``pyproject.toml`` / ``setup.py`` / ``setup.cfg``.
    - ``src/`` layout: immediate subdirectories that are *not* themselves
      Python packages (no ``__init__.py``) but *contain* at least one
      Python package (a subdirectory with ``__init__.py``).
    """
    roots = [root]
    try:
        for child in root.iterdir():
            if not child.is_dir():
                continue
            project_markers = ["pyproject.toml", "setup.py", "setup.cfg"]
            if any((child / m).exists() for m in project_markers):
                roots.append(child)
                continue
            # src-layout: not a package itself, but contains packages
            if not (child / "__init__.py").exists():
                try:
                    has_package = any(
                        (grandchild / "__init__.py").exists() for grandchild in child.iterdir() if grandchild.is_dir()
                    )
                except OSError:
                    has_package = False
                if has_package:
                    roots.append(child)
    except OSError:
        pass
    return roots


def find_module_path(module_name: str, root: Path) -> Path | None:
    """Resolve *module_name* against every Python root under *root*.

    Tries each root returned by :func:`python_roots` in order and returns the
    first match. This handles both flat and ``src/``-layout projects.

    Args:
        module_name: Dotted module name (e.g. ``"bonsai.pyfindrefs"``).
        root: Project root directory.

    Returns:
        Path to the module file, or ``None`` if not found in any root.
    """
    for r in python_roots(root):
        p = module_to_path(module_name, r)
        if p is not None:
            return p
    return None


def module_aliases_for_file(fpath: Path, roots: list[Path]) -> list[str]:
    """Return all dotted module names for *fpath* across every Python root."""
    return [m for r in roots if (m := path_to_module(fpath, r))]


def find_imports_of_symbol(
    tree: ast.Module,
    filepath: Path,
    root: Path,
    target_modules: frozenset[str],
    target_symbol: str,
) -> list[TrackedImport]:
    """Find all import nodes in *tree* that bring *target_symbol* into scope.

    Handles ``import mod``, ``from mod import sym``, ``from mod import sym as
    alias``, star imports, and the ``from parent import module_leaf`` pattern
    (where the symbol is later accessed as ``module_leaf.symbol``).

    Args:
        tree: Parsed AST of the file to inspect.
        filepath: Path of the file (used for relative import resolution).
        root: Project root.
        target_modules: All known dotted module names for the definition file
            (e.g. both ``"mypkg.utils"`` and ``"src.mypkg.utils"`` for
            src-layout projects).
        target_symbol: Name of the symbol being searched for.

    Returns:
        List of :class:`TrackedImport` objects for each import that exposes
        *target_symbol* in this file.
    """
    results: list[TrackedImport] = []
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if any(
                    alias.name == tm or alias.name.startswith(tm + ".")
                    for tm in target_modules
                ):
                    results.append(
                        TrackedImport(
                            node=node,
                            local_name=target_symbol,
                            is_module_import=True,
                            module_alias=alias.asname or alias.name.split(".")[0],
                            lineno=node.lineno,
                            end_lineno=node.end_lineno or node.lineno,
                        )
                    )
        elif isinstance(node, ast.ImportFrom):
            resolved = (
                resolve_relative_import(filepath, root, node.level, node.module)
                if node.level > 0
                else node.module
            )
            if resolved in target_modules:
                for alias in node.names:
                    if alias.name in (target_symbol, "*"):
                        results.append(
                            TrackedImport(
                                node=node,
                                local_name=(
                                    alias.asname or alias.name
                                    if alias.name != "*"
                                    else target_symbol
                                ),
                                is_module_import=False,
                                lineno=node.lineno,
                                end_lineno=node.end_lineno or node.lineno,
                            )
                        )
            # from parent import module_leaf (then module_leaf.symbol)
            for tm in target_modules:
                _parts = tm.rsplit(".", 1)
                if len(_parts) == 2 and resolved == _parts[0]:
                    for alias in node.names:
                        if alias.name == _parts[1]:
                            results.append(
                                TrackedImport(
                                    node=node,
                                    local_name=target_symbol,
                                    is_module_import=True,
                                    module_alias=alias.asname or alias.name,
                                    lineno=node.lineno,
                                    end_lineno=node.end_lineno or node.lineno,
                                )
                            )
    return results


def apply_changes(changes: list[FileChanges], dry_run: bool = False) -> int:
    """Apply a list of :class:`FileChanges` to disk, or preview them in dry-run mode.

    Writes are performed atomically (write to ``.tmp`` then ``os.replace``) to
    avoid corrupting files on crash.

    Args:
        changes: File changes to apply.
        dry_run: When ``True``, print a diff-style preview without modifying any files.

    Returns:
        Number of files modified (or that would be modified in dry-run mode).
    """
    modified = 0
    for fc in changes:
        if not fc.edits:
            continue
        lines = get_lines(fc.filepath)
        if lines is None:
            continue
        new_lines = fc.apply(lines)
        if dry_run:
            print(f"  Would modify: {fc.filepath}")
            for edit in sorted(fc.edits, key=lambda e: e.start_line):
                old = "".join(lines[edit.start_line : edit.end_line + 1]).rstrip("\n")
                print(f"    L{edit.start_line + 1}: {old[:120]}")
                print(f"     ->  {edit.new_text.rstrip()[:120]}")
        else:
            tmp = fc.filepath.with_name(fc.filepath.name + ".tmp")
            tmp.write_text("".join(new_lines), encoding="utf-8")
            os.replace(tmp, fc.filepath)
            print(f"  Updated {fc.filepath} ({len(fc.edits)} edit{'s' if len(fc.edits) != 1 else ''})")
        modified += 1
    return modified
