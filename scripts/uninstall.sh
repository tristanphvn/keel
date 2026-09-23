#!/usr/bin/env bash
# Remove what scripts/install.sh installed — and nothing else.
#
#   AGENT_HOME=~/.your-agent bash scripts/uninstall.sh                  # dry run, full removal
#   AGENT_HOME=~/.your-agent bash scripts/uninstall.sh --apply          # removes
#   AGENT_HOME=~/.your-agent bash scripts/uninstall.sh --stale          # dry run, only files the repo no longer ships
#   AGENT_HOME=~/.your-agent bash scripts/uninstall.sh --stale --apply
#   AGENT_HOME=~/.your-agent bash scripts/uninstall.sh --force --apply  # also remove locally MODIFIED installed files
#
# Ownership comes from $AGENT_HOME/.agent-skills/manifest.tsv, written by the
# installer: absolute path plus the sha256 of the content as installed.
#
# Two things are never removed:
#   * a path absent from the manifest — this installer did not create it;
#   * a manifest path whose content has changed since install — the user edited
#     it. It is reported and kept, unless --force says otherwise.
#
# The runtime integration lives in the adapters, not here: $AGENT_HOME/CLAUDE.md,
# settings.json and hooks are machine-owned. Use `adapters/<runtime>.sh --remove`
# for the managed block before or after this script.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/scripts/lib/common.sh"

as_preflight find cp rm mv mkdir date basename dirname || exit 1

DEST="${AGENT_HOME:-$HOME/.agent}"
SKILLS_DEST="${AGENT_SKILLS_DIR:-$DEST/skills}"
MANIFEST_DIR="$DEST/.agent-skills"
MANIFEST="$MANIFEST_DIR/manifest.tsv"

APPLY=0; ONLY_STALE=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --stale) ONLY_STALE=1 ;;
    --force) FORCE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

echo "destination: $DEST"
echo "manifest:    $MANIFEST"
[ "$ONLY_STALE" -eq 1 ] && echo "scope:       stale entries only" || echo "scope:       every installed file"
[ "$APPLY" -eq 1 ] && echo "mode:        APPLY" || echo "mode:        DRY RUN (pass --apply to remove)"
echo

if [ ! -f "$MANIFEST" ]; then
  echo "FATAL: no manifest at $MANIFEST." >&2
  echo "Nothing here can be proven to belong to this installer, so nothing is removed." >&2
  echo "If this configuration predates manifests, re-run scripts/install.sh --apply first." >&2
  exit 1
fi

