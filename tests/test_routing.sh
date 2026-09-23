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
n="$(find "$T/agents" "$T/.agent-skills/templates/claude" -name '*.md'       ! -name README.md 2>/dev/null | grep -c .)"
assert_eq "all $EXPECTED_ROLES canonical roles are rendered" "$EXPECTED_ROLES" "$n"
assert_contains "…driven by the contract version" "$out" "contract: 0.3.0"
for role in orchestrator planning review security documentation critical-thinking; do
  assert_file_exists "role $role rendered" \
    "$(test -f "$T/agents/$role.md" && echo "$T/agents/$role.md" || echo "$T/.agent-skills/templates/claude/$role.md")"
done

T2="$(sandbox_new)"
out="$($RENDER --runtime codex --target "$T2" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "codex render exits 0" 0 "$rc"
n="$(find "$T2/agents" "$T2/.agent-skills/templates/codex" -name '*.toml' 2>/dev/null | grep -c .)"
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
toml="$(cat "$T2/.agent-skills/templates/codex/review.toml")"
assert_contains "codex model bound"      "$toml" 'model = "gpt-5.6"'
assert_contains "codex reasoning bound"  "$toml" 'model_reasoning_effort = "medium"'
assert_contains "codex sandbox bound"    "$toml" 'sandbox_mode = "read-only"'

# --- tool limits come from an explicit authorization -------------------------
# A role with no authorized permission set renders as a template: the canonical
# profile alone cannot establish an authorized, restricted execution, and a file
# with no tool limit would inherit whatever the parent holds.
plain="$(cat "$T/.agent-skills/templates/claude/planning.md")"
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
tmpl="$(cat "$TT/.agent-skills/templates/claude/planning.md")"
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
      permissions: [read, execute]
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
  printf 'roles:\n  review:\n    claude:\n      permissions: [read]\n      tools_override: [Read]\n'
} > "$CFG3/nojust.yaml"
out="$($RENDER --runtime claude --target "$TD" --config "$CFG3/nojust.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override without a justification is rejected" 2 "$rc"
assert_contains "…because adapter policy must be visible" "$out" "must be visible, not silent"

{
  printf 'version: 3\n'
  printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
  printf 'tool_map:\n  claude:\n    read: [Read, Grep, Glob]\n    write: [Write]\n    execute: [Bash]\n'
  printf 'roles:\n  review:\n    claude:\n      permissions: [read]\n      tools_override: [Read]\n      justification: operator policy for this host\n'
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
  printf 'roles:\n  review:\n    claude:\n      permissions: [read]\n      tools_override: [Read]\n      justification: no map declared\n'
} > "$CFG3/nomapoverride.yaml"
TN="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TN" --config "$CFG3/nomapoverride.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override with no tool_map is refused" 2 "$rc"
assert_contains "…because coverage is unknowable" "$out" "tool_map is empty"

# --- an override is an executable configuration, so it is bounded too ---------
# Reviewed defect: the override branch checked floor coverage and returned, so a
# justified override could name tools carrying permissions the role was neither
# authorized for nor ever allowed to hold.
ovr() { # ovr NAME ROLE_BLOCK
  {
    printf 'version: 3\n'
    printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
    printf 'tool_map:\n  claude:\n    read: [Read, Grep, Glob]\n    write: [Write, Edit]\n    execute: [Bash]\n    network: [WebFetch, WebSearch]\n'
    printf '%b' "$2"
  } > "$CFG3/$1.yaml"
}

# documentation: floor [read], ceiling [read, write]. WebFetch carries `network`,
# which is outside both the authorization and the ceiling.
ovr above-ceiling 'roles:\n  documentation:\n    claude:\n      permissions: [read]\n      tools_override: [Read, WebFetch]\n      justification: operator asked for web access\n'
TOC="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TOC" --config "$CFG3/above-ceiling.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override reaching outside the ceiling is refused" 2 "$rc"
assert_contains "…naming the offending tool and class" "$out" "WebFetch carries network"
assert_eq "…leaving nothing written" 0 "$(find "$TOC" -type f 2>/dev/null | wc -l)"

# Authorized for read+write, but the override still reaches `network`.
ovr outside-auth 'roles:\n  documentation:\n    claude:\n      permissions: [read, write]\n      tools_override: [Read, WebFetch]\n      justification: operator asked for web access\n'
TOA="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TOA" --config "$CFG3/outside-auth.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override outside the authorized set is refused" 2 "$rc"
assert_contains "…even though it is inside no ceiling of its own" "$out" "reaches outside its authorized permissions"
assert_contains "…and a justification does not exempt it" "$out" "justified or not"

