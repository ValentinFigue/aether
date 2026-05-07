#!/bin/bash
set -e

MODE="local"
WITH_CLAUDE_MD=false

for arg in "$@"; do
  case "$arg" in
    global) MODE="global" ;;
    --claude-md) WITH_CLAUDE_MD=true ;;
  esac
done

if [ "$MODE" = "global" ]; then
  COMMANDS_DIR="$HOME/.claude/commands"
  SETTINGS_DIR="$HOME/.claude"
  CLAUDE_FILE="$HOME/.claude/CLAUDE.md"
else
  COMMANDS_DIR=".claude/commands"
  SETTINGS_DIR=".claude"
  CLAUDE_FILE="./CLAUDE.md"
fi

ALL_COMMANDS="cairn-commit.md cairn-pr.md cairn-changelog.md cairn-summary.md"

_json_add_perms() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
allow = s.setdefault("permissions", {}).setdefault("allow", [])
for p in ["Bash", "Read", "Write"]:
    if p not in allow: allow.append(p)
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF'
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.permissions = s.permissions || {};
s.permissions.allow = s.permissions.allow || [];
for (const p of ["Bash", "Read", "Write"]) { if (!s.permissions.allow.includes(p)) s.permissions.allow.push(p); }
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '.permissions.allow |= (. + ["Bash","Read","Write"] | unique)' "$file"
  else
    return 1
  fi
}

_json_add_hook() {
  local file="$1" hook_path="$2"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$hook_path" <<'PYEOF'
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
hooks = s.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
bash_entry = next((e for e in pre if e.get("matcher") == "Bash"), None)
if bash_entry is None:
    bash_entry = {"matcher": "Bash", "hooks": []}
    pre.append(bash_entry)
new_hook = {"type": "command", "command": hook_path}
if not any(h.get("command") == hook_path for h in bash_entry["hooks"]):
    bash_entry["hooks"].append(new_hook)
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" "$hook_path" <<'JSEOF'
const [f, hookPath] = process.argv.slice(2);
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.hooks = s.hooks || {};
s.hooks.PreToolUse = s.hooks.PreToolUse || [];
let bashEntry = s.hooks.PreToolUse.find(e => e.matcher === "Bash");
if (!bashEntry) { bashEntry = { matcher: "Bash", hooks: [] }; s.hooks.PreToolUse.push(bashEntry); }
bashEntry.hooks = bashEntry.hooks || [];
if (!bashEntry.hooks.some(h => h.command === hookPath)) {
    bashEntry.hooks.push({ type: "command", command: hookPath });
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq --arg p "$hook_path" '
      .hooks.PreToolUse |= (
        if . == null then [{"matcher":"Bash","hooks":[{"type":"command","command":$p}]}]
        else
          if any(.[]; .matcher == "Bash") then
            map(if .matcher == "Bash" then
              .hooks |= if any(.[]; .command == $p) then . else . + [{"type":"command","command":$p}] end
            else . end)
          else . + [{"matcher":"Bash","hooks":[{"type":"command","command":$p}]}]
          end
        end
      )' "$file"
  else
    return 1
  fi
}

_json_remove_hook() {
  local file="$1" hook_path="$2"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$hook_path" <<'PYEOF'
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
pre = s.get("hooks", {}).get("PreToolUse", [])
for entry in pre:
    if entry.get("matcher") == "Bash":
        entry["hooks"] = [h for h in entry.get("hooks", []) if h.get("command") != hook_path]
print(json.dumps(s, indent=2))
PYEOF
  else
    return 1
  fi
}

_json_add_post_hook() {
  local file="$1" hook_path="$2"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$hook_path" <<'PYEOF'
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
hooks = s.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])
matcher = "Bash|Write|Edit"
post_entry = next((e for e in post if e.get("matcher") == matcher), None)
if post_entry is None:
    post_entry = {"matcher": matcher, "hooks": []}
    post.append(post_entry)
new_hook = {"type": "command", "command": hook_path}
if not any(h.get("command") == hook_path for h in post_entry["hooks"]):
    post_entry["hooks"].append(new_hook)
print(json.dumps(s, indent=2))
PYEOF
  else
    return 1
  fi
}

_json_remove_post_hook() {
  local file="$1" hook_path="$2"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$hook_path" <<'PYEOF'
import json, sys
f, hook_path = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
post = s.get("hooks", {}).get("PostToolUse", [])
for entry in post:
    if entry.get("matcher") == "Bash|Write|Edit":
        entry["hooks"] = [h for h in entry.get("hooks", []) if h.get("command") != hook_path]
print(json.dumps(s, indent=2))
PYEOF
  else
    return 1
  fi
}

# Install command files
mkdir -p "$COMMANDS_DIR"
for name in $ALL_COMMANDS; do
  curl -fsSL \
    -o "$COMMANDS_DIR/$name" \
    "https://raw.githubusercontent.com/ValentinFigue/cairn/main/.claude/commands/$name"
  cmd_name="${name%.md}"
  echo "✓ /$cmd_name installed to $COMMANDS_DIR"
done

# Inject Bash + Read + Write permissions into settings.json
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
  printf '{\n  "permissions": {\n    "allow": ["Bash", "Read", "Write"]\n  }\n}\n' > "$SETTINGS_FILE"
  echo "✓ Permissions (Bash, Read, Write) added to $SETTINGS_FILE"
