#!/usr/bin/env bash
# Role-to-model routing: schema validation, ownership, and the fallback policy.
#
# What is asserted here is what the renderer WRITES and REFUSES to write. That a
# runtime then honours the rendered file is a separate, runtime-level claim —
# recorded with its evidence in docs/runtime-capabilities.md.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

FIX="$REPO_ROOT/tests/fixtures/routing"
RENDER="python3 $REPO_ROOT/scripts/routing/render.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "    skip  python3 unavailable — routing renderer not exercised"
  t_summary
  exit $?
fi

# --- renders both runtimes from one source ------------------------------------
T="$(sandbox_new)"
out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T" 2>&1)"; rc=$?
assert_eq "dry run exits 0" 0 "$rc"
assert_file_absent "dry run writes nothing" "$T/agents/reviewer.md"
assert_contains "dry run names the resolved model" "$out" "model=opus"

out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T" --apply 2>&1)"; rc=$?
assert_eq "claude render exits 0" 0 "$rc"
assert_file_exists "claude agent written" "$T/agents/reviewer.md"
body="$(cat "$T/agents/reviewer.md")"
assert_contains "…with the tier's model"      "$body" "model: opus"
assert_contains "…with the restricted tools"  "$body" "tools: Read, Grep, Glob"
assert_contains "…and the profile's instructions verbatim" "$body" "Report each finding as"
# Claude Code documents no per-agent reasoning key; emitting one would be invention.
assert_not_contains "no invented reasoning key in claude frontmatter" "$body" "reasoning:"

out="$($RENDER --runtime codex --config "$FIX/models.yaml" --target "$T" --apply 2>&1)"; rc=$?
assert_eq "codex render exits 0" 0 "$rc"
body="$(cat "$T/agents/reviewer.toml")"
assert_contains "codex model set"     "$body" 'model = "gpt-5.6"'
assert_contains "codex reasoning set" "$body" 'model_reasoning_effort = "high"'
assert_contains "codex sandbox set"   "$body" 'sandbox_mode = "read-only"'
assert_contains "codex instructions carried over" "$body" "developer_instructions"

# --- idempotent + check -------------------------------------------------------
out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T" --apply 2>&1)"
assert_contains "re-render is a no-op" "$out" "unchanged"
out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T" --check 2>&1)"; rc=$?
assert_eq "check passes on a fresh render" 0 "$rc"

printf '\nedited by hand\n' >> "$T/agents/reviewer.md"
out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T" --check 2>&1)"; rc=$?
assert_ne "check fails when the rendered file drifted" 0 "$rc"
assert_contains "…and says it is stale" "$out" "stale"

# --- ownership ----------------------------------------------------------------
# A file the renderer did not write is never overwritten, even at the same path.
T2="$(sandbox_new)"
mkdir -p "$T2/agents"
printf 'my own agent\n' > "$T2/agents/reviewer.md"
out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T2" --apply 2>&1)"; rc=$?
assert_ne "collision fails the run" 0 "$rc"
assert_contains "…and is reported" "$out" "COLLISION"
assert_eq "…and the user's file is untouched" "my own agent" "$(cat "$T2/agents/reviewer.md")"

# --- removal removes only what it owns ----------------------------------------
out="$($RENDER --runtime claude --config "$FIX/models.yaml" --target "$T" --remove --apply 2>&1)"
assert_contains "modified file is kept on removal" "$out" "KEPT (modified since render)"
assert_file_exists "…and still on disk" "$T/agents/reviewer.md"
out="$($RENDER --runtime codex --config "$FIX/models.yaml" --target "$T" --remove --apply 2>&1)"
assert_file_absent "unmodified rendered file is removed" "$T/agents/reviewer.toml"

# --- routing is optional ------------------------------------------------------
T3="$(sandbox_new)"
out="$($RENDER --runtime claude --config "$T3/absent.yaml" --target "$T3" --apply 2>&1)"; rc=$?
assert_eq "a missing routing file is not an error" 0 "$rc"
assert_contains "…and says routing is optional" "$out" "routing is optional"

# --- schema errors are fatal, never guessed -----------------------------------
mkerr() { printf '%s\n' "$2" > "$1"; }

E="$(sandbox_new)"
mkerr "$E/no-profile.yaml" 'version: 1
catalog:
  - tier: deep
    claude:
      model: opus
roles:
  - id: reviewer
    tier: deep'
out="$($RENDER --runtime claude --config "$E/no-profile.yaml" --target "$E" --apply 2>&1)"; rc=$?
assert_eq "a role without a profile is a schema error" 2 "$rc"
assert_contains "…and says routing never authors instructions" "$out" "never authors instructions"

# Profile paths are relative to the config file: an absolute POSIX path written
# inside a config is not argv-converted on Windows, so it would not resolve.
mkdir -p "$E/profiles"
cp "$FIX/profiles/reviewer.md" "$E/profiles/reviewer.md"

mkerr "$E/unknown-tier.yaml" 'version: 1
catalog:
  - tier: deep
    claude:
      model: opus
fallback:
  on_unknown_model: deny
roles:
  - id: reviewer
    profile: profiles/reviewer.md
    tier: nonexistent'
out="$($RENDER --runtime claude --config "$E/unknown-tier.yaml" --target "$E" --apply 2>&1)"; rc=$?
assert_eq "an unknown tier is a schema error under deny" 2 "$rc"
assert_contains "…and refuses to substitute silently" "$out" "silent substitution"

mkerr "$E/bad-reasoning.yaml" 'version: 1
catalog:
  - tier: deep
    codex:
      model: gpt-5.6
reasoning:
  default: medium
  levels: [low, medium, high, xhigh]
roles:
  - id: reviewer
    profile: profiles/reviewer.md
    tier: deep
    reasoning: ultra-max'
out="$($RENDER --runtime codex --config "$E/bad-reasoning.yaml" --target "$E" --apply 2>&1)"; rc=$?
assert_eq "an out-of-range reasoning level is a schema error" 2 "$rc"

mkerr "$E/bad-version.yaml" 'version: 99
roles: []'
out="$($RENDER --runtime claude --config "$E/bad-version.yaml" --target "$E" --apply 2>&1)"; rc=$?
assert_eq "an unsupported schema version is fatal" 2 "$rc"

# A profile with no description must not be papered over with a generated one.
mkdir -p "$E/profiles"
printf -- '---\nname: x\n---\n\nbody\n' > "$E/profiles/nodesc.md"
mkerr "$E/nodesc.yaml" 'version: 1
catalog:
  - tier: deep
    claude:
      model: opus
roles:
  - id: reviewer
    profile: profiles/nodesc.md
    tier: deep'
out="$($RENDER --runtime claude --config "$E/nodesc.yaml" --target "$E" --apply 2>&1)"; rc=$?
assert_eq "a profile without a description is fatal" 2 "$rc"
assert_contains "…and refuses to invent one" "$out" "will not invent"

t_summary