ovr unmapped 'roles:\n  documentation:\n    claude:\n      permissions: [read]\n      tools_override: [Read, UnknownTool]\n      justification: operator preference\n'
TUM="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TUM" --config "$CFG3/unmapped.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override naming an unmapped tool is refused" 2 "$rc"
assert_contains "…because its permission classes are unknown" "$out" "does not "
assert_eq "…leaving nothing written" 0 "$(find "$TUM" -type f 2>/dev/null | wc -l)"

ovr no-auth 'roles:\n  documentation:\n    claude:\n      tools_override: [Read]\n      justification: operator preference\n'
TNA="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TNA" --config "$CFG3/no-auth.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override without authorization is refused" 2 "$rc"
assert_contains "…because an override is still executable" "$out" "requires an explicit authorized permission set"

# testing floor is [read, execute]; an override covering only read cannot meet it.
ovr below-floor 'roles:\n  testing:\n    claude:\n      permissions: [read, execute]\n      tools_override: [Read]\n      justification: operator preference\n'
TBF="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TBF" --config "$CFG3/below-floor.yaml" --apply 2>&1)"; rc=$?
assert_eq "an override below the role floor is refused" 2 "$rc"
assert_contains "…naming the uncovered class" "$out" "does not cover its required permission"

# A valid override: authorized read+execute, tools inside that set, floor covered.
ovr valid 'roles:\n  testing:\n    claude:\n      permissions: [read, execute]\n      tools_override: [Read, Bash]\n      justification: operator narrowed the read tools\n'
TV="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TV" --config "$CFG3/valid.yaml" --apply 2>&1)"; rc=$?
assert_eq "a valid override renders" 0 "$rc"
valid_body="$(cat "$TV/agents/testing.md")"
assert_contains "…with exactly the overridden tools" "$valid_body" "tools: Read, Bash"
assert_contains "…stamped as adapter-declared"       "$valid_body" "ADAPTER-DECLARED override"
assert_contains "…carrying the justification"        "$valid_body" "operator narrowed the read tools"

# --- a derived tool list is bounded exactly as an override is -----------------
# A tool NAME may be declared under several permission classes. Reaching it
# through an authorized class selects every class it declares, so a name shared
# with an unauthorized class reaches outside the authorization — and with it the
# ceiling. The override path checked this tool by tool; the derived path walked
# the authorized classes, collected their names and returned, never asking what
# else those names were mapped to.
shared() { # shared NAME TOOL_MAP_BLOCK ROLE_BLOCK
  {
    printf 'version: 3\n'
    printf 'policies:\n  default:\n    claude:\n      model: sonnet\n  escalated:\n    claude:\n      model: opus\n'
    printf '%b' "$2"
    printf '%b' "$3"
  } > "$CFG3/$1.yaml"
}

# documentation: floor [read], ceiling [read, write]. SharedTool is declared
# under `read` and under `network`; the role is authorized for `read` alone.
shared derived-shared \
  'tool_map:\n  claude:\n    read: [SharedTool]\n    network: [SharedTool]\n' \
  'roles:\n  documentation:\n    claude:\n      permissions: [read]\n'
TDS="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TDS" --config "$CFG3/derived-shared.yaml" --apply 2>&1)"; rc=$?
assert_eq "a derived tool carrying an unauthorized class is refused" 2 "$rc"
assert_contains "…naming the tool and the class"   "$out" "SharedTool carries network"
assert_contains "…and the path that selected it"   "$out" "derived from its authorized permissions"
assert_contains "…bounding both paths by one rule" "$out" "an override alike"
assert_eq "…leaving nothing written" 0 "$(find "$TDS" -type f 2>/dev/null | wc -l)"

# The same shared name is legitimate when every class it declares is explicitly
# authorized and the authorization is still inside the ceiling.
shared derived-shared-ok \
  'tool_map:\n  claude:\n    read: [SharedTool]\n    write: [SharedTool, Write]\n' \
  'roles:\n  documentation:\n    claude:\n      permissions: [read, write]\n'
TDO="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TDO" --config "$CFG3/derived-shared-ok.yaml" --apply 2>&1)"; rc=$?
assert_eq "a shared tool whose every class is authorized renders" 0 "$rc"
shared_body="$(cat "$TDO/agents/documentation.md")"
assert_contains "…selecting the shared tool once"  "$shared_body" "tools: SharedTool, Write"
assert_contains "…attributed to the authorization" "$shared_body" "derived from the authorized permissions [read,write]"

