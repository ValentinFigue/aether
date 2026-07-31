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

## Turning a plugin off for good

Bypass markers are per-command. To silence a gate persistently, set `enabled: false`
in its config instead — `~/.aether/config` for every project, or `.aether/config`
in one repository, which overrides the global value for that key alone:

```bash
aether disable global                        # all four, everywhere
aether config set cairn.enabled false        # just cairn, just here
```

Both write an `[<plugin>]` section in the one config file for that scope, so the
setting is visible beside every other. `aether status` shows the resolved state
for each plugin, and `aether config show cairn` shows where the value came from.

## Where the marker has to be

A marker only counts in a **trailing comment**: after a `#` that starts a word and is
outside quotes, with nothing but further markers behind it.

```bash
git commit -m wip  # temper:skip                  bypassed
git commit -m wip  #temper:skip                   bypassed — no space needed
git commit -m wip  # temper:skip cairn:skip       both bypassed

git commit -m "docs: explain # temper:skip"       NOT bypassed — inside the message
git commit -m wip  # temper:skip && rm -rf /      NOT bypassed — not the trailing token
git commit -m wip  # TEMPER:skip                  NOT bypassed — case-sensitive
```

Until v1.5.0 every gate grepped for its own marker anywhere in the command, so a
commit *documenting* the marker turned the suite off:

```bash
git commit -m "docs: explain the # aether:skip marker"   # all four gates went silent
```

There is now one implementation — `aether_bypassed` in `hooks/aether-config.sh` — and
`tests/test_hookcost.sh` asserts all four gates and the dispatcher give the same answer
for the same string. They used to spell the whitespace three different ways.

## Threat model

**Everything here is advisory, and not only because of the marker.** Two separate
reasons, and the second is the stronger one:

1. The agent writes the commands the hook inspects, so the agent can write the marker.
2. **Nothing exits 2.** Every path in `enforce-suite.sh` exits 0 or 1, and
   `tests/acceptance.sh` fails the build if any payload makes it exit 2 — because a
   corrupt or half-written gate file would otherwise lock you out of every command you
   type. Failing open is a deliberate trade, not an oversight. Strict mode does not change
   it: escalation travels as a decision printed on **exit 0**, so breakage — which exits 2
   — can neither be mistaken for a deliberate stop nor forge one.

Nothing here is a permission boundary, and it is not trying to be — the suite exists to
make the right thing the default when nobody is paying attention, not to stop someone
who has decided otherwise.

What that buys, and what it does not:

| | |
|---|---|
| Catches | forgetting to review a large diff; a plan that drifted from its critique; a weak commit message nobody would defend |
| Does not catch | a deliberate bypass, by a person or an agent |
| Not a defence against | a hostile agent, a compromised dependency, or anyone with write access to `~/.claude/settings.json` |

Two consequences worth stating plainly:

- **The marker has to be hard to trip over by accident, not hard to type.** That is why
  it must be a trailing comment. A marker that fires on any substring is not more
  secure, only more surprising — it silences commits that merely mention it.
- **Two verdicts are exempt from the nudge budget.** temper's unreviewed-push and
  critical-path-commit messages print in full, alone, and suppress every other nudge. A
  nudge you miss costs you a better commit message; one of these you miss is unreviewed
  code on a shared branch. The unreviewed-push verdict now also requires *evidence* —
  `aether review status` — rather than firing on every push, because a verdict that is
  always the same carries no information and gets ignored.

**Strict mode changes what those two do.** With `strict: blocks`, they stop being printed
and become a permission prompt — and **the agent cannot answer that prompt.** You do. It
is the one mechanism here that takes the decision away from the thing writing the command.

```
[temper]
strict: off      # off | blocks — default off, read from ~/.aether/config only
```

Global-only on purpose: a project-level switch would sit in the tree the agent is editing,
and the value of this is that turning it off is a write outside the work, which is
conspicuous. It escalates rather than refuses, so approving the prompt *is* the bypass —
no separate marker to learn.

What it still does not do: the agent can edit `~/.aether/config`, deregister the hook, or
route a command so the matcher misses it. Strict mode raises the cost of a bypass from
*appending a comment* — invisible, deniable, one token — to *editing a file outside the
repository*. A real change, and not a boundary.

**If you need an actual gate, run it where the agent cannot edit it:** a pre-receive
hook on the server, or a required CI check. That is the boundary; this file is not.

## One nudge at a time

Since v1.5.0 the hook prints **one nudge per tool call** — the earliest lifecycle
stage with something to say — and names the rest on a single line:

```
Whetstone: a plan exists but has not been critiqued yet.
  .claude/plans/p.md
  Run /critique-plan before committing to surface blockers now.
  Append  # whetstone:skip  to your git command to bypass.
  + temper and cairn also had notes — `aether status --notes` to see them.
```

One `git commit` used to print fifteen lines from three plugins. Nudge fatigue is how
guardrails die: the fastest way to stop the noise becomes `# aether:skip` on
everything, which is worse than any single nudge.

temper's two high-risk verdicts are exempt. Each prints in full and alone, and the
nudges beside it are dropped rather than appended — being told your push had no review
is the only thing worth reading at that moment. Nothing announces the drop, so
`aether status --notes` shows what was held back either way. Notes live in `.aether/out/.notes` in the project, and
are overwritten on every tool call.

## Notes

- Multiple per-plugin markers can appear on the same line.
- `# aether:skip` and `# suite:skip` are equivalent and silence every gate.
- Bypass markers do not affect runtime execution — bash treats `#` comments as no-ops.
- The markers work identically whether a plugin runs standalone or under the suite.
  Each gate is defined once, in its own plugin's `hooks/enforce-<plugin>.sh`, and
  `enforce-suite.sh` sources that same file rather than keeping a second copy — so a
  marker can never be honoured by one and ignored by the other.
- Since v1.5.0 both `# aether:skip` and `# suite:skip` are resolved by
  `aether_bypassed`, which every gate calls, so both work standalone as well as under
  the suite. Before that, `# aether:skip` was resolved only by the dispatcher and did
  nothing for a plugin installed on its own.
