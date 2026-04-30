"""CLI entry point for bonsai: installs the MCP server or runs it directly."""

import argparse
import importlib.metadata
import json
import logging
import os
import sys
from pathlib import Path

logger = logging.getLogger(__name__)


def _install(command: str, settings_path: Path) -> None:
    """Register bonsai as an MCP server in Claude Code.

    Writes the MCP server entry to ``~/.claude.json`` (user-scoped) and the
    permission allowlist entry to ``settings_path`` (``~/.claude/settings.json``).
    Both files are written atomically via a temporary file.

    Args:
        command: Python executable path to use as the MCP server command.
        settings_path: Path to ``~/.claude/settings.json`` for the permission entry.
    """
    claude_json_path = Path.home() / ".claude.json"

    # Write mcpServers entry to ~/.claude.json
    claude_json: dict = {}
    if claude_json_path.exists():
        try:
            claude_json = json.loads(claude_json_path.read_text())
        except json.JSONDecodeError:
            logger.warning("could not parse %s, preserving existing content.", claude_json_path)

    claude_json.setdefault("mcpServers", {})["bonsai-py"] = {
        "type": "stdio",
        "command": command,
        "args": ["-m", "bonsai_python"],
    }

    tmp = claude_json_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(claude_json, indent=2) + "\n")
    os.replace(tmp, claude_json_path)

    # Write mcp__bonsai_py__* permission to ~/.claude/settings.json
    settings: dict = {}
    if settings_path.exists():
        try:
            settings = json.loads(settings_path.read_text())
        except json.JSONDecodeError:
            logger.warning("could not parse %s, creating fresh config.", settings_path)

    allow = settings.setdefault("permissions", {}).setdefault("allow", [])
    if "mcp__bonsai_py__*" not in allow:
        allow.append("mcp__bonsai_py__*")
        tmp = settings_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(settings, indent=2) + "\n")
        os.replace(tmp, settings_path)

    print(f"Installed. Added 'bonsai-py' MCP server to {claude_json_path}")
    print("Restart Claude Code to load the bonsai-py MCP server.")
    print()
    print("Available tools: pyfindrefs, pycallers, pyfindunused, pygrep, pymove, pymovesymbol, pyrename, pysignature")


def _install_hooks(settings_path: Path) -> None:
    """Merge bonsai hook templates into ~/.claude/settings.json.

    Reads the bundled hooks template and adds any missing entries to the
    ``hooks`` array in *settings_path*, then writes the file atomically.
    Already-installed matchers are skipped so the operation is idempotent.

    Args:
        settings_path: Path to ``~/.claude/settings.json``.
    """
    template_path = Path(__file__).parent / "_hooks_template.json"
    if not template_path.exists():
        logger.error("hooks template not found at %s", template_path)
        return

    hook_entries = json.loads(template_path.read_text()).get("hooks", [])

    settings: dict = {}
    if settings_path.exists():
        try:
            settings = json.loads(settings_path.read_text())
        except json.JSONDecodeError:
            logger.warning("could not parse %s, creating fresh config.", settings_path)

    existing = settings.setdefault("hooks", [])
    existing_matchers = {h.get("matcher") for h in existing}
    added = sum(
        1
        for entry in hook_entries
        if entry.get("matcher") not in existing_matchers
        and not existing.append(entry)  # append returns None, so always True
    )

    if added:
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = settings_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(settings, indent=2) + "\n")
        os.replace(tmp, settings_path)
        print(f"Added {added} hook(s) to {settings_path}")
    else:
        print("Bonsai hooks already installed.")


def _verify(settings_path: Path) -> None:
    """Check whether bonsai is correctly registered in Claude Code and report status."""
    claude_json_path = Path.home() / ".claude.json"
    ok = True

    # Check ~/.claude.json for MCP server entry
    if not claude_json_path.exists():
        print(f"✗ {claude_json_path} not found — run: python -m bonsai_python --install")
        ok = False
    else:
        try:
            data = json.loads(claude_json_path.read_text())
        except json.JSONDecodeError:
            data = {}
        if "bonsai-py" in data.get("mcpServers", {}):
            print(f"✓ MCP server registered in {claude_json_path}")
        else:
            print(f"✗ 'bonsai-py' not in {claude_json_path} — run: python -m bonsai_python --install")
            ok = False

    # Check ~/.claude/settings.json for permission allowlist
    if not settings_path.exists():
        print(f"✗ {settings_path} not found — run: python -m bonsai_python --install")
        ok = False
    else:
        try:
            settings = json.loads(settings_path.read_text())
        except json.JSONDecodeError:
            settings = {}
        allow = settings.get("permissions", {}).get("allow", [])
        if "mcp__bonsai_py__*" in allow:
            print(f"✓ Permissions granted in {settings_path}")
        else:
            print(f"✗ 'mcp__bonsai_py__*' not in {settings_path} — run: python -m bonsai_python --install")
            ok = False

    if ok:
        print("\nAll good! Restart Claude Code if you haven't already.")
    else:
        print("\nRe-run 'python -m bonsai_python --install', then restart Claude Code.")


def main() -> None:
    """Parse CLI arguments and either install the MCP server or start it."""
    logging.basicConfig(format="%(levelname)s: %(message)s")
    parser = argparse.ArgumentParser(
        description="bonsai: AST-based Python refactoring tools for Claude Code",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {importlib.metadata.version('bonsai-py')}",
    )
    install_group = parser.add_argument_group("installation")
    install_group.add_argument(
        "--install",
        action="store_true",
        help="Add bonsai MCP server to ~/.claude.json and exit",
    )
    install_group.add_argument(
        "--verify",
        action="store_true",
        help="Check whether bonsai is correctly registered in Claude Code",
    )
    install_group.add_argument(
        "--install-hooks",
        action="store_true",
        help="Add bonsai pre/post tool-use hooks to ~/.claude/settings.json and exit",
    )
    install_group.add_argument(
        "--settings",
        default=str(Path.home() / ".claude" / "settings.json"),
        help="Path to Claude Code settings.json for permissions (default: ~/.claude/settings.json)",
    )

    args = parser.parse_args()

    if args.install:
        _install(sys.executable, Path(args.settings))
        return

    if args.verify:
        _verify(Path(args.settings))
        return

    if args.install_hooks:
        _install_hooks(Path(args.settings))
        return

    # Deferred import: avoids loading the full MCP server stack when --install is used.
    from .server import mcp

    mcp.run()


if __name__ == "__main__":
    main()
