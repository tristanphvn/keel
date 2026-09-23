#!/usr/bin/env bash
# Static validation of the rules/skills/registry architecture in this repo.
# Read-only: never writes, never touches $AGENT_HOME.
# Usage: bash scripts/validate.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
pass() { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  skip  %s\n' "$1"; }

echo "== 1. Rule files =="
expected_rules="00-operating-principles 10-scope-control 20-verification 30-intent-first 40-correction-learning 50-design 60-adversarial-consensus"
for r in $expected_rules; do
  if [ -f "rules/$r.md" ]; then pass "rules/$r.md"; else bad "rules/$r.md missing"; fi
done

echo "== 2. Rule IDs unique =="
ids=$(grep -hoE '^## (VERIFY|SCOPE|ROOT|CODE|TEST|API|REVIEW|CORRECTION|UI|CONSENSUS)-[0-9]+' rules/*.md | sed 's/^## //' | sort)
total=$(printf '%s\n' "$ids" | grep -c .)
uniq_total=$(printf '%s\n' "$ids" | sort -u | grep -c .)
dupes=$(printf '%s\n' "$ids" | uniq -d)
if [ "$total" -eq "$uniq_total" ] && [ -z "$dupes" ]; then
  pass "$total rule IDs defined, all unique"
else
  bad "duplicate rule IDs: $dupes"
fi

echo "== 3. Rule families present =="
for fam in VERIFY SCOPE ROOT CODE TEST API REVIEW CORRECTION UI CONSENSUS; do
  n=$(printf '%s\n' "$ids" | grep -c "^$fam-" || true)
  if [ "$n" -gt 0 ]; then pass "$fam ($n)"; else bad "$fam family missing"; fi
done

echo "== 4. Skill frontmatter =="
for d in skills/*/; do
  name=$(basename "$d")
  f="$d/SKILL.md"
  if [ ! -f "$f" ]; then bad "$name has no SKILL.md"; continue; fi
  if [ "$(head -n1 "$f")" != "---" ]; then bad "$name: frontmatter does not open on line 1"; continue; fi
  fm_name=$(sed -n '2,10p' "$f" | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//')
  has_desc=$(sed -n '2,10p' "$f" | grep -c '^description:' || true)
  if [ "$fm_name" != "$name" ]; then bad "$name: frontmatter name is '$fm_name'"; continue; fi
  if [ "$has_desc" -eq 0 ]; then bad "$name: no description in frontmatter"; continue; fi
  pass "$name"
done

echo "== 5. Registry <-> skills on disk =="
# Only `status: active` entries must resolve to a directory (prefer id, fall back to
# legacy_name). `draft` = planned, `replaced`/`deprecated` = intentionally absent.
reg_entries=$(awk '
  /^  - id:/        { if (id != "") print id"|"legacy"|"status; id=$3; legacy=""; status="" }
  /^    legacy_name:/ { legacy=$2 }
  /^    status:/      { status=$2 }
  END               { if (id != "") print id"|"legacy"|"status }
' registry/registry.yaml)

n_active=0; n_planned=0
while IFS='|' read -r id legacy status; do
  [ -z "$id" ] && continue
  if [ "$status" != "active" ]; then
    n_planned=$((n_planned + 1))
    if [ -d "skills/$id" ] || { [ -n "$legacy" ] && [ -d "skills/$legacy" ]; }; then
      bad "$id: status '$status' but a skill directory still exists (stale trigger surface)"
    fi
    continue
  fi
  n_active=$((n_active + 1))
  if   [ -d "skills/$id" ];                        then pass "$id -> skills/$id (migrated)"
  elif [ -n "$legacy" ] && [ -d "skills/$legacy" ]; then pass "$id -> skills/$legacy (legacy name, not yet migrated)"
  else bad "$id: active but no directory skills/$id or skills/$legacy"
  fi
done <<< "$reg_entries"
pass "$n_active active entries checked; $n_planned non-active (draft/replaced) skipped"

echo "== 5b. Skill dirs <-> registry (no orphans) =="
for d in skills/*/; do
  name=$(basename "$d")
  if printf '%s\n' "$reg_entries" | grep -qE "^$name\||\|$name\|"; then
    pass "$name has a registry entry"
  else
    bad "$name on disk but absent from registry/registry.yaml"
  fi
done

echo "== 6. Registry rule references resolve =="
for rid in $(grep -hoE '(VERIFY|SCOPE|ROOT|CODE|TEST|API|REVIEW|CORRECTION|UI|CONSENSUS)-[0-9]+' registry/registry.yaml | sort -u); do
  if printf '%s\n' "$ids" | grep -qx "$rid"; then pass "$rid defined in rules/"; else bad "$rid referenced by registry but not defined in rules/"; fi
done

echo "== 7. config/AGENTS.md imports resolve =="
# 7a. every import must resolve to a file in the repo.
imports=$(grep -oE '@\{\{AGENT_HOME\}\}/(rules/[A-Za-z0-9._-]+|learned-rules\.md)' config/AGENTS.md | sed 's|@{{AGENT_HOME}}/||' | sort -u)
n_imports=$(printf '%s\n' "$imports" | grep -c .)
for imp in $imports; do
  case "$imp" in
    learned-rules.md) target="config/learned-rules.md" ;;
    *)                target="$imp" ;;
  esac
  if [ -f "$target" ]; then pass "$imp -> $target"; else bad "$imp -> $target missing in repo"; fi
done

# 7b. An entrypoint with no imports at all used to pass this section vacuously:
# the loop simply never ran. The entrypoint is the only thing that loads the
# rules on a runtime without directory auto-discovery, so empty is a failure.
if [ "$n_imports" -eq 0 ]; then
  bad "config/AGENTS.md imports nothing — the rule files would never load"
else
  pass "$n_imports import(s) declared"
fi

# 7c. The reverse direction: a rule file that exists but is imported by nothing
# is dead weight on those runtimes. Catches "added a rule, forgot the import".
for f in rules/*.md; do
  if printf '%s\n' "$imports" | grep -qx "$f"; then pass "$f is imported"; else bad "$f exists but config/AGENTS.md never imports it"; fi
done
if printf '%s\n' "$imports" | grep -qx "learned-rules.md"; then pass "learned-rules.md is imported"; else bad "config/learned-rules.md exists but is never imported"; fi

echo "== 8. Portability: no machine-specific or vendor-locked paths =="
# Two different rules, because two different things are being protected.
#
# 8a. One developer's filesystem must not appear anywhere in the repo. A drive
#     letter or a literal user directory is a leak no matter which file it is in.
machine_patterns='[A-Za-z]:\\(Users|vault|personal)|/c/Users/'
leaks=$(git ls-files -z | xargs -0 grep -lE "$machine_patterns" 2>/dev/null | grep -v '^scripts/validate.sh$')
if [ -z "$leaks" ]; then
  pass "no hardcoded drive-letter or user-directory paths"
else
  for f in $leaks; do bad "machine-specific path in $f"; done
fi

# 8b. INSTALLED content must additionally stay vendor-neutral: it is shared by
#     every runtime and resolves through {{AGENT_HOME}}. Adapters, their docs and
#     the routing layer are exempt by definition — naming a runtime's own
#     configuration directory is precisely their job, and a check that forbade it
#     would only be satisfied by making the adapters wrong.
vendor_pattern='(^|[^A-Za-z])(~|\$HOME)/\.[a-z-]+/(rules|skills|skill-registry|agents)'
vendor_leaks=$(git ls-files rules skills registry commands \
                 config/AGENTS.md config/learned-rules.md -z \
               | xargs -0 grep -lE "$vendor_pattern" 2>/dev/null)
if [ -z "$vendor_leaks" ]; then
  pass "installed content names no vendor configuration directory"
else
  for f in $vendor_leaks; do bad "vendor-locked path in installed file $f"; done
fi

# Installed files must not carry a raw absolute AGENT_HOME; they use the token.
# Scoped to what install.sh and the adapters actually write: the rest of config/
# is repo-only documentation, which is free to name the $AGENT_HOME variable.
raw=$(git ls-files rules skills registry commands \
        config/AGENTS.md config/learned-rules.md config/claude/CLAUDE.md.block -z \
      | xargs -0 grep -lE '\$AGENT_HOME' 2>/dev/null)
if [ -z "$raw" ]; then
  pass "installed files use the {{AGENT_HOME}} token, not a shell variable"
else
  for f in $raw; do bad "$f uses \$AGENT_HOME; installed files need {{AGENT_HOME}}"; done
fi

echo "== 9. YAML parses under a standard parser =="
# grep/awk accept files a real parser rejects. registry.yaml and every SKILL.md
# frontmatter are consumed as YAML by other tools, so they must actually parse.
yamllint_py='
import sys, io
try:
    import yaml
except ImportError:
    sys.exit(97)
ok = True
try:
    with io.open("registry/registry.yaml", encoding="utf-8") as fh:
        yaml.safe_load(fh)
    print("ok    registry/registry.yaml")
except Exception as e:
    print("FAIL  registry/registry.yaml: %s" % str(e).replace("\n", " ")); ok = False
import glob
for path in sorted(glob.glob("skills/*/SKILL.md")):
    with io.open(path, encoding="utf-8") as fh:
        text = fh.read()
    if not text.startswith("---"):
        print("FAIL  %s: no frontmatter" % path); ok = False; continue
    parts = text.split("---", 2)
    try:
        data = yaml.safe_load(parts[1])
    except Exception as e:
        print("FAIL  %s: %s" % (path, str(e).replace("\n", " "))); ok = False; continue
    if not isinstance(data, dict) or "name" not in data:
        print("FAIL  %s: frontmatter has no name" % path); ok = False; continue
    print("ok    %s" % path)
sys.exit(0 if ok else 1)
'
if command -v python3 >/dev/null 2>&1; then
  yaml_out=$(cd "$ROOT" && python3 -c "$yamllint_py" 2>&1); yaml_rc=$?
  if [ "$yaml_rc" -eq 97 ]; then
    skip "no YAML module (pip install pyyaml) — registry and frontmatter unparsed"
  else
    printf '%s\n' "$yaml_out" | while IFS= read -r line; do printf '  %s\n' "$line"; done
    [ "$yaml_rc" -eq 0 ] || bad "YAML parse errors above"
  fi
else
  skip "no python3 — registry and frontmatter unparsed"
fi

echo "== 10. Contract documents =="
# Shape and semantics are two separate results. An unavailable validator is
# reported as unavailable — never counted as a pass.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import jsonschema" 2>/dev/null; then
    if out=$(python3 scripts/contracts/validate.py --schema 2>&1); then
      pass "contract documents satisfy the JSON Schema"
    else
      bad "schema validation failed: $(printf '%s' "$out" | grep -m1 FAIL)"
    fi
  else
    skip "no jsonschema module (pip install jsonschema) — contract shape unvalidated"
  fi
  # Both canonical pairs: the blocked example and the completed one. The
  # completed pair is what exercises evidence, acceptance and delivery
  # semantics, so it must keep passing or it silently rots.
  for pair in "task:result" "task-completed:result-completed"; do
    t="contracts/examples/${pair%%:*}.json"
    r="contracts/examples/${pair##*:}.json"
    if out=$(python3 scripts/contracts/validate.py --semantic --task "$t" --result "$r" 2>&1); then
      pass "semantic checks pass for $(basename "$r")"
    else
      bad "semantic validation failed for $(basename "$r"): $(printf '%s' "$out" | grep -m1 FAIL)"
    fi
  done
else
  skip "no python3 — contract documents unvalidated"
fi

echo "== 11. Runtime capability records =="
# Shape and semantics separately, as with the contract. Validating a record is
# not measuring a runtime: nothing here re-runs a probe.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import jsonschema" 2>/dev/null; then
    if out=$(python3 scripts/capabilities/validate.py --schema 2>&1); then
      pass "capability records satisfy the record schema"
    else
      bad "capability schema validation failed: $(printf '%s' "$out" | grep -m1 FAIL)"
    fi
  else
    skip "no jsonschema module — capability record shape unvalidated"
  fi
  if out=$(python3 scripts/capabilities/validate.py --semantic 2>&1); then
    pass "capability records satisfy the semantic checks"
  else
    bad "capability semantic validation failed: $(printf '%s' "$out" | grep -m1 FAIL)"
  fi
else
  skip "no python3 — capability records unvalidated"
fi

echo "== 12. Routing configuration =="
# The example is what a user copies, so it has to keep rendering the canonical
# role set. Rendering is a dry run into a throwaway directory.
if command -v python3 >/dev/null 2>&1; then
  routing_tmp="$(mktemp -d)"
  for cfg in config/routing/models.example.yaml config/routing/models.yaml; do
    [ -f "$cfg" ] || continue
    for rt in claude codex; do
      if out=$(python3 scripts/routing/render.py --runtime "$rt" --config "$cfg" --target "$routing_tmp" 2>&1); then
        pass "$cfg renders for $rt"
      else
        bad "$cfg fails schema validation for $rt: $(printf '%s' "$out" | grep -m1 'schema error\|FATAL')"
      fi
    done
  done
  rm -rf "$routing_tmp"
else
  skip "no python3 — routing configuration unvalidated"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "VALIDATION: PASS"
else
  echo "VALIDATION: FAIL ($fail problem(s))"
fi
exit "$fail"
