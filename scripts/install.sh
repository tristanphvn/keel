#!/usr/bin/env bash
# Install this repo's architecture into the agent config home (repo -> machine).
#
#   AGENT_HOME=~/.your-agent bash scripts/install.sh            # dry run
#   AGENT_HOME=~/.your-agent bash scripts/install.sh --apply    # writes, after backing up
#
# AGENT_HOME must point at the configuration directory your coding agent reads.
# Defaults to ~/.agent, which is deliberately neutral: if your agent uses another
# directory, set AGENT_HOME rather than editing this script.
#
# Files carry the literal token {{AGENT_HOME}} wherever they need an absolute
# path. It is rendered to the real destination on the way in, so the repo stays
# free of machine-specific paths.
#
# Never deletes. Files present on the machine but absent from the repo are left
# alone and reported, so a local-only skill is never silently destroyed.
#
# Exits non-zero if any write or any backup fails. A dry run writes nothing at all.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${AGENT_HOME:-$HOME/.agent}"
# The skills tree can be installed somewhere other than $AGENT_HOME/skills, for a
# machine where that directory is already owned by something else (a separate
# checkout, for instance). The runtime still has to SEE them at its own skills
# path — an adapter links them into place. {{AGENT_HOME}} still renders to $DEST,
# because the tokens inside skills point at rules/, skill-registry/ and logs/.
SKILLS_DEST="${AGENT_SKILLS_DIR:-$DEST/skills}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# repo path | destination path RELATIVE to $DEST.
# The destination is kept relative on purpose: $DEST is never word-split, so a
# configuration directory containing spaces installs correctly.
PAIRS="
rules|rules
skills|skills
registry|skill-registry
commands|commands
config/AGENTS.md|AGENTS.md
config/learned-rules.md|learned-rules.md
"

# Map a PAIRS destination (relative to $DEST) to its real absolute path.
resolve_dst() {
  if [ "$1" = "skills" ]; then printf '%s' "$SKILLS_DEST"; else printf '%s/%s' "$DEST" "$1"; fi
}

# Extra files backed up but never written by this script. They belong to the
# machine, not the repo, and an adapter may edit them afterwards — so a restore
# point has to exist before anything else runs.
BACKUP_EXTRA="CLAUDE.md settings.json hooks"

# $DEST is substitution REPLACEMENT text, not a pattern: escape the characters
# sed treats specially there (backslash, the | delimiter, and & = "whole match").
DEST_ESC="$(printf '%s' "$DEST" | sed -e 's/[\\&|]/\\&/g')"

# Print a repo file with {{AGENT_HOME}} rendered to the real destination path.
# LC_ALL=C stops sed aborting on a non-UTF-8 byte; a file sed would treat as
# binary is copied through verbatim rather than pattern-matched.
render() {
  if LC_ALL=C grep -Iq . "$1" 2>/dev/null; then
    LC_ALL=C sed "s|{{AGENT_HOME}}|$DEST_ESC|g" "$1"
  else
    cat "$1"
  fi
}

# Render to a temporary file and move it into place, so a failed write leaves the
# previous content intact instead of a truncated file.
write_rendered() {
  _src="$1"; _dst="$2"; _tmp="$2.install-tmp.$$"
  mkdir -p "$(dirname "$_dst")" || return 1
  render "$_src" > "$_tmp" || { rm -f "$_tmp"; return 1; }
  mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; return 1; }
}

echo "repo:        $ROOT"
echo "destination: $DEST"
[ "$SKILLS_DEST" = "$DEST/skills" ] || echo "skills:      $SKILLS_DEST (AGENT_SKILLS_DIR override)"
[ "$APPLY" -eq 1 ] && echo "mode:        APPLY" || echo "mode:        DRY RUN (pass --apply to write)"
echo

