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
assert_contains "…driven by the contract version" "$out" "contract: 0.3.0"
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
assert_contains "contract version recorded"  "$body" "contract 0.3.0"

# --- model policy binding -----------------------------------------------------
assert_contains "policy resolved to a configured model" "$body" "model: sonnet"
assert_contains "…and the policy is named in provenance" "$body" "model policy: default -> sonnet"
toml="$(cat "$T2/agents/review.toml")"
assert_contains "codex model bound"      "$toml" 'model = "gpt-5.6"'
assert_contains "codex reasoning bound"  "$toml" 'model_reasoning_effort = "medium"'
assert_contains "codex sandbox bound"    "$toml" 'sandbox_mode = "read-only"'

# --- tool limits come from an explicit authorization -------------------------
# A role with no authorized permission set renders as a template: the canonical
# profile alone cannot establish an authorized, restricted execution, and a file
# with no tool limit would inherit whatever the parent holds.
plain="$(cat "$T/agents/planning.md")"
assert_contains "an unauthorized role is marked non-executable" "$plain" "NON-EXECUTABLE TEMPLATE"
assert_contains "…and says no authorization was supplied"       "$plain" "tool limit: NONE"
assert_contains "…so its skills are referenced, not preloaded"  "$plain" "skill delivery: reference"

CFG3="$(sandbox_new)"

# An authorized role gets a deterministic limit through the permission-class map,
# and the authorization may sit anywhere between the role's floor and ceiling.
R0="$(sandbox_new)/root"
mkdir -p "$R0"
cp -r "$REPO_ROOT/roles" "$REPO_ROOT/contracts" "$REPO_ROOT/skills" "$REPO_ROOT/rules" "$R0/"

{
  printf 'version: 3
'
  printf 'policies:
  default:
    claude:
      model: sonnet
  escalated:
    claude:
      model: opus
'
  printf 'tool_map:
  claude:
    read: [Read, Grep, Glob]
    write: [Write, Edit]
    execute: [Bash]
'
  printf 'roles:
  review:
    claude:
      permissions: [read, execute]
'
} > "$CFG3/derived.yaml"

TD="$(sandbox_new)"
out="$($RENDER --runtime claude --root "$R0" --target "$TD" --config "$CFG3/derived.yaml" --apply 2>&1)"; rc=$?
assert_eq "an authorized role renders" 0 "$rc"
derived="$(cat "$TD/agents/review.md")"
assert_contains "…with tools derived from the authorized classes" "$derived" "tools: Read, Grep, Glob, Bash"
assert_contains "…attributed to the authorization"                "$derived" "derived from the authorized permissions"
# Measured on Claude Code 2.1.220: an explicit tool list without Skill removes
# the Skill tool, and a control run showed such a child receives no skill text.
assert_contains "…and preloads instead of widening the limit" "$derived" "skill delivery: preload"
assert_contains "…with the canonical body inlined"  "$derived" "begin canonical skill: skills/review-code/SKILL.md"
assert_contains "…traceable by hash"                "$derived" "sha256="
n_inlined="$(grep -c 'begin canonical skill' "$TD/agents/review.md")"
assert_eq "every declared skill is delivered" 2 "$n_inlined"

assert_file_exists "a delivery record is written" "$TD/.agent-skills/delivered-skills-claude.json"
rec="$(cat "$TD/.agent-skills/delivered-skills-claude.json")"
assert_contains "…naming the contract version" "$rec" "0.3.0"
assert_contains "…and the delivery method"     "$rec" "preload"

# A permission class the tool map does not cover fails loudly rather than
# quietly dropping a capability the role needs.
{
  printf 'version: 3\n'
  printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
  printf 'tool_map:\n  claude:\n    read: [Read]\n'
  printf 'roles:\n  research:\n    claude:\n      permissions: [read, network]\n'
} > "$CFG3/nomap.yaml"
out="$($RENDER --runtime claude --root "$R0" --target "$TD" --config "$CFG3/nomap.yaml" --apply 2>&1)"; rc=$?
assert_eq "an unmapped permission class is a configuration error" 2 "$rc"
assert_contains "…and is named" "$out" "does not map"
assert_contains "…as an authorized class, not a floor" "$out" "authorized permission"

