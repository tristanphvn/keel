#!/usr/bin/env bash
# Pull the live machine config back into this repo (machine -> repo).
#
#   AGENT_HOME=~/.your-agent bash scripts/sync-from-local.sh            # dry run
#   AGENT_HOME=~/.your-agent bash scripts/sync-from-local.sh --apply    # copies into the working tree
#
# The reverse of install.sh: absolute paths pointing at AGENT_HOME are folded
# back into the literal token {{AGENT_HOME}}, so syncing never reintroduces
# machine-specific paths into the repo.
#
# Writes only into the repo working tree. Never touches the agent config home.
# Review with `git diff` afterwards — this script does not stage, commit, or push.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${AGENT_HOME:-$HOME/.agent}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# machine path -> repo path
PAIRS="
rules|rules
skills|skills
skill-registry|registry
commands|commands
AGENTS.md|config/AGENTS.md
learned-rules.md|config/learned-rules.md
"

# Print a machine file with the real path folded back to {{AGENT_HOME}}.
unrender() { sed "s|$SRC|{{AGENT_HOME}}|g" "$1"; }

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
      elif ! unrender "$f" | cmp -s - "$target"; then
        echo "  UPDATED   ${pair#*|}/$rel"; changed=$((changed + 1))
      fi
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$(dirname "$target")"
        unrender "$f" > "$target"
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
    elif ! unrender "$src" | cmp -s - "$dst"; then
      echo "  UPDATED   ${pair#*|}"; changed=$((changed + 1))
    fi
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$(dirname "$dst")"
      unrender "$src" > "$dst"
    fi
  fi
done

echo
echo "$changed file(s) differ."
if [ "$APPLY" -eq 1 ]; then
  echo "Copied into the working tree. Now: bash scripts/validate.sh && git diff"
else
  echo "Nothing written. Re-run with --apply to sync."
fi
