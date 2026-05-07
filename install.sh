#!/bin/bash
set -e

VERSION="1.0.0"

MODE="local"
WITH_CLAUDE_MD=false
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    global|--global) MODE="global" ;;
    --claude-md)     WITH_CLAUDE_MD=true ;;
    --dry-run)       DRY_RUN=true ;;
  esac
done

if [ "$MODE" = "global" ]; then
  SETTINGS_DIR="$HOME/.claude"
  HOOK_DIR="$HOME/.local/share/aether"
  CLI_DIR="$HOME/.local/bin"
  CLAUDE_FILE="$HOME/.claude/CLAUDE.md"
  MANIFEST="$HOME/.claude/aether.manifest"
else
  SETTINGS_DIR=".claude"
  HOOK_DIR=".claude/hooks"
  CLI_DIR=".bin"
  CLAUDE_FILE="./CLAUDE.md"
  MANIFEST=".claude/aether.manifest"
fi

SETTINGS_FILE="$SETTINGS_DIR/settings.json"
HOOK_DEST="$HOOK_DIR/enforce-suite.sh"
SCOPE_ARG=""; [ "$MODE" = "global" ] && SCOPE_ARG="global"

# ── JSON helpers (Python3 → Node → jq fallback chain from cairn) ─────────────

_json_remove_stale_hooks() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF' > "$file.tmp" && mv "$file.tmp" "$file"
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
STALE = ["enforce-cairn", "enforce-temper", "enforce-whetstone",
         "enforce-bonsai", "post-cairn", "post-bonsai", "enforce-suite"]
for phase in ("PreToolUse", "PostToolUse"):
    entries = s.get("hooks", {}).get(phase, [])
    for entry in entries:
        entry["hooks"] = [
            h for h in entry.get("hooks", [])
            if not any(kw in h.get("command", "") for kw in STALE)
        ]
    # Remove empty entries
    s.get("hooks", {})[phase] = [
        e for e in entries if e.get("hooks")
    ]
print(json.dumps(s, indent=2))
PYEOF
  fi
}

_json_register_suite_hook() {
  local file="$1" hook_path="$2"
  local matcher="Bash|Write|Edit|MultiEdit"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$hook_path" "$matcher" <<'PYEOF' > "$file.tmp" && mv "$file.tmp" "$file"
import json, sys
f, hook_path, matcher = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f) as fh: s = json.load(fh)
hooks = s.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
entry = next((e for e in pre if e.get("matcher") == matcher), None)
if entry is None:
    entry = {"matcher": matcher, "hooks": []}
    pre.append(entry)
new_hook = {"type": "command", "command": hook_path}
if not any(h.get("command") == hook_path for h in entry["hooks"]):
    entry["hooks"].append(new_hook)
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" "$hook_path" "$matcher" <<'JSEOF' > "$file.tmp" && mv "$file.tmp" "$file"
const [f, hookPath, matcher] = process.argv.slice(2);
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.hooks = s.hooks || {};
s.hooks.PreToolUse = s.hooks.PreToolUse || [];
let entry = s.hooks.PreToolUse.find(e => e.matcher === matcher);
if (!entry) { entry = { matcher, hooks: [] }; s.hooks.PreToolUse.push(entry); }
entry.hooks = entry.hooks || [];
if (!entry.hooks.some(h => h.command === hookPath)) {
    entry.hooks.push({ type: "command", command: hookPath });
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq --arg p "$hook_path" --arg m "$matcher" '
      .hooks.PreToolUse |= (
        if . == null then [{"matcher":$m,"hooks":[{"type":"command","command":$p}]}]
        else
          if any(.[]; .matcher == $m) then
            map(if .matcher == $m then
              .hooks |= if any(.[]; .command == $p) then . else . + [{"type":"command","command":$p}] end
            else . end)
          else . + [{"matcher":$m,"hooks":[{"type":"command","command":$p}]}]
          end
        end
      )' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '  Could not register hook (install python3, node, or jq).\n'
    printf '  Add a PreToolUse hook pointing to %s manually.\n' "$hook_path"
    return 1
  fi
}