# --- templates stay out of the runtime's discovery path -----------------------
# A comment saying NON-EXECUTABLE does not stop a runtime listing and
# dispatching a file in its agents directory. Placement has to do that.
TPL="$(sandbox_new)"
out="$($RENDER --runtime claude --target "$TPL" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "a mixed render succeeds" 0 "$rc"
assert_file_exists "an authorized role is installed as an agent" "$TPL/agents/review.md"
assert_file_absent "an unauthorized role is NOT in the agents directory" "$TPL/agents/planning.md"
assert_file_exists "…it is written as a template instead" "$TPL/.agent-skills/templates/claude/planning.md"
assert_file_exists "…with a README saying why" "$TPL/.agent-skills/templates/claude/README.md"
rec="$(cat "$TPL/.agent-skills/delivered-skills-claude.json")"
assert_contains "the delivery record marks executability" "$rec" "\"executable\""

TPLC="$(sandbox_new)"
out="$($RENDER --runtime codex --target "$TPLC" --config "$CFG" --apply 2>&1)"; rc=$?
assert_eq "the same split applies to codex" 0 "$rc"
assert_file_exists "…codex templates are written outside agents/" "$TPLC/.agent-skills/templates/codex/planning.toml"
assert_file_absent "…and nothing unauthorized reaches its agents directory" "$TPLC/agents/planning.toml"

# --- transitions must not leave a stale active agent --------------------------
TR="$(sandbox_new)"
ovr auth-planning 'roles:\n  planning:\n    claude:\n      permissions: [read]\n'
$RENDER --runtime claude --target "$TR" --config "$CFG3/auth-planning.yaml" --apply >/dev/null 2>&1
assert_file_exists "an authorized role starts out installed" "$TR/agents/planning.md"

ovr no-planning ''
out="$($RENDER --runtime claude --target "$TR" --config "$CFG3/no-planning.yaml" --apply 2>&1)"; rc=$?
assert_eq "removing the authorization succeeds" 0 "$rc"
assert_contains "…reporting the deactivation" "$out" "DEACTIVATE planning"
assert_file_absent "…and the live agent is gone, not merely relabelled" "$TR/agents/planning.md"
assert_file_exists "…the role survives as a template" "$TR/.agent-skills/templates/claude/planning.md"

out="$($RENDER --runtime claude --target "$TR" --config "$CFG3/auth-planning.yaml" --apply 2>&1)"; rc=$?
assert_eq "re-authorizing succeeds" 0 "$rc"
assert_contains "…reporting the promotion" "$out" "PROMOTE"
assert_file_exists "…the agent is installed again" "$TR/agents/planning.md"
assert_file_absent "…and the template does not linger" "$TR/.agent-skills/templates/claude/planning.md"

# A hand-edited agent must never be deleted to satisfy a deactivation, and the
# run must not claim the role was deactivated.
printf '\nhand edit\n' >> "$TR/agents/planning.md"
before="$(sha256sum < "$TR/agents/planning.md")"
out="$($RENDER --runtime claude --target "$TR" --config "$CFG3/no-planning.yaml" --apply 2>&1)"; rc=$?
assert_ne "a modified agent blocks the deactivation" 0 "$rc"
assert_contains "…reported as a conflict"        "$out" "CONFLICT role planning"
assert_contains "…saying it was modified"        "$out" "modified since it was rendered"
assert_contains "…and refusing to claim success" "$out" "was NOT deactivated"
assert_file_exists "…the edited file is preserved" "$TR/agents/planning.md"
assert_eq "…byte for byte" "$before" "$(sha256sum < "$TR/agents/planning.md")"

# An unowned file at the active path is equally untouchable.
TU="$(sandbox_new)"
$RENDER --runtime claude --target "$TU" --config "$CFG3/no-planning.yaml" --apply >/dev/null 2>&1
mkdir -p "$TU/agents"
printf 'someone else wrote this\n' > "$TU/agents/planning.md"
out="$($RENDER --runtime claude --target "$TU" --config "$CFG3/no-planning.yaml" --apply 2>&1)"; rc=$?
assert_ne "an unowned agent blocks the deactivation" 0 "$rc"
assert_contains "…as not ours to remove" "$out" "not written by this renderer"
assert_eq "…and is left exactly as found" "someone else wrote this" "$(cat "$TU/agents/planning.md")"

