#!/usr/bin/env bash
# Runtime capability records: validation, and the renderer gate that consumes
# them.
#
# The gate is the point of M1. A role runs on a runtime only where the runtime's
# ability to do what the role requires has been measured. Everything short of
# that — unmeasured, documented, configured, observed-but-unenforced, a record
# for another version or platform, no record at all — refuses, and refuses
# before anything is written.
#
# Validating a record is not measuring a runtime. Nothing here re-runs a probe.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

CAPVAL="python3 $REPO_ROOT/scripts/capabilities/validate.py"
RENDER="python3 $REPO_ROOT/scripts/routing/render.py"
CFG="$REPO_ROOT/config/routing/models.example.yaml"
MEASURED="$REPO_ROOT/capabilities/records/claude-code-2.1.220-windows.json"
EXAMPLE="$REPO_ROOT/capabilities/examples/codex-unmeasured.example.json"

if ! python3 -c "import jsonschema" 2>/dev/null; then
  echo "    FAIL  jsonschema is not installed — capability schema validation cannot run."
  exit 1
fi

# --- the shipped records ------------------------------------------------------
out="$($CAPVAL --schema 2>&1)"; rc=$?
assert_eq "capability records satisfy the schema" 0 "$rc"
assert_contains "…reported as its own result" "$out" "CAPABILITY SCHEMA VALIDATION: PASS"

out="$($CAPVAL --semantic 2>&1)"; rc=$?
assert_eq "capability records satisfy the semantic checks" 0 "$rc"
assert_contains "…reported separately from shape" "$out" "CAPABILITY SEMANTIC VALIDATION: PASS"
assert_contains "enforcement claims are checked for enforcement evidence" "$out" "enforced carries enforcement-kind evidence"
assert_contains "probe digests are checked against the tree" "$out" "probe digest still matches"

# --- a role that requires a capability ----------------------------------------
# Built by mutating a copy of the canonical roles: the canonical set requires no
# capabilities, and this milestone does not change that.
mkroot() { # mkroot CAPABILITY -> prints a distribution root
  _r="$(sandbox_new)/root"
  mkdir -p "$_r"
  cp -r "$REPO_ROOT/roles" "$REPO_ROOT/contracts" "$REPO_ROOT/skills" "$REPO_ROOT/rules" "$_r/"
  python3 -c "
import json, sys
p = sys.argv[1] + '/roles/review.json'
d = json.load(open(p, encoding='utf-8'))
d['required_capabilities'] = [sys.argv[2]] if sys.argv[2] else []
json.dump(d, open(p, 'w', encoding='utf-8'))" "$_r" "$1"
  printf '%s\n' "$_r"
}

render_into() { # render_into ROOT TARGET [extra args...]
  _root="$1"; _target="$2"; shift 2
  $RENDER --runtime claude --root "$_root" --target "$_target" --config "$CFG" --apply "$@" 2>&1
}

# 1. verified required capability -> render succeeds
R_ENF="$(mkroot tool-isolation)"
T="$(sandbox_new)"
out="$(render_into "$R_ENF" "$T" --capabilities "$MEASURED" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an enforced capability lets the role render" 0 "$rc"
assert_file_exists "…and the role is written" "$T/agents/review.md"
# Rendered roles now land in one of two places: an authorized role is installed
# as an agent, an unauthorized one is written as a template outside the
# runtime's discovery path. The whole set is still rendered either way.
n="$(find "$T/agents" "$T/.agent-skills/templates/claude" -name '*.md' \
      ! -name README.md 2>/dev/null | grep -c .)"
assert_eq "…along with the rest of the set" 14 "$n"
assert_file_absent "…and an unauthorized role is not installed as an agent" "$T/agents/planning.md"

# 10. a role requiring nothing still renders, with no record at all
R_NONE="$(mkroot '')"
T2="$(sandbox_new)"
out="$(render_into "$R_NONE" "$T2")"; rc=$?
assert_eq "a role requiring no capability renders without a record" 0 "$rc"
assert_eq "…and the whole canonical set renders" 14 \
  "$(find "$T2/agents" "$T2/.agent-skills/templates/claude" -name '*.md' \
      ! -name README.md 2>/dev/null | grep -c .)"

# 3. capability unmeasured -> refused
T3="$(sandbox_new)"
UNMEASURED="$(sandbox_new)/unmeasured.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['capabilities']['tool-isolation'] = {'state': 'unmeasured', 'reason': 'no probe run on this host'}
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$UNMEASURED"
out="$(render_into "$R_ENF" "$T3" --capabilities "$UNMEASURED" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an unmeasured capability is refused" 2 "$rc"
assert_contains "…and the reason is preserved" "$out" "no probe run on this host"
assert_eq "…leaving nothing written" 0 "$(find "$T3" -type f 2>/dev/null | wc -l)"