_json_add_perms() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF' > "$file.tmp" && mv "$file.tmp" "$file"
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
allow = s.setdefault("permissions", {}).setdefault("allow", [])
perms = ["Bash", "Read", "Write", "mcp__bonsai_py__*", "mcp__bonsai_ts__*"]
for p in perms:
    if p not in allow: allow.append(p)
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF' > "$file.tmp" && mv "$file.tmp" "$file"
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.permissions = s.permissions || {};
s.permissions.allow = s.permissions.allow || [];
const perms = ["Bash", "Read", "Write", "mcp__bonsai_py__*", "mcp__bonsai_ts__*"];
for (const p of perms) { if (!s.permissions.allow.includes(p)) s.permissions.allow.push(p); }
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '.permissions.allow |= (. + ["Bash","Read","Write","mcp__bonsai_py__*","mcp__bonsai_ts__*"] | unique)' \
      "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '  Could not add permissions (install python3, node, or jq).\n'
    return 1
  fi
}

# ── Step 1: Ensure settings.json exists ──────────────────────────────────────

if $DRY_RUN; then
  printf '[dry-run] Would install aether v%s (%s)\n\n' "$VERSION" "$MODE"
fi

if $DRY_RUN; then
  printf '  [dry-run] Would ensure %s exists\n' "$SETTINGS_FILE"
else
  mkdir -p "$SETTINGS_DIR"
  [ -f "$SETTINGS_FILE" ] || { printf '{}\n' > "$SETTINGS_FILE"; printf '✓ Created %s\n' "$SETTINGS_FILE"; }
fi

# ── Step 2: Remove stale per-plugin hooks ────────────────────────────────────

if $DRY_RUN; then
  printf '  [dry-run] Would remove stale per-plugin hooks from %s\n' "$SETTINGS_FILE"
elif [ -f "$SETTINGS_FILE" ]; then
  _json_remove_stale_hooks "$SETTINGS_FILE"
  printf '✓ Removed any stale per-plugin hooks from %s\n' "$SETTINGS_FILE"
fi

# ── Step 3: Install plugins ───────────────────────────────────────────────────

printf '\nInstalling plugins...\n'

# FIXME: bonsai-py is not yet published to PyPI and bonsai-ts is not yet published to npm.
# The --published flag in bonsai's install.sh will not work until the packages are released.
# Until then, bonsai must be installed from its local repo clone using:
#   python -m bonsai --install [--global]   (from within the bonsai repo directory)
# Reference: https://github.com/valentinfigue/bonsai  (check PUBLISHED flag in install.sh)
printf '  bonsai: skipped — bonsai-py/bonsai-ts not yet on PyPI/npm.\n'
printf '          Install manually from the bonsai repo: python -m bonsai --install\n'
printf '          See: https://github.com/valentinfigue/bonsai\n'

# cairn
if $DRY_RUN; then
  printf '  [dry-run] Would install cairn (%s)\n' "$MODE"
else
  curl -fsSL https://raw.githubusercontent.com/ValentinFigue/cairn/main/install.sh | bash -s -- $SCOPE_ARG 2>&1 | grep -E '(✓|could not|Note:)' || true
  printf '  ✓ cairn installed\n'
fi

# whetstone
if $DRY_RUN; then
  printf '  [dry-run] Would install whetstone (%s)\n' "$MODE"
else
  curl -fsSL https://raw.githubusercontent.com/ValentinFigue/whetstone/main/install.sh | bash -s -- $SCOPE_ARG 2>&1 | grep -E '(✓|could not|Note:)' || true
  printf '  ✓ whetstone installed\n'
fi

# temper
if $DRY_RUN; then
  printf '  [dry-run] Would install temper (%s)\n' "$MODE"
else
  curl -fsSL https://raw.githubusercontent.com/ValentinFigue/temper/main/install.sh | bash -s -- $SCOPE_ARG 2>&1 | grep -E '(✓|could not|Note:)' || true
  printf '  ✓ temper installed\n'
fi

# Step 3b: clean up per-plugin hooks added by individual installers
if ! $DRY_RUN && [ -f "$SETTINGS_FILE" ]; then
  _json_remove_stale_hooks "$SETTINGS_FILE"
  printf '  ✓ Consolidated plugin hooks\n'
fi

# ── Step 4: Install enforce-suite.sh ─────────────────────────────────────────

printf '\nInstalling suite hook...\n'