# --- check sees a role sitting in the wrong place ------------------------------
TC2="$(sandbox_new)"
$RENDER --runtime claude --target "$TC2" --config "$CFG" --apply >/dev/null 2>&1
out="$($RENDER --runtime claude --target "$TC2" --config "$CFG" --check 2>&1)"; rc=$?
assert_eq "check passes on a correct install" 0 "$rc"
cp "$TC2/.agent-skills/templates/claude/planning.md" "$TC2/agents/planning.md"
out="$($RENDER --runtime claude --target "$TC2" --config "$CFG" --check 2>&1)"; rc=$?
assert_ne "check fails when a template is also installed as an agent" 0 "$rc"
assert_contains "…naming the discoverable copy" "$out" "still discoverable at"

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

# --- the destination is ownership-checked before it is replaced ---------------
# The migration preflight protected the file at the OTHER location, so a role
# changing side never clobbered anything. The destination had no such check: the
# write loop asked only whether the path was in the manifest, never whether the
# bytes still matched the digest recorded for it. An edit made to a live agent
# since the last render was therefore overwritten, and the run exited 0.
ovr own-review 'roles:\n  review:\n    claude:\n      permissions: [read]\n'

# First, the boundary the preflight must NOT block: an untouched destination whose
# rendered content has changed is still updated in place. A digest that matches
# what was written is exactly what makes a file safe to replace.
ovr wider-review 'roles:\n  review:\n    claude:\n      permissions: [read, write]\n'
TUP="$(sandbox_new)"
$RENDER --runtime claude --target "$TUP" --config "$CFG3/own-review.yaml" --apply >/dev/null 2>&1
assert_contains "the first render limits review to its read tools" \
  "$(cat "$TUP/agents/review.md")" "tools: Read, Grep, Glob"
out="$($RENDER --runtime claude --target "$TUP" --config "$CFG3/wider-review.yaml" --apply 2>&1)"; rc=$?
assert_eq "a wider authorization re-renders the same path" 0 "$rc"
assert_contains "…reported as an update, not a collision" "$out" "UPDATE"
assert_contains "…and the new limit is on disk" \
  "$(cat "$TUP/agents/review.md")" "tools: Read, Grep, Glob, Write, Edit"
out="$($RENDER --runtime claude --target "$TUP" --config "$CFG3/wider-review.yaml" --check 2>&1)"; rc=$?
assert_eq "…leaving the install consistent" 0 "$rc"

TM="$(sandbox_new)"
$RENDER --runtime claude --target "$TM" --config "$CFG3/own-review.yaml" --apply >/dev/null 2>&1
assert_file_exists "an authorized role is installed" "$TM/agents/review.md"
printf '\noperator edit\n' >> "$TM/agents/review.md"
edited="$(sha256sum < "$TM/agents/review.md")"
fp="$(tree_fingerprint "$TM")"
out="$($RENDER --runtime claude --target "$TM" --config "$CFG3/own-review.yaml" --apply 2>&1)"; rc=$?
assert_ne "a modified active agent blocks the render" 0 "$rc"
assert_contains "…reported before anything is written" "$out" "COLLISION"
assert_contains "…saying what is wrong with it"        "$out" "modified since it was rendered"
assert_contains "…and refusing to claim a write"       "$out" "no manifest or delivery record updated"
assert_eq "…the edit survives byte for byte" "$edited" "$(sha256sum < "$TM/agents/review.md")"
assert_eq "…and nothing else in the target moved" "$fp" "$(tree_fingerprint "$TM")"

# A template is a build output too, and an edited one is just as much someone's
# work as an edited agent.
TMT="$(sandbox_new)"
$RENDER --runtime claude --target "$TMT" --config "$CFG3/own-review.yaml" --apply >/dev/null 2>&1
TPLF="$TMT/.agent-skills/templates/claude/planning.md"
printf '\noperator edit\n' >> "$TPLF"
edited="$(sha256sum < "$TPLF")"
fp="$(tree_fingerprint "$TMT")"
out="$($RENDER --runtime claude --target "$TMT" --config "$CFG3/own-review.yaml" --apply 2>&1)"; rc=$?
assert_ne "a modified template blocks the render too" 0 "$rc"
assert_contains "…naming the file"          "$out" "planning.md"
assert_eq "…which survives byte for byte"   "$edited" "$(sha256sum < "$TPLF")"
assert_eq "…leaving the target untouched"   "$fp" "$(tree_fingerprint "$TMT")"