# 4. capability missing from the record -> refused
T4="$(sandbox_new)"
MISSING="$(sandbox_new)/missing.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['capabilities'].pop('tool-isolation')
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$MISSING"
out="$(render_into "$R_ENF" "$T4" --capabilities "$MISSING" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "a capability absent from the record is refused" 2 "$rc"
assert_contains "…as unknown, not as false" "$out" "unknown, and unknown fails closed"

# 2. capability explicitly unavailable -> refused
# Built by mutation: no shipped record claims `unavailable` any more, since the
# probe that once justified that state measured read confinement rather than
# workspace allocation (see DR-0004).
UNAVAILABLE="$(sandbox_new)/unavailable.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
cap = d['capabilities']['tool-isolation']
cap['state'] = 'unavailable'
for e in cap['evidence']:
    e['kind'] = 'observation'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$UNAVAILABLE"
T5="$(sandbox_new)"
out="$(render_into "$R_ENF" "$T5" --capabilities "$UNAVAILABLE" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "a capability measured unavailable is refused" 2 "$rc"
assert_contains "…and says it was measured absent" "$out" "measured as unavailable"
assert_eq "…leaving nothing written" 0 "$(find "$T5" -type f 2>/dev/null | wc -l)"

# 12. observed-but-not-enforced cannot satisfy tool isolation
T6="$(sandbox_new)"
OBSERVED="$(sandbox_new)/observed.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
cap = d['capabilities']['tool-isolation']
cap['state'] = 'observed'
for e in cap['evidence']:
    e['kind'] = 'observation'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$OBSERVED"
out="$(render_into "$R_ENF" "$T6" --capabilities "$OBSERVED" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "observed-but-unenforced does not satisfy tool-isolation" 2 "$rc"
assert_contains "…because compliance is not enforcement" "$out" "model compliance is not runtime enforcement"

# …while the same evidence level does satisfy an observation-level capability.
R_SPAWN="$(mkroot spawn)"
T7="$(sandbox_new)"
out="$(render_into "$R_SPAWN" "$T7" --capabilities "$MEASURED" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an observation-level capability is satisfied by observation" 0 "$rc"

# 11. configured/documented-only evidence cannot satisfy anything
T8="$(sandbox_new)"
DOCUMENTED="$(sandbox_new)/documented.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['capabilities']['tool-isolation'] = {'state': 'documented', 'source': 'vendor docs, sandbox section'}
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$DOCUMENTED"
out="$(render_into "$R_ENF" "$T8" --capabilities "$DOCUMENTED" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "documented-only evidence is refused" 2 "$rc"
assert_contains "…because documentation is not observation" "$out" "documentation is not an observation"

# 5. wrong runtime version -> refused
T9="$(sandbox_new)"
out="$(render_into "$R_ENF" "$T9" --capabilities "$MEASURED" --runtime-version 2.2.0 --platform windows)"; rc=$?
assert_eq "a record measured on another version is refused" 2 "$rc"
assert_contains "…and says why" "$out" "does not carry to another"

# 6. wrong platform -> refused
T10="$(sandbox_new)"
out="$(render_into "$R_ENF" "$T10" --capabilities "$MEASURED" --runtime-version 2.1.220 --platform linux)"; rc=$?
assert_eq "a record measured on another platform is refused" 2 "$rc"
assert_contains "…and says why" "$out" "does not certify another"

# wrong runtime family -> refused
T11="$(sandbox_new)"
out="$($RENDER --runtime codex --root "$R_ENF" --target "$T11" --config "$CFG" \
        --capabilities "$MEASURED" --apply 2>&1)"; rc=$?
assert_eq "a record for another runtime family is refused" 2 "$rc"
assert_contains "…and says why" "$out" "proves nothing about another runtime"

# 7. malformed record -> refused
T12="$(sandbox_new)"
BAD="$(sandbox_new)/bad.json"
printf '{ this is not json' > "$BAD"
out="$(render_into "$R_ENF" "$T12" --capabilities "$BAD" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "a malformed record is refused" 2 "$rc"
assert_contains "…as invalid JSON" "$out" "invalid JSON"

# 8. unsupported record version -> refused
T13="$(sandbox_new)"
STALE="$(sandbox_new)/stale.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['record_version'] = 99
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$STALE"
out="$(render_into "$R_ENF" "$T13" --capabilities "$STALE" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an unsupported record version is refused" 2 "$rc"
assert_contains "…without reinterpreting it" "$out" "implements 2 exactly"

