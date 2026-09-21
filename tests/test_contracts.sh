#!/usr/bin/env bash
# Contract validation: JSON Schema shape and cross-document semantics, asserted
# as two separate results.
#
# None of this is runtime enforcement. A document that validates here has not
# been executed, and no permission, budget or tool boundary has been enforced by
# validating it.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

V="python3 $REPO_ROOT/scripts/contracts/validate.py"
EX="$REPO_ROOT/contracts/examples"
GEN="$REPO_ROOT/tests/lib/mutate_contract.py"

if ! python3 -c "import jsonschema" 2>/dev/null; then
  echo "    FAIL  jsonschema is not installed — schema validation cannot run."
  echo "          Install it (pip install jsonschema); an unavailable check is never a pass."
  exit 1
fi

# --- schema, on the canonical artifacts ---------------------------------------
out="$($V --schema 2>&1)"; rc=$?
assert_eq "schema validation passes on the canonical set" 0 "$rc"
assert_contains "…and covers the catalog"  "$out" "catalog.json"
assert_contains "…and every role profile"  "$out" "review.json"
assert_contains "…and the examples"        "$out" "task.json"
assert_contains "…reported as its own result" "$out" "SCHEMA VALIDATION: PASS"

# --- semantics, on the canonical artifacts ------------------------------------
out="$($V --semantic --task "$EX/task.json" --result "$EX/result.json" 2>&1)"; rc=$?
assert_eq "semantic validation passes on the canonical set" 0 "$rc"
assert_contains "…reported separately from shape" "$out" "SEMANTIC VALIDATION: PASS"
assert_contains "dispatch identity is checked"    "$out" "result echoes dispatch_id"
assert_contains "criterion uniqueness is checked" "$out" "criterion IDs are unique"
assert_contains "permission ceiling is checked"   "$out" "within the role ceiling"
assert_contains "write containment is checked"    "$out" "is contained"
assert_contains "all 14 canonical roles are covered" "$out" "role documentation skill"

# --- negatives ----------------------------------------------------------------
# Two groups, establishing different things:
#
#   gap    the schema ACCEPTS the document and only the semantic layer rejects
#          it. These are the cases that justify a separate validator at all.
#   depth  the schema rejects it too. Asserted so a later schema relaxation
#          cannot quietly remove the only check standing.
F="$(sandbox_new)"

reject() { # reject NAME LABEL NEEDLE gap|depth [extra validator args...]
  _name="$1"; _label="$2"; _needle="$3"; _kind="$4"; shift 4
  _out="$($V --semantic --task "$F/$_name-task.json" --result "$F/$_name-result.json" "$@" 2>&1)"
  _rc=$?
  assert_ne "$_label is rejected by the semantic layer" 0 "$_rc"
  assert_contains "…by the expected check" "$_out" "$_needle"
  $V --schema --task "$F/$_name-task.json" --result "$F/$_name-result.json" >/dev/null 2>&1
  _src=$?
  if [ "$_kind" = gap ]; then
    assert_eq "…and the schema alone accepts it (why the semantic layer exists)" 0 "$_src"
  else
    assert_ne "…and the schema rejects it as well" 0 "$_src"
  fi
}

python3 "$GEN" "$EX" "$F" || { echo "    FAIL  fixture generation"; t_summary; exit 1; }

reject dispatch      "a mismatched dispatch id"                "result echoes dispatch_id"        gap
reject attempt       "an attempt beyond the budget"            "within the budget"                gap
reject dupcrit       "duplicate criterion IDs"                 "criterion IDs are unique"         gap
reject dangling      "a dangling evidence reference"           "only existing evidence"           gap
reject invented      "an invented acceptance criterion"        "resolves to a task criterion"     gap
reject perms         "permissions above the role ceiling"      "within the role ceiling"          gap
reject selfdep       "a self-dependency"                       "does not depend on itself"        gap
reject outofscope    "a changed file outside the write scope"  "within the write scope"           gap
reject escape        "a write path escaping the workspace"     "is contained"                     depth
reject blockcomplete "a completed result with a blocking item" "no blocking unresolved item"      depth
reject replay        "re-accepting a dispatch"                 "has not already been accepted"    gap --ledger "$F/ledger.json"

# --- the completed example is canonical, not synthetic ------------------------
# Acceptance, evidence and delivery semantics are exercised by a shipped example,
# so the contract cannot drift away from its own documentation unnoticed.
out="$($V --semantic --task "$EX/task-completed.json" --result "$EX/result-completed.json" 2>&1)"; rc=$?
assert_eq "the completed example passes semantic validation" 0 "$rc"
assert_contains "…exercising evidence references" "$out" "references only existing evidence"
assert_contains "…and every criterion recorded once" "$out" "recorded exactly once"
assert_contains "…and delivery provenance"          "$out" "is declared by role"
assert_contains "…and changed files in scope"       "$out" "within the write scope"

$V --schema >/dev/null 2>&1
assert_eq "…and the schema, as part of the canonical set" 0 $?

# --- delivery provenance invariants (contract 0.3.0) --------------------------
reject undeclared-skill "delivery of a skill the role never declared" "is declared by role" gap
reject bad-digest       "a delivery digest that is not a sha256"      "carries a sha256 digest" depth
reject dup-delivery     "the same skill claimed as delivered twice"   "refs are unique" depth

# --- required_permissions is a floor inside the ceiling -----------------------
# Two sibling arrays the schema cannot compare: a role that requires a permission
# its own ceiling forbids is incoherent, and only the semantic layer sees it.
R="$(sandbox_new)/root"
mkdir -p "$R"
cp -r "$REPO_ROOT/roles" "$REPO_ROOT/contracts" "$REPO_ROOT/skills" "$REPO_ROOT/rules" "$R/"

python3 -c "
import json, sys
p = sys.argv[1] + '/roles/documentation.json'
d = json.load(open(p, encoding='utf-8'))
d['required_permissions'] = ['read', 'execute']   # ceiling is read, write
json.dump(d, open(p, 'w', encoding='utf-8'))" "$R"
out="$($V --semantic --root "$R" 2>&1)"; rc=$?
assert_ne "a required permission outside the ceiling is rejected" 0 "$rc"
assert_contains "…and named" "$out" "stay within its ceiling"

$V --schema --root "$R" >/dev/null 2>&1
assert_eq "…while the schema alone accepts it (why the semantic layer exists)" 0 $?

python3 -c "
import json, sys
p = sys.argv[1] + '/roles/documentation.json'
d = json.load(open(p, encoding='utf-8'))
d['required_permissions'] = ['read']
json.dump(d, open(p, 'w', encoding='utf-8'))" "$R"
out="$($V --semantic --root "$R" 2>&1)"; rc=$?
assert_eq "a floor inside the ceiling is accepted" 0 "$rc"

# --- dependency graph ---------------------------------------------------------
out="$($V --semantic --task "$F/cycle-a.json" --task "$F/cycle-b.json" 2>&1)"; rc=$?
assert_ne "a dependency cycle is rejected" 0 "$rc"
assert_contains "…and the cycle is named" "$out" "dependency graph is acyclic"

out="$($V --semantic --task "$F/dag-a.json" --task "$F/dag-b.json" 2>&1)"; rc=$?
assert_eq "an acyclic graph is accepted" 0 "$rc"

out="$($V --semantic --task "$F/dag-b.json" 2>&1)"; rc=$?
assert_ne "a dependency missing from the graph is rejected" 0 "$rc"
assert_contains "…and named" "$out" "dependencies exist in the graph"

t_summary
