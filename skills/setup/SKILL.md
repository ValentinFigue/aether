---
name: setup
description: >
  Register the bonsai MCP server in user-global Claude Code config so its
  refactoring tools are available in all projects. Writes to ~/.claude.json
  via `claude mcp add --scope user`, which survives plugin updates. Run this
  once after installing the bonsai plugin.
when_to_use: >
  When the user wants to install or activate bonsai, when bonsai tools are
  missing after a plugin update, or when setting up bonsai for the first time.
allowed-tools: Bash
---

# Bonsai Setup

Register the bonsai MCP server in user-global config by running:

```bash
claude mcp add bonsai --scope user -- uvx bonsai
```

This writes to `~/.claude.json` (not inside the plugin directory), so it
survives plugin updates.

After running the command, tell the user:

> Bonsai is now registered. **Restart Claude Code** to load the MCP server.
> Once restarted, the tools `pyfindrefs`, `pycallers`, `pyfindunused`, `pygrep`,
> `pymove`, `pymovesymbol`, `pyrename`, and `pysignature` will be available.
>
> Run `/bonsai:setup` again after any bonsai plugin update if the tools stop working.

If the command fails because `uvx` is not installed, suggest:

```bash
# Install uv first:
curl -LsSf https://astral.sh/uv/install.sh | sh

# Then re-run:
claude mcp add bonsai --scope user -- uvx bonsai
```

If the user prefers pip over uvx:

```bash
pip install bonsai
claude mcp add bonsai --scope user -- python -m bonsai
```