# --- R1: the floor is a minimum, not the allowlist ----------------------------
# Regression for the reviewed defect: a role's required_permissions were used as
# the entire tool list, so a role could never be authorized for anything above
# its floor — a review role could not write the report the contract names.
{
  printf 'version: 3
'
  printf 'policies:
  default:
    claude:
      model: sonnet
  escalated:
    claude:
      model: opus
'
  printf 'tool_map:
  claude:
    read: [Read, Grep, Glob]
    write: [Write, Edit]
    execute: [Bash]
'
  printf 'roles:
  review:
    permissions: [read, write]
'
} > "$CFG3/authorized.yaml"
TA="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TA" --config "$CFG3/authorized.yaml" --apply 2>&1)"; rc=$?
assert_eq "an authorized permission set renders" 0 "$rc"
auth="$(cat "$TA/agents/review.md")"
assert_contains "…granting tools above the floor"    "$auth" "tools: Read, Grep, Glob, Write, Edit"
assert_contains "…attributed to the authorization"   "$auth" "derived from the authorized permissions"

# Below the floor is refused: a role cannot discharge its responsibility there.
{
  printf 'version: 3
'
  printf 'policies:
  default:
    claude:
      model: sonnet
  escalated:
    claude:
      model: opus
'
  printf 'tool_map:
  claude:
    read: [Read]
    write: [Write]
    execute: [Bash]
'
  printf 'roles:
  testing:
    permissions: [read]
'
} > "$CFG3/belowfloor.yaml"
TB="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TB" --config "$CFG3/belowfloor.yaml" --apply 2>&1)"; rc=$?
assert_eq "an authorization below the role floor is refused" 2 "$rc"
assert_contains "…naming the missing class" "$out" "do not meet its floor"
assert_eq "…leaving nothing written" 0 "$(find "$TB" -type f 2>/dev/null | wc -l)"

# Above the ceiling is refused too.
{
  printf 'version: 3
'
  printf 'policies:
  default:
    claude:
      model: sonnet
  escalated:
    claude:
      model: opus
'
  printf 'tool_map:
  claude:
    read: [Read]
    write: [Write]
    execute: [Bash]
    network: [WebFetch]
'
  printf 'roles:
  documentation:
    permissions: [read, write, network]
'
} > "$CFG3/aboveceiling.yaml"
TC="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TC" --config "$CFG3/aboveceiling.yaml" --apply 2>&1)"; rc=$?
assert_eq "an authorization above the role ceiling is refused" 2 "$rc"
assert_contains "…naming the excess" "$out" "exceed its ceiling"

# Without authorization the output is a template, explicitly not executable.
TT="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TT" --config "$CFG3/authorized.yaml" --apply 2>&1)"
tmpl="$(cat "$TT/agents/planning.md")"
assert_contains "an unauthorized role is marked non-executable" "$tmpl" "NON-EXECUTABLE TEMPLATE"
assert_not_contains "…and carries no tool limit to mistake for one" "$tmpl" "tools:"

# --- R1: an explicit empty override is a decision, not an absence -------------
{
  printf 'version: 3
'
  printf 'policies:
  default:
    claude:
      model: sonnet
  escalated:
    claude:
      model: opus
'
  printf 'tool_map:
  claude:
    read: [Read]
'
  printf 'roles:
  review:
    claude:
      tools_override: []
      justification: operator wants no tools
'
} > "$CFG3/emptyoverride.yaml"
TE="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TE" --config "$CFG3/emptyoverride.yaml" --apply 2>&1)"; rc=$?
assert_eq "an explicitly empty override is not silently ignored" 2 "$rc"
assert_contains "…it means no tools"            "$out" "means NO tools"
assert_contains "…and says why it refuses"      "$out" "has not been measured"
assert_eq "…leaving nothing written" 0 "$(find "$TE" -type f 2>/dev/null | wc -l)"

