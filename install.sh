#!/bin/bash
set -e

VERSION="1.0.0"

MODE="local"
WITH_CLAUDE_MD=false
DRY_RUN=false
WITH_BONSAI=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'EOF'
aether — install the whetstone → bonsai → temper → cairn suite

Usage:
  bash install.sh [global|--global] [--claude-md] [--no-bonsai] [--dry-run]

  --global       Install for every project (default: this project only)
  --claude-md    Append the unified rules block to CLAUDE.md
  --no-bonsai    Skip bonsai (the only plugin needing uv, node and npm)
  --dry-run      Print what would happen and change nothing

All four plugins are installed from this clone — no network access is used.
Keep the clone: bonsai registers MCP servers by absolute path into it.
EOF
}

for arg in "$@"; do
  case "$arg" in
    global|--global) MODE="global" ;;
    --claude-md)     WITH_CLAUDE_MD=true ;;
    --dry-run)       DRY_RUN=true ;;
    --no-bonsai)     WITH_BONSAI=false ;;
    -h|--help)       usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$arg"; usage; exit 1 ;;
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
GATE_DEST="$HOOK_DIR/gates"
SCOPE_ARG=""; [ "$MODE" = "global" ] && SCOPE_ARG="global"

SUITE_PLUGINS="whetstone bonsai temper cairn"
INSTALLED_PLUGINS=""
FAILED=0

# ── Helpers ──────────────────────────────────────────────────────────────────

# Snapshot a file before the first mutation of this run. Every JSON helper below
# rewrites in place via `> tmp && mv`, which truncates the original if the
# interpreter dies halfway — and settings.json / CLAUDE.md hold hand-written
# user content that is not recoverable from this repo.
_backup() {
  local file="$1"
  [ -f "$file" ] || return 0
  cp "$file" "$file.bak"
}

# Strip superseded PreToolUse hooks. PostToolUse is deliberately untouched:
# post-cairn.sh and post-bonsai.sh have no equivalent in enforce-suite.sh, and
# an earlier version of this list removed them, silently deleting bonsai's
# reference-drift nudge and cairn's post-review and changelog nudges.
_json_remove_stale_hooks() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF' > "$file.tmp" && mv "$file.tmp" "$file"
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
STALE = ["enforce-cairn", "enforce-temper", "enforce-whetstone",
         "enforce-bonsai", "enforce-suite"]
entries = s.get("hooks", {}).get("PreToolUse", [])
for entry in entries:
    entry["hooks"] = [
        h for h in entry.get("hooks", [])
        if not any(kw in h.get("command", "") for kw in STALE)
    ]
if "hooks" in s and "PreToolUse" in s["hooks"]:
    s["hooks"]["PreToolUse"] = [e for e in entries if e.get("hooks")]
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF' > "$file.tmp" && mv "$file.tmp" "$file"
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
const STALE = ["enforce-cairn", "enforce-temper", "enforce-whetstone",
               "enforce-bonsai", "enforce-suite"];
if (s.hooks && s.hooks.PreToolUse) {
  s.hooks.PreToolUse = s.hooks.PreToolUse
    .map(e => ({ ...e, hooks: (e.hooks || []).filter(
      h => !STALE.some(kw => (h.command || "").includes(kw))) }))
    .filter(e => e.hooks.length);
}
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '
      def stale: ["enforce-cairn","enforce-temper","enforce-whetstone","enforce-bonsai","enforce-suite"];
      if (.hooks.PreToolUse | type) == "array" then
        .hooks.PreToolUse |= (
          map(.hooks |= (map(select(.command as $c | (stale | any(. as $k | $c | contains($k))) | not))))
          | map(select((.hooks | length) > 0))
        )
      else . end
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '  Could not clean stale hooks (install python3, node, or jq).\n'
    return 1
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
if not any(h.get("command") == hook_path for h in entry["hooks"]):
    entry["hooks"].append({"type": "command", "command": hook_path})
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

# Servers register as bonsai-py / bonsai-ts, so their tools are named
# mcp__bonsai-py__*. The underscore spelling this used to write matched nothing.
_json_add_perms() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PYEOF' > "$file.tmp" && mv "$file.tmp" "$file"
import json, sys
f = sys.argv[1]
with open(f) as fh: s = json.load(fh)
allow = s.setdefault("permissions", {}).setdefault("allow", [])
perms = ["Bash", "Read", "Write", "mcp__bonsai-py__*", "mcp__bonsai-ts__*"]
for p in perms:
    if p not in allow: allow.append(p)
# Drop the underscore spelling if a previous install left it behind.
for dead in ("mcp__bonsai_py__*", "mcp__bonsai_ts__*"):
    while dead in allow: allow.remove(dead)
print(json.dumps(s, indent=2))
PYEOF
  elif command -v node &>/dev/null; then
    node - "$file" <<'JSEOF' > "$file.tmp" && mv "$file.tmp" "$file"