elif _json_add_perms "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"; then
  echo "✓ Permissions (Bash, Read, Write) added to $SETTINGS_FILE"
else
  echo "  Could not update $SETTINGS_FILE automatically (install python3, node, or jq)."
  echo "  Add \"Bash\", \"Read\", and \"Write\" to permissions.allow manually."
fi

# Optionally inject documentation rules into CLAUDE.md
if [ "$WITH_CLAUDE_MD" = true ]; then
  MARKER="<!-- cairn:start -->"

  if [ -f "$CLAUDE_FILE" ] && grep -q "$MARKER" "$CLAUDE_FILE"; then
    echo "✓ $CLAUDE_FILE already contains cairn section — skipped"
  else
    TEMPLATE=$(curl -fsSL \
      "https://raw.githubusercontent.com/ValentinFigue/cairn/main/templates/CLAUDE.md")
    {
      printf "\n"
      echo "<!-- cairn:start -->"
      echo "$TEMPLATE"
      echo "<!-- cairn:end -->"
    } >> "$CLAUDE_FILE"
    echo "✓ Documentation rules added to $CLAUDE_FILE"
  fi
fi

# Install cairn CLI and hook for global mode
if [ "$MODE" = "global" ]; then
  CLI_DIR="$HOME/.local/bin"
  mkdir -p "$CLI_DIR"
  curl -fsSL \
    -o "$CLI_DIR/cairn" \
    "https://raw.githubusercontent.com/ValentinFigue/cairn/main/bin/cairn"
  chmod +x "$CLI_DIR/cairn"
  echo "✓ cairn CLI installed to $CLI_DIR/cairn"

  if ! echo "$PATH" | grep -q "$CLI_DIR"; then
    echo "  Note: add $CLI_DIR to your PATH to use the 'cairn' command"
  fi

  # Install enforce-cairn hook (PreToolUse)
  HOOK_DIR="$HOME/.local/share/cairn"
  HOOK_FILE="$HOOK_DIR/enforce-cairn.sh"
  POST_HOOK_FILE="$HOOK_DIR/post-cairn.sh"
  mkdir -p "$HOOK_DIR"
  curl -fsSL \
    -o "$HOOK_FILE" \
    "https://raw.githubusercontent.com/ValentinFigue/cairn/main/hooks/enforce-cairn.sh"
  chmod +x "$HOOK_FILE"
  echo "✓ enforce-cairn hook installed to $HOOK_FILE"

  # Install post-cairn hook (PostToolUse)
  curl -fsSL \
    -o "$POST_HOOK_FILE" \
    "https://raw.githubusercontent.com/ValentinFigue/cairn/main/hooks/post-cairn.sh"
  chmod +x "$POST_HOOK_FILE"
  echo "✓ post-cairn hook installed to $POST_HOOK_FILE"

  GLOBAL_SETTINGS="$HOME/.claude/settings.json"
  if [ ! -f "$GLOBAL_SETTINGS" ]; then
    printf '{\n  "hooks": {\n    "PreToolUse": [{\n      "matcher": "Bash",\n      "hooks": [{"type": "command", "command": "%s"}]\n    }],\n    "PostToolUse": [{\n      "matcher": "Bash|Write|Edit",\n      "hooks": [{"type": "command", "command": "%s"}]\n    }]\n  }\n}\n' "$HOOK_FILE" "$POST_HOOK_FILE" > "$GLOBAL_SETTINGS"
    echo "✓ Hooks registered in $GLOBAL_SETTINGS"
  else
    if _json_add_hook "$GLOBAL_SETTINGS" "$HOOK_FILE" > "$GLOBAL_SETTINGS.tmp" && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS"; then
      echo "✓ PreToolUse hook registered in $GLOBAL_SETTINGS"
    else
      echo "  Could not register PreToolUse hook automatically (install python3, node, or jq)."
      echo "  Add a PreToolUse Bash hook pointing to $HOOK_FILE manually."
    fi
    if _json_add_post_hook "$GLOBAL_SETTINGS" "$POST_HOOK_FILE" > "$GLOBAL_SETTINGS.tmp" && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS"; then
      echo "✓ PostToolUse hook registered in $GLOBAL_SETTINGS"
    else
      echo "  Could not register PostToolUse hook automatically (install python3, node, or jq)."
      echo "  Add a PostToolUse Bash|Write|Edit hook pointing to $POST_HOOK_FILE manually."
    fi
  fi
fi

echo ""
if [ "$MODE" = "global" ]; then
  echo "Available in all Claude Code projects. Restart Claude Code to activate."
  echo ""
  echo "Commands: /cairn-commit  /cairn-pr  /cairn-changelog  /cairn-summary"
  echo ""
  echo "Run 'cairn status' to verify your install."
else
  echo "Available in this project. Restart Claude Code to activate."
  echo ""
  echo "Commands: /cairn-commit  /cairn-pr  /cairn-changelog  /cairn-summary"
  echo ""
  echo "Tips:"
  echo "  Global install:             bash install.sh global"
  echo "  With doc rules:             bash install.sh --claude-md"
  echo "  Global + doc rules:         bash install.sh global --claude-md"
fi
