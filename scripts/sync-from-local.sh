#!/usr/bin/env bash
# Pull the live machine config back into this repo (machine -> repo).
#
#   bash scripts/sync-from-local.sh            # dry run
#   bash scripts/sync-from-local.sh --apply    # copies into the working tree
#
# Writes only into the repo working tree. Never touches ~/.claude. Review with
# `git diff` afterwards — this script does not stage, commit, or push.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${CLAUDE_HOME:-$HOME/.claude}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# machine path -> repo path
PAIRS="
rules|rules
skills|skills
skill-registry|registry
commands|commands
CLAUDE.md|config/CLAUDE.md
learned-rules.md|config/learned-rules.md
"

echo "machine: $SRC"
echo "repo:    $ROOT"
[ "$APPLY" -eq 1 ] && echo "mode:    APPLY" || echo "mode:    DRY RUN (pass --apply to write)"
echo

changed=0
for pair in $PAIRS; do
  src="$SRC/${pair%%|*}"
  dst="$ROOT/${pair#*|}"
  [ -e "$src" ] || { echo "skip (not on machine): ${pair%%|*}"; continue; }

  if [ -d "$src" ]; then
    while IFS= read -r f; do
      rel="${f#"$src"/}"
      target="$dst/$rel"
      if [ ! -f "$target" ]; then
        echo "  NEW       ${pair#*|}/$rel"; changed=$((changed + 1))
      elif ! cmp -s "$f" "$target"; then
        echo "  UPDATED   ${pair#*|}/$rel"; changed=$((changed + 1))
      fi
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$(dirname "$target")"
        cp "$f" "$target"
      fi
    done < <(find "$src" -type f)

    # A skill deleted on the machine (e.g. after a rename) still sits in the repo.
    while IFS= read -r f; do
      rel="${f#"$dst"/}"
      [ -f "$src/$rel" ] || echo "  REPO-ONLY (delete by hand if intended) ${pair#*|}/$rel"
    done < <(find "$dst" -type f 2>/dev/null)
  else
    if [ ! -f "$dst" ]; then
      echo "  NEW       ${pair#*|}"; changed=$((changed + 1))
    elif ! cmp -s "$src" "$dst"; then
      echo "  UPDATED   ${pair#*|}"; changed=$((changed + 1))
    fi
    [ "$APPLY" -eq 1 ] && { mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; }
  fi
done

echo
echo "$changed file(s) differ."
if [ "$APPLY" -eq 1 ]; then
  echo "Copied into the working tree. Now: bash scripts/validate.sh && git diff"
else
  echo "Nothing written. Re-run with --apply to sync."
fi
