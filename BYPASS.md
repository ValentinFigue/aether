# Bypass reference

All suite hooks respect the following bypass markers. Append them as bash comments — bash ignores them at runtime so the command still executes.

## Suite-wide bypass (silence all hooks)

```bash
# aether:skip
# suite:skip    (alias — works with standalone plugin installs too)
```

## Per-plugin bypass

```bash
# whetstone:skip   silence whetstone gate only
# bonsai:skip      silence bonsai gate only
# temper:skip      silence temper gate only
# cairn:skip       silence cairn gate only
```

## Examples

```bash
# Skip all hooks for a quick WIP push
git push origin main   # aether:skip

# Skip only temper (let cairn still nudge)
git commit -m "chore: bump deps"   # temper:skip

# Skip only cairn (let temper still gate)
git commit -m "fix: correct null check in parser"   # cairn:skip

# Skip temper and cairn, keep whetstone
git commit -m "refactor: extract helper"   # temper:skip cairn:skip

# Skip bonsai nudge for a legitimate raw grep
grep -r "TODO" ./src   # bonsai:skip
```

## Notes

- Bypass markers are detected as inline comments anywhere in the command string.
- Multiple per-plugin markers can appear on the same line.
- `# aether:skip` and `# suite:skip` are equivalent and silence every gate.
- Bypass markers do not affect runtime execution — bash treats `#` comments as no-ops.
