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
for imp in $(grep -oE '@\{\{AGENT_HOME\}\}/(rules/[A-Za-z0-9._-]+|learned-rules\.md)' config/AGENTS.md | sed 's|@{{AGENT_HOME}}/||'); do
  case "$imp" in
    learned-rules.md) target="config/learned-rules.md" ;;
    *)                target="$imp" ;;
  esac
  if [ -f "$target" ]; then pass "$imp -> $target"; else bad "$imp -> $target missing in repo"; fi
done

echo "== 8. Portability: no machine-specific or vendor-locked paths =="
# The repo must stay agent-neutral and free of one developer's filesystem. Files
# that get installed use the {{AGENT_HOME}} token; nothing may hardcode a home
# directory, a drive letter, or a single vendor's config directory.
leak_patterns='(^|[^A-Za-z])(~|\$HOME)/\.[a-z-]+/(rules|skills|skill-registry)|[A-Za-z]:\\(Users|vault|personal)|/c/Users/'
leaks=$(git ls-files -z | xargs -0 grep -lE "$leak_patterns" 2>/dev/null | grep -v '^scripts/validate.sh$')
if [ -z "$leaks" ]; then
  pass "no hardcoded home, drive-letter, or vendor config paths"
else
  for f in $leaks; do bad "machine-specific or vendor-locked path in $f"; done
fi

# Installed files must not carry a raw absolute AGENT_HOME; they use the token.
raw=$(git ls-files rules skills registry config commands -z | xargs -0 grep -lE '\$AGENT_HOME' 2>/dev/null)
if [ -z "$raw" ]; then
  pass "installed files use the {{AGENT_HOME}} token, not a shell variable"
else
  for f in $raw; do bad "$f uses \$AGENT_HOME; installed files need {{AGENT_HOME}}"; done
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "VALIDATION: PASS"
else
  echo "VALIDATION: FAIL ($fail problem(s))"
fi
exit "$fail"