const f = process.argv[2];
const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
s.permissions = s.permissions || {};
s.permissions.allow = s.permissions.allow || [];
const perms = ["Bash", "Read", "Write", "mcp__bonsai-py__*", "mcp__bonsai-ts__*"];
for (const p of perms) { if (!s.permissions.allow.includes(p)) s.permissions.allow.push(p); }
s.permissions.allow = s.permissions.allow.filter(
  p => p !== "mcp__bonsai_py__*" && p !== "mcp__bonsai_ts__*");
process.stdout.write(JSON.stringify(s, null, 2) + "\n");
JSEOF
  elif command -v jq &>/dev/null; then
    jq '.permissions.allow |= ((. // []) + ["Bash","Read","Write","mcp__bonsai-py__*","mcp__bonsai-ts__*"]
        | map(select(. != "mcp__bonsai_py__*" and . != "mcp__bonsai_ts__*")) | unique)' \
      "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '  Could not add permissions (install python3, node, or jq).\n'
    return 1
  fi
}

# ── Step 1: Ensure settings.json exists ──────────────────────────────────────

if $DRY_RUN; then
  printf '[dry-run] Would install aether v%s (%s) from %s\n\n' "$VERSION" "$MODE" "$SCRIPT_DIR"
  printf '  [dry-run] Would ensure %s exists\n' "$SETTINGS_FILE"
else
  mkdir -p "$SETTINGS_DIR"
  [ -f "$SETTINGS_FILE" ] || { printf '{}\n' > "$SETTINGS_FILE"; printf '✓ Created %s\n' "$SETTINGS_FILE"; }
  _backup "$SETTINGS_FILE"
fi

# ── Step 2: Remove stale per-plugin PreToolUse hooks ─────────────────────────

if $DRY_RUN; then
  printf '  [dry-run] Would remove superseded PreToolUse hooks from %s\n' "$SETTINGS_FILE"
  printf '  [dry-run] Would leave PostToolUse hooks (post-cairn, post-bonsai) intact\n'
elif [ -f "$SETTINGS_FILE" ]; then
  _json_remove_stale_hooks "$SETTINGS_FILE" || true
  printf '✓ Removed superseded per-plugin PreToolUse hooks\n'
fi

# ── Step 3: Install plugins from this clone ──────────────────────────────────

printf '\nInstalling plugins from %s/plugins ...\n' "$SCRIPT_DIR"

for p in cairn whetstone temper; do
  if $DRY_RUN; then
    printf '  [dry-run] Would install %s (%s)\n' "$p" "$MODE"
    INSTALLED_PLUGINS="$INSTALLED_PLUGINS $p"
    continue
  fi
  if bash "$SCRIPT_DIR/plugins/$p/install.sh" $SCOPE_ARG --suite \
       > /tmp/aether-install-$p.log 2>&1; then
    printf '  ✓ %s installed\n' "$p"
    INSTALLED_PLUGINS="$INSTALLED_PLUGINS $p"
  else
    printf '  ✗ %s failed to install — see /tmp/aether-install-%s.log\n' "$p" "$p"
    tail -3 "/tmp/aether-install-$p.log" | sed 's/^/      /'
    FAILED=1
  fi
done

# bonsai is the only plugin with real prerequisites and a build step. Probe for
# them and degrade with instructions rather than failing the whole suite.
if [ "$WITH_BONSAI" = false ]; then
  printf '  bonsai: skipped (--no-bonsai)\n'
elif $DRY_RUN; then
  printf '  [dry-run] Would install bonsai (builds py/ and ts/)\n'
  INSTALLED_PLUGINS="$INSTALLED_PLUGINS bonsai"
elif ! command -v uv &>/dev/null || ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
  printf '  bonsai: skipped — needs uv, node and npm.\n'
  printf '          Install them, then run:  bash %s/plugins/bonsai/install.sh --suite\n' "$SCRIPT_DIR"
else
  printf '  bonsai: building py/ and ts/, this takes a minute...\n'
  if bash "$SCRIPT_DIR/plugins/bonsai/install.sh" --suite \
       > /tmp/aether-install-bonsai.log 2>&1; then
    printf '  ✓ bonsai installed\n'
    INSTALLED_PLUGINS="$INSTALLED_PLUGINS bonsai"
  else
    printf '  ✗ bonsai failed to install — see /tmp/aether-install-bonsai.log\n'
    tail -3 /tmp/aether-install-bonsai.log | sed 's/^/      /'
    FAILED=1
  fi
fi

# Safety net for machines that still carry hooks from a pre-suite install.
if ! $DRY_RUN && [ -f "$SETTINGS_FILE" ]; then
  _json_remove_stale_hooks "$SETTINGS_FILE" || true
fi

# ── Step 4: Install enforce-suite.sh and the gates it sources ────────────────