# The set the repo currently ships, computed the same way install.sh does, so
# --stale means exactly "installed once, not shipped any more".
PAIRS="
rules|rules
skills|skills
registry|skill-registry
commands|commands
roles|roles
contracts|contracts
config/AGENTS.md|AGENTS.md
config/learned-rules.md|learned-rules.md
"
resolve_dst() {
  if [ "$1" = "skills" ]; then printf '%s' "$SKILLS_DEST"; else printf '%s/%s' "$DEST" "$1"; fi
}
CURRENT=""
while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  src="$ROOT/${pair%%|*}"
  dst="$(resolve_dst "${pair#*|}")"
  [ -e "$src" ] || continue
  if [ -d "$src" ]; then
    while IFS= read -r f; do
      CURRENT="$CURRENT$dst/${f#"$src"/}
"
    done < <(find "$src" -type f)
  else
    CURRENT="$CURRENT$dst
"
  fi
done <<EOF
$PAIRS
EOF

# --- classify every manifest entry -------------------------------------------
to_remove=""; n_remove=0; n_modified=0; n_gone=0; n_kept_current=0
while IFS="$(printf '\t')" read -r path hash; do
  [ -z "${path:-}" ] && continue
  if [ ! -e "$path" ]; then n_gone=$((n_gone + 1)); continue; fi
  if [ "$ONLY_STALE" -eq 1 ] && printf '%s\n' "$CURRENT" | grep -qxF "$path"; then
    n_kept_current=$((n_kept_current + 1)); continue
  fi
  now="$(as_sha256 "$path")"
  if [ -n "$hash" ] && [ -n "$now" ] && [ "$now" != "$hash" ]; then
    n_modified=$((n_modified + 1))
    if [ "$FORCE" -eq 1 ]; then
      echo "  REMOVE (modified, --force) $path"
      to_remove="$to_remove$path
"; n_remove=$((n_remove + 1))
    else
      echo "  KEPT (modified since install) $path"
    fi
    continue
  fi
  echo "  REMOVE   $path"
  to_remove="$to_remove$path
"; n_remove=$((n_remove + 1))
done < "$MANIFEST"

echo
echo "$n_remove file(s) to remove; $n_modified modified; $n_gone already absent; $n_kept_current still shipped (kept)."

if [ "$APPLY" -ne 1 ]; then
  echo
  echo "Nothing removed. Re-run with --apply."
  exit 0
fi
if [ "$n_remove" -eq 0 ]; then
  echo
  echo "Nothing to remove."
  exit 0
fi

# --- verified backup before deleting -----------------------------------------
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$DEST/backups/uninstall-$stamp"
mkdir -p "$backup" || as_die "cannot create backup directory $backup"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rel="${p#"$DEST"/}"
  # A skills tree installed outside $AGENT_HOME keeps its full shape under
  # external/, so two files named SKILL.md cannot collide in the backup.
  [ "$rel" = "$p" ] && rel="external/$(printf '%s' "$p" | sed -e 's|^/||' -e 's|:|_|g')"
  mkdir -p "$backup/$(dirname "$rel")" || as_die "cannot create backup path for $p"
  cp -p "$p" "$backup/$rel" || as_die "backup of $p failed"
  [ "$(as_sha256 "$p")" = "$(as_sha256 "$backup/$rel")" ] || as_die "backup of $p did not verify"
done <<EOF
$to_remove
EOF
echo "backup:      $backup (verified)"

failed=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  rm -f "$p" || { echo "  FAILED to remove $p" >&2; failed=$((failed + 1)); }
done <<EOF
$to_remove
EOF

# Directories this installer created are removed only when empty, so a
# machine-only file left inside one keeps its directory alive.
for d in "$DEST/rules" "$DEST/skill-registry" "$DEST/commands" "$DEST/roles" "$DEST/contracts" "$SKILLS_DEST"; do
  [ -d "$d" ] || continue
  find "$d" -depth -type d -empty -exec rmdir {} + 2>/dev/null
done

# Rewrite the manifest so it lists only what is still installed.
if [ "$ONLY_STALE" -eq 1 ] || [ "$n_modified" -gt 0 ]; then
  tmp="$MANIFEST.tmp.$$"
  : > "$tmp"
  while IFS="$(printf '\t')" read -r path hash; do
    [ -z "${path:-}" ] && continue
    [ -e "$path" ] || continue
    printf '%s\t%s\n' "$path" "$hash" >> "$tmp"
  done < "$MANIFEST"
  mv -f "$tmp" "$MANIFEST" || as_die "cannot rewrite $MANIFEST"
  echo "manifest:    rewritten, $(grep -c . "$MANIFEST") entry(ies) remain"
else
  rm -f "$MANIFEST"
  rmdir "$MANIFEST_DIR" 2>/dev/null
  echo "manifest:    removed (nothing installed remains)"
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed file(s) could not be removed." >&2
  exit 1
fi
echo "Removed $n_remove file(s). Backup kept at $backup."
[ "$n_modified" -gt 0 ] && [ "$FORCE" -ne 1 ] && echo "$n_modified locally modified file(s) were kept; re-run with --force to remove them too."
echo "The runtime integration block, if any, is removed separately: scripts/adapters/<runtime>.sh --remove --apply"
exit 0
