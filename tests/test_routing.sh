#!/usr/bin/env bash
# Routing: rendering the canonical role set, policy binding, skill delivery,
# instruction budget and output ownership.
#
# What is asserted is what the renderer WRITES and REFUSES to write. That a
# runtime then honours a rendered file is a separate claim, recorded with its
# evidence in docs/runtime-capabilities.md.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

RENDER="python3 $REPO_ROOT/scripts/routing/render.py"
CFG="$REPO_ROOT/config/routing/models.example.yaml"
EXPECTED_ROLES=14

if ! command -v python3 >/dev/null 2>&1; then
  echo "    FAIL  python3 unavailable — the renderer cannot be exercised"
  exit 1
fi

# --- the whole canonical role set renders -------------------------------------
T="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$T" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "claude render exits 0" 0 "$rc"
n="$(find "$T/agents" -name '*.md' | grep -c .)"
assert_eq "all $EXPECTED_ROLES canonical roles are rendered" "$EXPECTED_ROLES" "$n"
assert_contains "…driven by the contract version" "$out" "contract: 0.2.0"
for role in orchestrator planning review security documentation critical-thinking; do
  assert_file_exists "role $role rendered" "$T/agents/$role.md"
done

T2="$(sandbox_new)"
out="$($RENDER --runtime codex --target "$T2" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "codex render exits 0" 0 "$rc"
n="$(find "$T2/agents" -name '*.toml' | grep -c .)"
assert_eq "all $EXPECTED_ROLES roles render for codex too" "$EXPECTED_ROLES" "$n"

# --- contract content is carried into the instructions ------------------------
body="$(cat "$T/agents/review.md")"
assert_contains "purpose carried"            "$body" "Assess correctness and maintainability"
assert_contains "responsibilities carried"   "$body" "## Responsibilities"
assert_contains "boundaries carried"         "$body" "Do not edit implementation during review"
assert_contains "inputs carried"             "$body" "## Inputs"
assert_contains "outputs carried"            "$body" "## Outputs"
assert_contains "completion criteria carried" "$body" "## Completion criteria"
assert_contains "permission ceiling stated"  "$body" "Permission ceiling: read, write, execute"
assert_contains "canonical skill refs kept"  "$body" "skills/review-code/SKILL.md"
assert_contains "provenance recorded"        "$body" "source: roles/review.json"
assert_contains "contract version recorded"  "$body" "contract 0.2.0"

# --- model policy binding -----------------------------------------------------
assert_contains "policy resolved to a configured model" "$body" "model: sonnet"
assert_contains "…and the policy is named in provenance" "$body" "model policy: default -> sonnet"
toml="$(cat "$T2/agents/review.toml")"
assert_contains "codex model bound"      "$toml" 'model = "gpt-5.6"'
assert_contains "codex reasoning bound"  "$toml" 'model_reasoning_effort = "medium"'
assert_contains "codex sandbox bound"    "$toml" 'sandbox_mode = "read-only"'

# --- skill delivery under tool restrictions -----------------------------------
# Measured: a Claude sub-agent given an explicit tools list without `Skill` has
# no Skill tool, so referencing a skill would deliver nothing. The renderer
# preloads the canonical body instead of widening the permission.
assert_contains "restricted role declares its tool limit" "$body" "tools: Read, Grep, Glob, Bash"
assert_contains "…and preloads its skills"                "$body" "skill delivery: preload"
assert_contains "…with the canonical body inlined"        "$body" "begin canonical skill: skills/review-code/SKILL.md"
assert_contains "…traceable by hash"                      "$body" "sha256="
n_inlined="$(grep -c 'begin canonical skill' "$T/agents/review.md")"
assert_eq "every declared skill is delivered" 2 "$n_inlined"

plain="$(cat "$T/agents/planning.md")"
assert_contains "an unrestricted role keeps its Skill tool" "$plain" "skill delivery: reference"
assert_not_contains "…and is not bloated with inlined copies" "$plain" "begin canonical skill"

# --- unresolved policies and bad contracts are configuration errors -----------
E="$(sandbox_new)"
printf 'version: 2\npolicies:\n  default:\n    claude:\n      model: sonnet\n' > "$E/partial.yaml"
out="$($RENDER --runtime claude --target "$E" --config "$E/partial.yaml" --apply 2>&1)"; rc=$?
assert_eq "an unbound policy is a configuration error" 2 "$rc"
assert_contains "…naming the missing binding" "$out" "escalated"
assert_contains "…and refusing to guess"      "$out" "no model is guessed"