printf '\nInstalling suite hook...\n'

if $DRY_RUN; then
  printf '  [dry-run] Would install enforce-suite.sh to %s\n' "$HOOK_DEST"
  printf '  [dry-run] Would copy gates for:%s to %s\n' "$INSTALLED_PLUGINS" "$GATE_DEST"
  printf '  [dry-run] Would register PreToolUse hook (matcher: Bash|Write|Edit|MultiEdit)\n'
else
  mkdir -p "$HOOK_DIR" "$GATE_DEST"
  cp "$SCRIPT_DIR/hooks/enforce-suite.sh" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"
  printf '  ✓ enforce-suite.sh installed to %s\n' "$HOOK_DEST"

  # Copy a gate only for a plugin that actually installed, so the suite never
  # advises tools the user does not have. Stale gates from a previous run are
  # cleared first.
  rm -f "$GATE_DEST"/enforce-*.sh
  for p in $INSTALLED_PLUGINS; do
    src="$SCRIPT_DIR/plugins/$p/hooks/enforce-$p.sh"
    if [ -f "$src" ]; then
      cp "$src" "$GATE_DEST/enforce-$p.sh"
      chmod +x "$GATE_DEST/enforce-$p.sh"
    fi
  done
  printf '  ✓ gates installed to %s (%s)\n' "$GATE_DEST" "$(ls "$GATE_DEST" | wc -l | tr -d ' ') files"

  _json_register_suite_hook "$SETTINGS_FILE" "$HOOK_DEST" && \
    printf '  ✓ PreToolUse hook registered in %s\n' "$SETTINGS_FILE"
fi

# ── Step 5: Write permissions ─────────────────────────────────────────────────

printf '\nUpdating permissions...\n'

if $DRY_RUN; then
  printf '  [dry-run] Would add permissions to %s\n' "$SETTINGS_FILE"
else
  _json_add_perms "$SETTINGS_FILE" && \
    printf '  ✓ Permissions (Bash, Read, Write, mcp__bonsai-py__*, mcp__bonsai-ts__*) added\n'
fi

# ── Step 6: Install aether CLI ────────────────────────────────────────────────

printf '\nInstalling aether CLI...\n'

if $DRY_RUN; then
  printf '  [dry-run] Would install aether CLI to %s/aether\n' "$CLI_DIR"
else
  mkdir -p "$CLI_DIR"
  cp "$SCRIPT_DIR/bin/aether" "$CLI_DIR/aether"
  chmod +x "$CLI_DIR/aether"
  printf '  ✓ aether CLI installed to %s/aether\n' "$CLI_DIR"
  if [ "$MODE" = "global" ] && ! echo "$PATH" | grep -q "$CLI_DIR"; then
    printf '  Note: add %s to your PATH to use the aether command\n' "$CLI_DIR"
  fi
fi

# ── Step 7: Inject CLAUDE.md block ───────────────────────────────────────────

if [ "$WITH_CLAUDE_MD" = true ]; then
  printf '\nInjecting CLAUDE.md block...\n'
  if $DRY_RUN; then
    printf '  [dry-run] Would inject templates/CLAUDE.md into %s\n' "$CLAUDE_FILE"
  else
    _backup "$CLAUDE_FILE"

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
  fi
fi

# ── Step 8: Write install manifest ───────────────────────────────────────────

if ! $DRY_RUN; then
  mkdir -p "$(dirname "$MANIFEST")"
  cat > "$MANIFEST" <<MANIFEST_EOF
version=$VERSION
scope=$MODE
hook=$HOOK_DEST
gates=$GATE_DEST
repo=$SCRIPT_DIR
claude_md=$WITH_CLAUDE_MD
bonsai=$WITH_BONSAI
plugins=$(echo $INSTALLED_PLUGINS)
MANIFEST_EOF
  printf '\n  ✓ Manifest written to %s\n' "$MANIFEST"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf '\n'
if $DRY_RUN; then
  printf 'Dry run complete. Run without --dry-run to apply.\n'
  exit 0
fi

if [ "$FAILED" -ne 0 ]; then
  printf 'aether v%s installed with errors — see the ✗ lines above.\n' "$VERSION"
  exit 1
fi

if [ "$MODE" = "global" ]; then
  printf 'aether v%s installed globally.\n' "$VERSION"
  printf 'Restart Claude Code to activate.\n\n'
  printf 'Run: aether status\n'
else
  printf 'aether v%s installed for this project.\n' "$VERSION"
  printf 'Restart Claude Code to activate.\n\n'
  printf 'Tips:\n'
  printf '  Global install:        bash install.sh --global\n'
  printf '  With CLAUDE.md rules:  bash install.sh --claude-md\n'
  printf '  Dry run:               bash install.sh --dry-run\n'
fi

printf '\nKeep this clone at %s — bonsai registers its MCP servers by absolute path.\n' "$SCRIPT_DIR"
