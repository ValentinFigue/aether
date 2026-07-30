#!/usr/bin/env bash
# tests/test_project.sh — [project:<path>] areas, and `aether check`.
#
# Order matters here. The trust assertion comes first because a path section used to
# bypass the gate entirely, and the regression guard comes second because the whole
# safety argument for this feature is "a repo with no path sections is unaffected".
# Everything else is behaviour.
#
# Commands are stubs — `true`, `false`, `pwd`. pimento's real toolchains need uv, bun
# and postgres, so exercising those is a manual step, not something to pretend runs
# here.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$REPO/tests/lib.sh"

CLI="$REPO/bin/aether"
LIB="$REPO/hooks/aether-config.sh"

TMPS=()
mk() { local d; d=$(mktemp -d); TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# <home> <proj> <section> <key>
cfg() { ( cd "$2" && HOME="$1" bash -c ". '$LIB'; aether_cfg_get \"\$1\" \"\$2\"" _ "$3" "$4" ); }
# <home> <proj> args…
at()  { ( cd "$2" && env HOME="$1" bash "$CLI" "${@:3}" 2>&1 ); }
trust_it() { ( cd "$2" && env HOME="$1" bash "$CLI" trust >/dev/null 2>&1 ); }

# ── 1. trust covers every area, not just [project] ───────────────────────────
# The gate was `[ "$section" = project ]`, an equality test — so [project:web]
# returned its commands from an untrusted repo. Harmless only while nothing read
# them, and `aether check` is exactly something that reads them.
suite "trust covers project:<path>"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether"
cat > "$P/.aether/config" <<'EOF'
[project]
test: ROOT

[project:web]
test: WEB
EOF
assert_eq "" "$(cfg "$H" "$P" project test)"     "[project] is withheld when untrusted"
assert_eq "" "$(cfg "$H" "$P" project:web test)" "[project:web] is withheld too"
trust_it "$H" "$P"
assert_eq "ROOT" "$(cfg "$H" "$P" project test)"     "[project] resolves once trusted"
assert_eq "WEB"  "$(cfg "$H" "$P" project:web test)" "[project:web] resolves once trusted"

# A hand edit revokes both, not just the root section.
printf 'lint: SNEAKY\n' >> "$P/.aether/config"
assert_eq "" "$(cfg "$H" "$P" project:web test)" "a hand edit re-gates the areas as well"

# And `aether check` must refuse rather than run anything.
H2=$(mk); P2=$(mk); mkdir -p "$H2/.aether" "$P2/.aether" "$P2/web"
printf '[project:web]\ntest: touch %s/PWNED\n' "$P2" > "$P2/.aether/config"
out=$(at "$H2" "$P2" check --all); e=$?
assert_exit 1 "$e" "check exits 1 on an untrusted repo"
# Specific enough that the usage text — which also mentions `aether trust` — cannot
# satisfy it. An unknown subcommand must not look like a refusal.
assert_contains "$out" "untrusted" "…and says the repo is untrusted"
assert_contains "$out" "Review .aether/config" "…telling you to review it first"
[ -f "$P2/PWNED" ] && fail "check ran nothing while untrusted" "the command executed" \
                   || pass "check ran nothing while untrusted"

# `aether trust` must show what you are consenting to — from every area. Reading only
# [project] showed nothing at all on a monorepo whose commands all live in areas,
# which turns the preview into a formality: the one thing it exists to prevent.
suite "the trust preview covers every area"
H3=$(mk); P3=$(mk); mkdir -p "$H3/.aether" "$P3/.aether" "$P3/web" "$P3/backend"
cat > "$P3/.aether/config" <<'EOF'
[project:web]
lint: bun run lint-ci
typecheck: bun run tsc

[project:backend]
test: uv run pytest
check.lockfile: uv lock --check
EOF
out=$(at "$H3" "$P3" trust)
assert_contains "$out" "Commands the critics would run" "the preview lists commands"
for c in "web/lint" "web/typecheck" "backend/test" "backend/check.lockfile"; do
  assert_contains "$out" "$c" "…including $c"
done
assert_contains "$out" "bun run tsc" "…with the command itself, not just the key"

# ── 2. the regression guard ──────────────────────────────────────────────────
# The entire safety argument is that a repo with no path sections is unaffected.
suite "a repo with no path areas is unchanged"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether"
printf '[project]\ntest: true\nlint: true\ncoverage_min: 80\n' > "$P/.aether/config"
trust_it "$H" "$P"
assert_eq "true" "$(cfg "$H" "$P" project test)" "[project] still resolves exactly as before"
assert_eq "80"   "$(cfg "$H" "$P" project coverage_min)" "…including non-command keys"
out=$(at "$H" "$P" check --all --raw)
assert_contains "$out" "project	test	ok"  "check runs the root area"
assert_contains "$out" "project	lint	ok"  "…every command key it sets"
case "$out" in *"project:"*) fail "no phantom areas appear" "$out" ;; *) pass "no phantom areas appear" ;; esac

