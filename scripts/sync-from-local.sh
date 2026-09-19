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
# Review with `git status --untracked-files=all` and `git diff` afterwards —
# this script does not stage, commit, or push.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${AGENT_HOME:-$HOME/.agent}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# machine path RELATIVE to $SRC | repo path relative to $ROOT.
# Both sides stay relative so neither $SRC nor $ROOT is ever word-split.
PAIRS="
rules|rules
skills|skills
skill-registry|registry
commands|commands
AGENTS.md|config/AGENTS.md
learned-rules.md|config/learned-rules.md
"

# $SRC is spliced into a sed s/// command as the PATTERN, so it is compiled as a
# basic regular expression. Escape every BRE metacharacter and the | delimiter,
# otherwise a path like /home/me/.agent matches /home/me/Xagent as well.
SRC_ESC="$(printf '%s' "$SRC" | sed -e 's/[][\.*^$|]/\\&/g')"

# Print a machine file with the real path folded back to {{AGENT_HOME}}.
# LC_ALL=C stops sed aborting on a non-UTF-8 byte; a file sed would treat as
# binary is copied through verbatim rather than pattern-matched.
unrender() {
  if LC_ALL=C grep -Iq . "$1" 2>/dev/null; then
    LC_ALL=C sed "s|$SRC_ESC|{{AGENT_HOME}}|g" "$1"
  else
    cat "$1"
  fi
}

write_unrendered() {
  _src="$1"; _dst="$2"; _tmp="$2.sync-tmp.$$"
  mkdir -p "$(dirname "$_dst")" || return 1
  unrender "$_src" > "$_tmp" || { rm -f "$_tmp"; return 1; }
  mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; return 1; }
}

echo "machine: $SRC"
echo "repo:    $ROOT"
[ "$APPLY" -eq 1 ] && echo "mode:    APPLY" || echo "mode:    DRY RUN (pass --apply to write)"
echo

changed=0
failed=0
while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  src="$SRC/${pair%%|*}"
  dst="$ROOT/${pair#*|}"
  [ -e "$src" ] || { echo "skip (not on machine): ${pair%%|*}"; continue; }

  # A config subdirectory that is its own checkout would otherwise be ingested
  # wholesale — object database included — and land in this repo as content.
  if [ -e "$src/.git" ]; then
    echo "REFUSED: $src is a separate git checkout; not syncing it wholesale." >&2
    failed=$((failed + 1)); continue
  fi

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
        write_unrendered "$f" "$target" || { echo "  FAILED    ${pair#*|}/$rel"; failed=$((failed + 1)); }
      fi
    done < <(find "$src" -type f -not -path '*/.git/*' -not -name '.DS_Store')

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
      write_unrendered "$src" "$dst" || { echo "  FAILED    ${pair#*|}"; failed=$((failed + 1)); }
    fi
  fi
done <<EOF
$PAIRS
EOF

echo
echo "$changed file(s) differ."
if [ "$failed" -gt 0 ]; then
  echo "$failed path(s) FAILED or were refused." >&2
  exit 1
fi
if [ "$APPLY" -eq 1 ]; then
  echo "Copied into the working tree. Now: bash scripts/validate.sh && git status --untracked-files=all && git diff"
else
  echo "Nothing written. Re-run with --apply to sync."
fi