# Knowing a generated file's path is not a licence to overwrite it. The README
# and the delivery record are build outputs under the same ownership rule.
TRM="$(sandbox_new)"
$RENDER --runtime claude --target "$TRM" --config "$CFG3/own-review.yaml" --apply >/dev/null 2>&1
RMF="$TRM/.agent-skills/templates/claude/README.md"
printf '\nOperator note: our own wording, keep it.\n' >> "$RMF"
edited="$(sha256sum < "$RMF")"
fp="$(tree_fingerprint "$TRM")"
out="$($RENDER --runtime claude --target "$TRM" --config "$CFG3/own-review.yaml" --apply 2>&1)"; rc=$?
assert_ne "a modified templates README blocks the render" 0 "$rc"
assert_contains "…named as the generated file it is" "$out" "templates README"
assert_eq "…and preserved byte for byte" "$edited" "$(sha256sum < "$RMF")"
assert_eq "…leaving the target untouched" "$fp" "$(tree_fingerprint "$TRM")"

TDR="$(sandbox_new)"
$RENDER --runtime claude --target "$TDR" --config "$CFG3/own-review.yaml" --apply >/dev/null 2>&1
DRF="$TDR/.agent-skills/delivered-skills-claude.json"
printf '\n' >> "$DRF"
edited="$(sha256sum < "$DRF")"
fp="$(tree_fingerprint "$TDR")"
out="$($RENDER --runtime claude --target "$TDR" --config "$CFG3/own-review.yaml" --apply 2>&1)"; rc=$?
assert_ne "a modified delivery record blocks the render" 0 "$rc"
assert_contains "…named as the generated file it is" "$out" "delivery record"
assert_eq "…and preserved byte for byte" "$edited" "$(sha256sum < "$DRF")"
assert_eq "…leaving the target untouched" "$fp" "$(tree_fingerprint "$TDR")"

# An unowned file sitting at a destination is refused as well: the promotion
# would have replaced a file this renderer never wrote.
TUD="$(sandbox_new)"
$RENDER --runtime claude --target "$TUD" --config "$CFG3/own-review.yaml" --apply >/dev/null 2>&1
assert_file_exists "planning starts as a template" "$TUD/.agent-skills/templates/claude/planning.md"
mkdir -p "$TUD/agents"
printf 'someone else put this here\n' > "$TUD/agents/planning.md"
ovr promote-planning 'roles:\n  review:\n    claude:\n      permissions: [read]\n  planning:\n    claude:\n      permissions: [read]\n'
out="$($RENDER --runtime claude --target "$TUD" --config "$CFG3/promote-planning.yaml" --apply 2>&1)"; rc=$?
assert_ne "an unowned destination blocks the promotion" 0 "$rc"
assert_contains "…as not this renderer's to replace" "$out" "not written by this renderer"
assert_eq "…and is left exactly as found" "someone else put this here" "$(cat "$TUD/agents/planning.md")"
assert_file_exists "…the template it would have replaced is intact" \
  "$TUD/.agent-skills/templates/claude/planning.md"

# One conflict fails the whole batch. Writing the roles that happen to be clean
# would leave the target half-migrated, described by a manifest and a delivery
# record for a delivery that did not take place.
TBA="$(sandbox_new)"
ovr batch-before 'roles:\n  review:\n    claude:\n      permissions: [read]\n  planning:\n    claude:\n      permissions: [read]\n'
$RENDER --runtime claude --target "$TBA" --config "$CFG3/batch-before.yaml" --apply >/dev/null 2>&1
assert_file_exists "review starts installed"   "$TBA/agents/review.md"
assert_file_exists "planning starts installed" "$TBA/agents/planning.md"
# review is edited, and in the same run planning loses its authorization — an
# unrelated deactivation, plus the template write that goes with it.
printf '\noperator edit\n' >> "$TBA/agents/review.md"
fp="$(tree_fingerprint "$TBA")"
out="$($RENDER --runtime claude --target "$TBA" --config "$CFG3/own-review.yaml" --apply 2>&1)"; rc=$?
assert_ne "one conflict fails the whole batch" 0 "$rc"
assert_file_exists "…the unrelated migration did not happen" "$TBA/agents/planning.md"
assert_file_absent "…nor the template write that went with it" \
  "$TBA/.agent-skills/templates/claude/planning.md"
assert_eq "…and not one byte of the target changed" "$fp" "$(tree_fingerprint "$TBA")"

t_summary
