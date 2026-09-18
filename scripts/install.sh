#!/usr/bin/env bash
# Install this repo's architecture into ~/.claude (repo -> machine).
#
#   bash scripts/install.sh            # dry run: shows exactly what would change
#   bash scripts/install.sh --apply    # performs the copy, after backing up
#
# Never deletes. Files present on the machine but absent from the repo are left
# alone and reported, so a local-only skill is never silently destroyed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# repo path -> destination path
PAIRS="
rules|$DEST/rules
skills|$DEST/skills
registry|$DEST/skill-registry
commands|$DEST/commands
config/CLAUDE.md|$DEST/CLAUDE.md
config/learned-rules.md|$DEST/learned-rules.md
"

echo "repo:        $ROOT"
echo "destination: $DEST"
[ "$APPLY" -eq 1 ] && echo "mode:        APPLY" || echo "mode:        DRY RUN (pass --apply to write)"
echo

if [ "$APPLY" -eq 1 ]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$DEST/backups/install-$stamp"
  mkdir -p "$backup"
  echo "backup:      $backup"
  for pair in $PAIRS; do
    dst="${pair#*|}"
    [ -e "$dst" ] && cp -r "$dst" "$backup/" 2>/dev/null
  done
  echo
fi

changed=0
for pair in $PAIRS; do
  src="$ROOT/${pair%%|*}"
  dst="${pair#*|}"
  [ -e "$src" ] || { echo "skip (not in repo): ${pair%%|*}"; continue; }

  if [ -d "$src" ]; then
    mkdir -p "$dst"
    while IFS= read -r f; do
      rel="${f#"$src"/}"
      target="$dst/$rel"
      if [ ! -f "$target" ]; then
        echo "  NEW      $target"; changed=$((changed + 1))
      elif ! cmp -s "$f" "$target"; then
        echo "  OVERWRITE $target"; changed=$((changed + 1))
      fi
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$(dirname "$target")"
        cp "$f" "$target"
      fi
    done < <(find "$src" -type f)

    # Report machine-only files; never delete them.
    while IFS= read -r f; do
      rel="${f#"$dst"/}"
      [ -f "$src/$rel" ] || echo "  LOCAL-ONLY (kept, not in repo) $f"
    done < <(find "$dst" -type f 2>/dev/null)
  else
    if [ ! -f "$dst" ]; then
      echo "  NEW      $dst"; changed=$((changed + 1))
    elif ! cmp -s "$src" "$dst"; then
      echo "  OVERWRITE $dst"; changed=$((changed + 1))
    fi
    [ "$APPLY" -eq 1 ] && { mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; }
  fi
done

echo
echo "$changed file(s) would change."
if [ "$APPLY" -eq 1 ]; then
  echo "Applied. Restart Claude Code so the rule imports and skill list reload."
else
  echo "Nothing written. Re-run with --apply to install."
fi