# a fixture must never satisfy a requirement, whatever it claims
T14="$(sandbox_new)"
FIXTURE="$(sandbox_new)/fixture.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['status'] = 'example'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$FIXTURE"
out="$(render_into "$R_ENF" "$T14" --capabilities "$FIXTURE" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an example record cannot satisfy a requirement" 2 "$rc"
assert_contains "…even claiming enforcement" "$out" "did not pass canonical capability validation"

# Codex, today: the unmeasured fixture refuses every capability requirement.
T15="$(sandbox_new)"
out="$($RENDER --runtime codex --root "$R_ENF" --target "$T15" --config "$CFG" \
        --capabilities "$EXAMPLE" --apply 2>&1)"; rc=$?
assert_eq "the Codex fixture satisfies nothing" 2 "$rc"
assert_eq "…and writes nothing" 0 "$(find "$T15" -type f 2>/dev/null | wc -l)"

# workspace-isolation is unmeasured in the shipped record: the probe that once
# backed a verdict measured a different property. A role requiring it is refused.
R_WS="$(mkroot workspace-isolation)"
T_WS="$(sandbox_new)"
out="$(render_into "$R_WS" "$T_WS" --capabilities "$MEASURED" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an unmeasured capability is refused" 2 "$rc"
assert_contains "…citing the reason recorded for it" "$out" "separate writable workspace"
assert_eq "…leaving nothing written" 0 "$(find "$T_WS" -type f 2>/dev/null | wc -l)"

# A record cannot authorise an evidence-dependent render for an unnamed target.
T_ID="$(sandbox_new)"
out="$(render_into "$R_ENF" "$T_ID" --capabilities "$MEASURED")"; rc=$?
assert_eq "a record without a stated target is refused" 2 "$rc"
assert_contains "…because an optional flag cannot establish compatibility" "$out" "the target runtime must be identified"
assert_eq "…leaving nothing written" 0 "$(find "$T_ID" -type f 2>/dev/null | wc -l)"

# R3 regression: a label is not evidence.
T_EV="$(sandbox_new)"
NOEV="$(sandbox_new)/no-evidence.json"
python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['capabilities']['tool-isolation']['evidence'] = []
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))" "$MEASURED" "$NOEV"
out="$(render_into "$R_ENF" "$T_EV" --capabilities "$NOEV" --runtime-version 2.1.220 --platform windows)"; rc=$?
assert_eq "an enforced claim with no evidence is refused on the render path" 2 "$rc"
assert_contains "…by canonical record validation" "$out" "did not pass canonical capability validation"
assert_eq "…leaving nothing written" 0 "$(find "$T_EV" -type f 2>/dev/null | wc -l)"

# --- record semantics that the schema cannot express --------------------------
S="$(sandbox_new)"
semantic_fail() { # semantic_fail FILE LABEL NEEDLE
  _out="$($CAPVAL --semantic --record "$1" 2>&1)"; _rc=$?
  assert_ne "$2 is rejected" 0 "$_rc"
  assert_contains "…by the expected check" "$_out" "$3"
  $CAPVAL --schema --record "$1" >/dev/null 2>&1
  assert_eq "…while the schema alone accepts it" 0 $?
}

python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for e in d['capabilities']['tool-isolation']['evidence']:
    e['kind'] = 'observation'
json.dump(d, open(sys.argv[2] + '/enf-no-proof.json', 'w', encoding='utf-8'))
d2 = json.load(open(sys.argv[1], encoding='utf-8'))
d2['capabilities']['spawn']['evidence'][0]['probe_sha256'] = '0' * 64
json.dump(d2, open(sys.argv[2] + '/drifted.json', 'w', encoding='utf-8'))
d3 = json.load(open(sys.argv[1], encoding='utf-8'))
d3['capabilities']['spawn']['evidence'][0]['probe'] = 'tests/probes/does-not-exist.sh'
json.dump(d3, open(sys.argv[2] + '/absent-probe.json', 'w', encoding='utf-8'))
d4 = json.load(open(sys.argv[1], encoding='utf-8'))
d4['status'] = 'example'
json.dump(d4, open(sys.argv[2] + '/example-claiming.json', 'w', encoding='utf-8'))" "$MEASURED" "$S"

semantic_fail "$S/enf-no-proof.json"    "an enforced claim with only observation evidence" "enforcement-kind evidence"
semantic_fail "$S/drifted.json"         "evidence whose probe has since changed"           "probe digest still matches"
semantic_fail "$S/absent-probe.json"    "evidence citing a probe that does not exist"      "exists"
semantic_fail "$S/example-claiming.json" "an example claiming a measured state"            "claims no measured state"

t_summary