if ! $DRY_RUN; then
  mkdir -p "$HOOK_DIR"
  cp "$SCRIPT_DIR/hooks/enforce-suite.sh" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"
  printf '  ✓ enforce-suite.sh installed to %s\n' "$HOOK_DEST"

  if [ ! -f "$SETTINGS_FILE" ]; then
    printf '{}' > "$SETTINGS_FILE"
  fi

  _json_register_suite_hook "$SETTINGS_FILE" "$HOOK_DEST" && \
    printf '  ✓ PreToolUse hook registered in %s\n' "$SETTINGS_FILE"
else
  printf '  [dry-run] Would install enforce-suite.sh to %s\n' "$HOOK_DEST"
  printf '  [dry-run] Would register PreToolUse hook (matcher: Bash|Write|Edit|MultiEdit)\n'
fi

# ── Step 5: Write permissions ─────────────────────────────────────────────────

printf '\nUpdating permissions...\n'

if ! $DRY_RUN; then
  _json_add_perms "$SETTINGS_FILE" && \
    printf '  ✓ Permissions (Bash, Read, Write, mcp__bonsai_*) added to %s\n' "$SETTINGS_FILE"
else
  printf '  [dry-run] Would add permissions to %s\n' "$SETTINGS_FILE"
fi

# ── Step 6: Install aether CLI ────────────────────────────────────────────────

printf '\nInstalling aether CLI...\n'

if ! $DRY_RUN; then
  mkdir -p "$CLI_DIR"
  cp "$SCRIPT_DIR/bin/aether" "$CLI_DIR/aether"
  chmod +x "$CLI_DIR/aether"
  printf '  ✓ aether CLI installed to %s/aether\n' "$CLI_DIR"
  if [ "$MODE" = "global" ] && ! echo "$PATH" | grep -q "$CLI_DIR"; then
    printf '  Note: add %s to your PATH to use the aether command\n' "$CLI_DIR"
  fi
else
  printf '  [dry-run] Would install aether CLI to %s/aether\n' "$CLI_DIR"
fi

# ── Step 7: Inject CLAUDE.md block ───────────────────────────────────────────

if [ "$WITH_CLAUDE_MD" = true ]; then
  printf '\nInjecting CLAUDE.md block...\n'
  if ! $DRY_RUN; then
    # Remove per-plugin sentinels superseded by the unified aether block
    for marker in "cairn" "temper" "whetstone" "bonsai"; do
      if [ -f "$CLAUDE_FILE" ] && grep -q "<!-- ${marker}:start -->" "$CLAUDE_FILE"; then
        awk "/<!-- ${marker}:start -->/{skip=1} !skip{print} /<!-- ${marker}:end -->/{skip=0}" \
          "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
        printf '  ✓ Removed standalone %s section from %s\n' "$marker" "$CLAUDE_FILE"
      fi
    done

    if [ -f "$CLAUDE_FILE" ] && grep -q "<!-- aether:start -->" "$CLAUDE_FILE"; then
      printf '  %s already contains aether section — skipped\n' "$CLAUDE_FILE"
    else
      {
        printf '\n'
        cat "$SCRIPT_DIR/templates/CLAUDE.md"
      } >> "$CLAUDE_FILE"
      printf '  ✓ aether rules added to %s\n' "$CLAUDE_FILE"
    fi
  else
    printf '  [dry-run] Would inject templates/CLAUDE.md into %s\n' "$CLAUDE_FILE"
  fi
fi

# ── Step 8: Write install manifest ───────────────────────────────────────────

if ! $DRY_RUN; then
  mkdir -p "$(dirname "$MANIFEST")"
  cat > "$MANIFEST" <<MANIFEST_EOF
version=$VERSION
scope=$MODE
hook=$HOOK_DEST
MANIFEST_EOF
  printf '\n  ✓ Manifest written to %s\n' "$MANIFEST"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf '\n'
if $DRY_RUN; then
  printf 'Dry run complete. Run without --dry-run to apply.\n'
else
  if [ "$MODE" = "global" ]; then
    printf 'aether v%s installed globally.\n' "$VERSION"
    printf 'Restart Claude Code to activate.\n'
    printf '\n'
    printf 'Run: aether status\n'
  else
    printf 'aether v%s installed for this project.\n' "$VERSION"
    printf 'Restart Claude Code to activate.\n'
    printf '\n'
    printf 'Tips:\n'
    printf '  Global install:        bash install.sh --global\n'
    printf '  With CLAUDE.md rules:  bash install.sh --claude-md\n'
    printf '  Dry run:               bash install.sh --dry-run\n'
  fi
fi
