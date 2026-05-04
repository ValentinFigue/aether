"""pycallers — Find every call site of a Python function or method."""

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from ._common import find_project_root
from .pyfindrefs import find_refs


def main() -> None:
    """CLI entry point: parse arguments and print call-type references only."""
    parser = argparse.ArgumentParser(
        description="Find all call sites of a Python function.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("target", metavar="MODULE:SYMBOL", help="module:function or module:Class.method")
    parser.add_argument("--project-root", "-r", help="Project root (auto-detected if omitted)")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    root = Path(args.project_root) if args.project_root else find_project_root(Path.cwd())

    refs = find_refs(args.target, root)
    calls = [r for r in refs if r.ref_type == "call"]

    if args.json:
        print(json.dumps([asdict(r) for r in calls], indent=2))
        sys.exit(0)

    if not calls:
        print("No call sites found.")
        sys.exit(0)

    for ref in sorted(calls, key=lambda r: (r.filepath, r.line)):
        loc = f"{ref.filepath}:{ref.line}"
        print(f"  {loc:<60}  {ref.snippet[:80]}")
    print(f"\n{len(calls)} call site{'s' if len(calls) != 1 else ''} found.")
    sys.exit(0)


if __name__ == "__main__":
    main()
