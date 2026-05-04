"""pygrep — Text-pattern search across Python files in the project."""

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from ._common import collect_python_files, find_project_root, read_source


@dataclass
class GrepResult:
    """A single line matched by a pattern search.

    ``filepath`` is relative to the project root. ``line`` is 1-based.
    ``snippet`` is the matched line with trailing whitespace stripped.
    """

    filepath: str
    line: int
    snippet: str


def grep(pattern: str, root: Path, *, case_sensitive: bool = True) -> list[GrepResult]:
    """Search for *pattern* (regex) in every Python file under *root*.

    Args:
        pattern: Regular expression to search for.
        root: Project root directory.
        case_sensitive: When ``False``, matching is case-insensitive.

    Returns:
        List of :class:`GrepResult` in file-path / line-number order.
    """
    flags = 0 if case_sensitive else re.IGNORECASE
    try:
        rx = re.compile(pattern, flags)
    except re.error as exc:
        print(f"Invalid pattern: {exc}", file=sys.stderr)
        sys.exit(1)

    results: list[GrepResult] = []
    for fpath in collect_python_files(root):
        source = read_source(fpath)
        if source is None:
            continue
        rel = str(fpath.relative_to(root))
        for lineno, line in enumerate(source.splitlines(), start=1):
            if rx.search(line):
                results.append(GrepResult(filepath=rel, line=lineno, snippet=line.rstrip()))
    return results


def main() -> None:
    """CLI entry point: parse arguments and print grep results."""
    parser = argparse.ArgumentParser(
        description="Search for a text pattern across Python files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("pattern", help="Regular expression to search for")
    parser.add_argument("--project-root", "-r", help="Project root (auto-detected if omitted)")
    parser.add_argument("--ignore-case", "-i", action="store_true", help="Case-insensitive matching")
    args = parser.parse_args()

    root = Path(args.project_root) if args.project_root else find_project_root(Path.cwd())
    results = grep(args.pattern, root, case_sensitive=not args.ignore_case)

    if not results:
        print("No matches found.")
        sys.exit(0)

    for r in results:
        print(f"{r.filepath}:{r.line}: {r.snippet}")
    print(f"\n{len(results)} match{'es' if len(results) != 1 else ''} found.")
    sys.exit(0)


if __name__ == "__main__":
    main()