# ── 3. section names are normalised ──────────────────────────────────────────
suite "path normalisation"
for spelling in 'web' './web' 'web/'; do
  H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/web"
  printf '[project:%s]\ntest: true\n' "$spelling" > "$P/.aether/config"
  trust_it "$H" "$P"
  assert_eq "true" "$(cfg "$H" "$P" project:web test)" "[project:$spelling] reads as project:web"
done

# ── 4. commands do not inherit; other keys do ────────────────────────────────
# A command in [project] is written relative to the repo root, so inheriting it into
# an area has no correct working directory. The first draft of the plan got this
# wrong in exactly this way.
suite "no command inheritance"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/web"
cat > "$P/.aether/config" <<'EOF'
[project]
test: ROOT-TEST
coverage_min: 90

[project:web]
lint: WEB-LINT
EOF
trust_it "$H" "$P"
assert_eq ""         "$(cfg "$H" "$P" project:web test)" "a command key is not inherited"
assert_eq "WEB-LINT" "$(cfg "$H" "$P" project:web lint)" "the area's own command resolves"
# Through the CLI, which is where the area rule lives — the library resolves one
# section exactly, and keeping it that way is what keeps the gate path cheap.
assert_eq "90" "$(at "$H" "$P" config get project:web.coverage_min)" \
  "a non-command key IS inherited"
assert_eq ""   "$(at "$H" "$P" config get project:web.test)" \
  "…and a command key still is not, through the CLI too"
out=$(at "$H" "$P" check web/x.ts --raw)
case "$out" in *ROOT-TEST*) fail "the root command is not run inside an area" "$out" ;;
               *) pass "the root command is not run inside an area" ;; esac

# ── 5. longest prefix wins ───────────────────────────────────────────────────
suite "longest matching prefix"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/plugins/bonsai/py"
cat > "$P/.aether/config" <<'EOF'
[project]
test: true

[project:plugins]
test: true

[project:plugins/bonsai/py]
test: true
EOF
trust_it "$H" "$P"
out=$(at "$H" "$P" check plugins/bonsai/py/mod.py --raw)
n=$(printf '%s\n' "$out" | grep -c '	test	' || true)
assert_eq "1" "$n" "the deepest area runs, exactly once"
assert_contains "$out" "project:plugins/bonsai/py" "…and it is the deepest one"
case "$out" in *"project:plugins	test	ok"*) fail "the shallower area does not also run" "$out" ;;
               *) pass "the shallower area does not also run" ;; esac

# ── 6. files outside every area fall to [project] ────────────────────────────
suite "the root area is the fallback"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/web"
printf '[project]\ntest: true\n\n[project:web]\ntest: true\n' > "$P/.aether/config"
trust_it "$H" "$P"
out=$(at "$H" "$P" check README.md --raw)
assert_contains "$out" "project	test	ok" "a file in no area runs the root area"
case "$out" in *"project:web	test	ok"*) fail "…and not the areas it does not touch" "$out" ;;
               *) pass "…and not the areas it does not touch" ;; esac

# ── 7. commands run in their own directory ───────────────────────────────────
suite "working directory"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/web" "$P/api"
cat > "$P/.aether/config" <<'EOF'
[project:web]
test: test "$(basename "$PWD")" = web

[project:api]
test: test "$(basename "$PWD")" = api
EOF
trust_it "$H" "$P"
out=$(at "$H" "$P" check --all --raw)
assert_contains "$out" "project:web	test	ok" "web's command ran in web/"
assert_contains "$out" "project:api	test	ok" "api's command ran in api/"

# An area whose directory is gone must be reported, not crash on cd.
rm -rf "$P/api"
out=$(at "$H" "$P" check --all)
assert_contains "$out" "api" "a missing area directory is named"
case "$out" in *"No such file"*|*"cd:"*) fail "…without a raw cd error" "$out" ;;
               *) pass "…without a raw cd error" ;; esac

# ── 8. check.<name> ──────────────────────────────────────────────────────────
# CI runs things that are not test/lint/typecheck — lockfile checks, migration
# head counts. Without this they would be silently dropped from any config.
suite "check.<name> escape hatch"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/backend"
cat > "$P/.aether/config" <<'EOF'
[project:backend]
test: true
check.lockfile: true
check.migrations: false
EOF
trust_it "$H" "$P"
out=$(at "$H" "$P" check --all --raw)
assert_contains "$out" "check.lockfile	ok"    "a passing named check is reported"
assert_contains "$out" "check.migrations	fail" "…and a failing one"
n=$(printf '%s\n' "$out" | grep -c '	' || true)
assert_eq "3" "$n" "a failing check does not abort the ones after it"
out=$(at "$H" "$P" config doctor)
case "$out" in *"check.lockfile — unknown key"*) fail "check.* is not an unknown key" "$out" ;;
               *) pass "check.* is not an unknown key" ;; esac