if [ "$APPLY" -eq 1 ]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$DEST/backups/install-$stamp"
  mkdir -p "$backup" || { echo "FATAL: cannot create backup directory $backup" >&2; exit 1; }
  echo "backup:      $backup"

  # Back up everything this run could overwrite, plus the machine-owned files an
  # adapter may touch. A failed backup aborts before any write.
  while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    dst="$(resolve_dst "${pair#*|}")"
    [ -e "$dst" ] || continue
    cp -R "$dst" "$backup/" || { echo "FATAL: backup of $dst failed" >&2; exit 1; }
  done <<EOF
$PAIRS
EOF
  for extra in $BACKUP_EXTRA; do
    [ -e "$DEST/$extra" ] || continue
    cp -R "$DEST/$extra" "$backup/" || { echo "FATAL: backup of $DEST/$extra failed" >&2; exit 1; }
  done

  # Verify the backup before trusting it: every backed-up path must compare equal.
  while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    dst="$(resolve_dst "${pair#*|}")"
    [ -e "$dst" ] || continue
    diff -r "$dst" "$backup/$(basename "$dst")" >/dev/null 2>&1 \
      || { echo "FATAL: backup of $dst did not verify" >&2; exit 1; }
  done <<EOF
$PAIRS
EOF
  for extra in $BACKUP_EXTRA; do
    [ -e "$DEST/$extra" ] || continue
    diff -r "$DEST/$extra" "$backup/$(basename "$extra")" >/dev/null 2>&1 \
      || { echo "FATAL: backup of $extra did not verify" >&2; exit 1; }
  done
  echo "backup:      verified"
  echo
fi

changed=0
failed=0
while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  src="$ROOT/${pair%%|*}"
  dst="$(resolve_dst "${pair#*|}")"
  [ -e "$src" ] || { echo "skip (not in repo): ${pair%%|*}"; continue; }

  # A symlinked destination would move the write outside $AGENT_HOME.
  if [ -L "$dst" ]; then
    echo "  REFUSED (symlink leaves \$AGENT_HOME) $dst"; failed=$((failed + 1)); continue
  fi

  if [ -d "$src" ]; then
    [ "$APPLY" -eq 1 ] && { mkdir -p "$dst" || { echo "FATAL: cannot create $dst" >&2; exit 1; }; }
    while IFS= read -r f; do
      rel="${f#"$src"/}"
      target="$dst/$rel"
      if [ ! -f "$target" ]; then
        echo "  NEW      $target"; changed=$((changed + 1))
      elif ! render "$f" | cmp -s - "$target"; then
        echo "  OVERWRITE $target"; changed=$((changed + 1))
      fi
      if [ "$APPLY" -eq 1 ]; then
        write_rendered "$f" "$target" || { echo "  FAILED   $target"; failed=$((failed + 1)); }
      fi
    done < <(find "$src" -type f)

    # Report machine-only files; never delete them. .git is skipped: a config
    # directory that is also a checkout would otherwise bury the real output.
    while IFS= read -r f; do
      rel="${f#"$dst"/}"
      [ -f "$src/$rel" ] || echo "  LOCAL-ONLY (kept, not in repo) $f"
    done < <(find "$dst" -type f -not -path '*/.git/*' 2>/dev/null)
  else
    if [ ! -f "$dst" ]; then
      echo "  NEW      $dst"; changed=$((changed + 1))
    elif ! render "$src" | cmp -s - "$dst"; then
      echo "  OVERWRITE $dst"; changed=$((changed + 1))
    fi
    if [ "$APPLY" -eq 1 ]; then
      write_rendered "$src" "$dst" || { echo "  FAILED   $dst"; failed=$((failed + 1)); }
    fi
  fi
done <<EOF
$PAIRS
EOF

echo
echo "$changed file(s) would change."
if [ "$failed" -gt 0 ]; then
  echo "$failed file(s) FAILED to write." >&2
  exit 1
fi
if [ "$APPLY" -eq 1 ]; then
  echo "Applied. Restart your coding agent so the rule imports and skill list reload."
else
  echo "Nothing written. Re-run with --apply to install."
fi