# An override still has to satisfy the floor, justified or not.
{
  printf 'version: 3
'
  printf 'policies:
  default:
    claude:
      model: sonnet
  escalated:
    claude:
      model: opus
'
  printf 'tool_map:
  claude:
    read: [Read, Grep, Glob]
    execute: [Bash]
'
  printf 'roles:
  testing:
    claude:
      tools_override: [Read]
      justification: operator preference
'
} > "$CFG3/shortoverride.yaml"
TS="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TS" --config "$CFG3/shortoverride.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override below the floor is refused" 2 "$rc"
assert_contains "…even with a justification" "$out" "justified or not"

# --- adapter-declared limits must be visible, never silent --------------------
{
  printf 'version: 3\n'
  printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
  printf 'roles:\n  review:\n    claude:\n      tools_override: [Read]\n'
} > "$CFG3/nojust.yaml"
out="$($RENDER --runtime claude --target "$TD" --config "$CFG3/nojust.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override without a justification is rejected" 2 "$rc"
assert_contains "…because adapter policy must be visible" "$out" "must be visible, not silent"

{
  printf 'version: 3\n'
  printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
  printf 'tool_map:\n  claude:\n    read: [Read, Grep, Glob]\n    write: [Write]\n    execute: [Bash]\n'
  printf 'roles:\n  review:\n    claude:\n      tools_override: [Read]\n      justification: operator policy for this host\n'
} > "$CFG3/just.yaml"
TO="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TO" --config "$CFG3/just.yaml" --apply 2>&1)"; rc=$?
assert_eq "a justified override renders" 0 "$rc"
over="$(cat "$TO/agents/review.md")"
assert_contains "…stamped as adapter-declared"  "$over" "ADAPTER-DECLARED override"
assert_contains "…carrying the justification"   "$over" "operator policy for this host"
assert_contains "…and restricted, so it preloads" "$over" "skill delivery: preload"

# An override cannot be checked against a floor without a tool map, so it is
# refused rather than accepted on trust.
{
  printf 'version: 3\n'
  printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
  printf 'roles:\n  review:\n    claude:\n      tools_override: [Read]\n      justification: no map declared\n'
} > "$CFG3/nomapoverride.yaml"
TN="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TN" --config "$CFG3/nomapoverride.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override with no tool_map is refused" 2 "$rc"
assert_contains "…because coverage is unknowable" "$out" "tool_map is empty"

# --- the pre-3 per-role tools list is refused ---------------------------------
{
  printf 'version: 3\n'
  printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
  printf 'roles:\n  review:\n    claude:\n      tools: [Read]\n'
} > "$CFG3/oldtools.yaml"
out="$($RENDER --runtime claude --target "$TD" --config "$CFG3/oldtools.yaml" --apply 2>&1)"; rc=$?
assert_eq "an invented per-role tools list is refused" 2 "$rc"
assert_contains "…pointing at required_permissions" "$out" "required_permissions"

# --- unresolved policies and bad contracts are configuration errors -----------
E="$(sandbox_new)"
printf 'version: 3\npolicies:\n  default:\n    claude:\n      model: sonnet\n' > "$E/partial.yaml"
out="$($RENDER --runtime claude --target "$E" --config "$E/partial.yaml" --apply 2>&1)"; rc=$?
assert_eq "an unbound policy is a configuration error" 2 "$rc"
assert_contains "…naming the missing binding" "$out" "escalated"
assert_contains "…and refusing to guess"      "$out" "no model is guessed"

printf 'version: 2\npolicies:\n  default:\n    claude:\n      model: sonnet\n' > "$E/v1.yaml"
out="$($RENDER --runtime claude --target "$E" --config "$E/v1.yaml" --apply 2>&1)"; rc=$?
assert_eq "the superseded routing schema version is rejected" 2 "$rc"

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
d=json.load(open(p,encoding='utf-8')); d['contract_version']='0.9.0'
json.dump(d,open(p,'w',encoding='utf-8'))" "$R"
out="$($RENDER --runtime claude --target "$E" --root "$R" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "an unsupported contract version is rejected" 2 "$rc"
assert_contains "…without reinterpreting it" "$out" "will not reinterpret"

python3 -c "
import json,sys
p=sys.argv[1]+'/roles/catalog.json'
d=json.load(open(p,encoding='utf-8')); d['contract_version']='0.3.0'
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