# ── 9. --raw is the critics' contract ────────────────────────────────────────
suite "--raw is stable"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/web" "$P/api"
printf '[project:web]\ntest: true\n\n[project:api]\ntest: false\n' > "$P/.aether/config"
trust_it "$H" "$P"
out=$(at "$H" "$P" check --all --raw)
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n=$(printf '%s' "$line" | awk -F'\t' '{print NF}')
  [ "$n" -eq 4 ] || fail "every --raw line has 4 tab-separated fields" "got $n: $line"
done <<EOF
$out
EOF
pass "every --raw line has 4 tab-separated fields"
st=$(printf '%s\n' "$out" | awk -F'\t' '{print $3}' | sort -u | tr '\n' ' ')
case "$st" in *ok*|*fail*|*skipped*) pass "status vocabulary is ok|fail|skipped (saw: ${st% })" ;;
              *) fail "status vocabulary is ok|fail|skipped" "saw: $st" ;; esac
out=$(at "$H" "$P" check web/x.ts --raw)
assert_contains "$out" "skipped" "an untouched area is reported as skipped, not omitted"

# ── 10. config show and doctor understand areas ──────────────────────────────
suite "config show and doctor"
H=$(mk); P=$(mk); mkdir -p "$H/.aether" "$P/.aether" "$P/web" "$P/backend"
cat > "$P/.aether/config" <<'EOF'
[project:web]
lint: true

[project:backend]
test: definitely-not-a-real-binary
EOF
trust_it "$H" "$P"
out=$(at "$H" "$P" config show project)
assert_contains "$out" "project:web"     "config show project lists every area"
assert_contains "$out" "project:backend" "…all of them"
out=$(at "$H" "$P" config show project:web)
case "$out" in *"project:backend"*) fail "config show project:web lists one area" "$out" ;;
               *) pass "config show project:web lists one area" ;; esac
out=$(at "$H" "$P" config doctor)
assert_contains "$out" "not on PATH" "doctor checks binaries inside an area"
assert_contains "$out" "backend"     "…naming the area"
case "$out" in *"lint"*"not on PATH"*) fail "doctor does not flag the area that is fine" "$out" ;;
               *) pass "doctor does not flag the area that is fine" ;; esac

# ── a nested install becomes an area ────────────────────────────────────────
# Before [project:<path>] existed, a subfolder with its own toolchain meant running
# `aether install` inside it — which is what pimento did for backend/, leaving the
# other two thirds of the repo unconfigured.
suite "nested install folds into the parent"
H=$(mk); R=$(mk)
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t )
mkdir -p "$R/backend/.aether" "$R/web" "$R/.aether"
printf '[project]\ntest: uv run pytest\nlint: ruff check ./\n\n[git]\nticket: NESTED-\\d+\n' \
  > "$R/backend/.aether/config"
printf '[critique-diff]\nBackend prose.\n' > "$R/backend/.aether/rules.md"
printf '[git]\nticket: PARENT-\\d+\n' > "$R/.aether/config"
( cd "$R" && printf 'x\n' > web/a.ts && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )

out=$( cd "$R" && env HOME="$H" bash "$CLI" migrate 2>&1 )
assert_contains "$out" "project:backend" "the nested install is folded into an area"
body=$(cat "$R/.aether/config")
assert_contains "$body" "[project:backend]"    "…as its own section"
assert_contains "$body" "uv run pytest"        "…carrying its commands"
assert_contains "$body" "PARENT-" "the parent's own [git] value is kept"
case "$body" in *"NESTED-"*) fail "the nested [git] value is not merged in" "$body" ;;
               *) pass "the nested [git] value is not merged in" ;; esac
assert_contains "$out" "differs — kept the parent" "…and the conflict is reported, not silent"
[ -d "$R/backend/.aether.bak" ] && pass "the nested install is backed up, not deleted" \
                               || fail "the nested install is backed up, not deleted"
[ -d "$R/backend/.aether" ] && fail "…and moved out of the way" || pass "…and moved out of the way"
assert_contains "$(cat "$R/.aether/rules.md" 2>/dev/null)" "Backend prose." \
  "its rules.md is carried across"

out=$( cd "$R" && env HOME="$H" bash "$CLI" migrate 2>&1 )
case "$out" in *"project:backend"*) fail "re-running migrate is a no-op" "$out" ;;
               *) pass "re-running migrate is a no-op" ;; esac

# A separate git work tree in a subdirectory is not an area of this repo.
R2=$(mk)
( cd "$R2" && git init -q . && git config user.email t@t && git config user.name t
  printf 'x\n' > a.txt && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
mkdir -p "$R2/vendor/.aether"
( cd "$R2/vendor" && git init -q . )
printf '[project]\ntest: their-test\n' > "$R2/vendor/.aether/config"
out=$( cd "$R2" && env HOME="$H" bash "$CLI" migrate 2>&1 )
case "$(cat "$R2/.aether/config" 2>/dev/null)" in
  *"their-test"*) fail "a vendored repo is not folded in" "$(cat "$R2/.aether/config")" ;;
  *) pass "a vendored repo is not folded in" ;;
esac
[ -d "$R2/vendor/.aether" ] && pass "…and is left where it is" \
                           || fail "…and is left where it is"

summary