printf 'version: 1\npolicies:\n  default:\n    claude:\n      model: sonnet\n' > "$E/v1.yaml"
out="$($RENDER --runtime claude --target "$E" --config "$E/v1.yaml" --apply 2>&1)"; rc=$?
assert_eq "an old routing schema version is rejected" 2 "$rc"

out="$($RENDER --runtime claude --target "$E" --config "$E/absent.yaml" --apply 2>&1)"; rc=$?
assert_eq "a missing routing file is a configuration error" 2 "$rc"
assert_contains "…explaining that the contract defines no model names" "$out" "no model names"

# --- a mutated distribution root ----------------------------------------------
R="$(sandbox_new)/root"
mkdir -p "$R"
cp -r "$REPO_ROOT/roles" "$REPO_ROOT/contracts" "$REPO_ROOT/skills" "$REPO_ROOT/rules" "$R/"

python3 -c "
import json,sys
p=sys.argv[1]+'/roles/catalog.json'
d=json.load(open(p,encoding='utf-8')); d['contract_version']='0.3.0'
json.dump(d,open(p,'w',encoding='utf-8'))" "$R"
out="$($RENDER --runtime claude --target "$E" --root "$R" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "an unsupported contract version is rejected" 2 "$rc"
assert_contains "…without reinterpreting it" "$out" "will not reinterpret"

python3 -c "
import json,sys
p=sys.argv[1]+'/roles/catalog.json'
d=json.load(open(p,encoding='utf-8')); d['contract_version']='0.2.0'
json.dump(d,open(p,'w',encoding='utf-8'))
p=sys.argv[1]+'/roles/review.json'
d=json.load(open(p,encoding='utf-8')); d['skill_refs']=['skills/not-a-real-skill/SKILL.md']
json.dump(d,open(p,'w',encoding='utf-8'))" "$R"
out="$($RENDER --runtime claude --target "$E" --root "$R" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "a missing skill reference is rejected" 2 "$rc"
assert_contains "…and named" "$out" "does not exist"

python3 -c "
import json,sys
p=sys.argv[1]+'/roles/review.json'
d=json.load(open(p,encoding='utf-8')); d['skill_refs']=['../../etc/passwd']
json.dump(d,open(p,'w',encoding='utf-8'))" "$R"
out="$($RENDER --runtime claude --target "$E" --root "$R" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "a traversing reference is rejected" 2 "$rc"
assert_contains "…as a containment failure" "$out" "no traversal"

# --- the instruction budget is never silently exceeded ------------------------
B="$(sandbox_new)"
sed 's/^  review:$/  review:\n    skill_delivery: preload/' "$CFG" > "$B/preload.yaml"
out="$($RENDER --runtime codex --target "$B" --config "$B/preload.yaml" --budget 4096 --apply 2>&1)"; rc=$?
assert_eq "an over-budget role fails the run" 2 "$rc"
assert_contains "…naming the limit"          "$out" "instruction budget"
assert_contains "…and refusing truncation"   "$out" "never truncated"
assert_file_absent "…having written nothing" "$B/agents/review.toml"

# --- idempotency, drift and ownership -----------------------------------------
out="$($RENDER --runtime claude --target "$T" --config "$CFG" --apply 2>&1)"
assert_contains "re-render is a no-op" "$out" "unchanged"
out="$($RENDER --runtime claude --target "$T" --config "$CFG" --check 2>&1)"; rc=$?
assert_eq "check passes on a fresh render" 0 "$rc"

printf '\nedited by hand\n' >> "$T/agents/review.md"
out="$($RENDER --runtime claude --target "$T" --config "$CFG" --check 2>&1)"; rc=$?
assert_ne "check fails once a rendered file drifts" 0 "$rc"
assert_contains "…and says it is stale" "$out" "stale"

C="$(sandbox_new)"
mkdir -p "$C/agents"
printf 'my own agent\n' > "$C/agents/review.md"
out="$($RENDER --runtime claude --target "$C" --config "$CFG" --apply 2>&1)"; rc=$?
assert_ne "a collision fails the run" 0 "$rc"
assert_contains "…and is reported" "$out" "COLLISION"
assert_eq "…and the user's file is untouched" "my own agent" "$(cat "$C/agents/review.md")"

out="$($RENDER --runtime claude --target "$T" --config "$CFG" --remove --apply 2>&1)"
assert_contains "the edited file is kept on removal" "$out" "KEPT (modified since render)"
assert_file_exists "…and still on disk"              "$T/agents/review.md"
assert_file_absent "an unmodified rendered file is removed" "$T/agents/planning.md"

t_summary
