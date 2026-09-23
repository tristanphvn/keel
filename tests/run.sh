#!/usr/bin/env bash
# Run every tests/test_*.sh. Exits non-zero if any file fails.
#
#   bash tests/run.sh              # all
#   bash tests/run.sh installer    # only files whose name contains "installer"
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
filter="${1:-}"

total_fail=0
ran=0
for f in "$ROOT"/tests/test_*.sh; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in
    *"$filter"*) ;;
    *) continue ;;
  esac
  ran=$((ran + 1))
  printf '\n== %s ==\n' "$(basename "$f")"
  bash "$f" || total_fail=$((total_fail + 1))
done

printf '\n'
if [ "$ran" -eq 0 ]; then
  echo "no test files matched '$filter'" >&2
  exit 2
fi
if [ "$total_fail" -eq 0 ]; then
  echo "TESTS: PASS ($ran file(s))"
  exit 0
fi
echo "TESTS: FAIL ($total_fail of $ran file(s))" >&2
exit 1
