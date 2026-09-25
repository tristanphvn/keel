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
#
# Every file written is recorded, with its hash, in $AGENT_HOME/.agent-skills/manifest.tsv.
# scripts/uninstall.sh removes only what that manifest proves this installer put
# there, and only while the file is still byte-identical to what was installed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/scripts/lib/common.sh"

# Verify the toolchain before touching anything: a missing `diff` must not be
# discovered after the backup step has already copied half the tree.
as_preflight sed awk paste tr find cmp diff cp mv mkdir rm date basename dirname || exit 1

# One native spelling per location (see as_native_path): the manifest, the
# rendered {{AGENT_HOME}} token and every lookup then agree whichever spelling
# of the same directory the caller passed in.
DEST="$(as_native_path "${AGENT_HOME:-$HOME/.agent}")"
# The skills tree can be installed somewhere other than $AGENT_HOME/skills, for a
# machine where that directory is already owned by something else (a separate
# checkout, for instance). The runtime still has to SEE them at its own skills
# path — an adapter links them into place. {{AGENT_HOME}} still renders to $DEST,
# because the tokens inside skills point at rules/, skill-registry/ and logs/.
SKILLS_DEST="$(as_native_path "${AGENT_SKILLS_DIR:-$DEST/skills}")"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# repo path | destination path RELATIVE to $DEST.
# The destination is kept relative on purpose: $DEST is never word-split, so a
# configuration directory containing spaces installs correctly.
# roles/ and contracts/ are installed because role profiles reference skills by
# repository-relative path: those references have to stay resolvable on the
# machine, not only in the checkout.
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

# --- ownership manifest ------------------------------------------------------
# One tab-separated line per installed file: absolute path, then the sha256 of
# the content as written. The uninstaller trusts nothing else: a path absent
# here was not put there by this installer, and a path whose hash no longer
# matches has been edited by the user since.
MANIFEST_DIR="$DEST/.agent-skills"
MANIFEST="$MANIFEST_DIR/manifest.tsv"
MANIFEST_TMP="$MANIFEST_DIR/manifest.tsv.tmp.$$"
# Previous entries as "native<TAB>key<TAB>hash". Lookups go by key, so an entry
# recorded under another spelling of the same path is still recognised as ours.
PREV_ROWS="$(as_manifest_rows "$MANIFEST")"
INSTALLED_PATHS=""

record() { INSTALLED_PATHS="$INSTALLED_PATHS$1
"; }

# The hash recorded for a path on the previous run, or non-zero if this
# installer never wrote it.
prev_digest() {
  [ -n "$PREV_ROWS" ] || return 1
  printf '%s\n' "$PREV_ROWS" | awk -F'\t' -v p="$1" -v ci="$AS_WINPATH" '
    BEGIN { if (ci == 1) p = tolower(p) }
    $2 == p { print $3; found = 1; exit } END { exit !found }'
}

# Every file this run would install, as "<source>\t<destination>". This mirrors
# the mapping the write loop performs; the two have to change together.
each_target() {
  while IFS= read -r _pair; do
    [ -z "$_pair" ] && continue
    _psrc="$ROOT/${_pair%%|*}"
    _pdst="$(resolve_dst "${_pair#*|}")"
    [ -e "$_psrc" ] || continue
    # A symlinked destination is refused wholesale below; do not report its
    # contents a second time here.
    [ -L "$_pdst" ] && continue
    if [ -d "$_psrc" ]; then
      while IFS= read -r _f; do
        printf '%s\t%s\n' "$_f" "$_pdst/${_f#"$_psrc"/}"
      done < <(find "$_psrc" -type f)
    else
      printf '%s\t%s\n' "$_psrc" "$_pdst"
    fi
  done <<EOF
$PAIRS
EOF
}

echo "repo:        $ROOT"
echo "destination: $DEST"
[ "$SKILLS_DEST" = "$DEST/skills" ] || echo "skills:      $SKILLS_DEST (AGENT_SKILLS_DIR override)"
[ "$APPLY" -eq 1 ] && echo "mode:        APPLY" || echo "mode:        DRY RUN (pass --apply to write)"
echo

# --- ownership preflight -----------------------------------------------------
# The manifest records what this installer wrote and the hash it wrote. The
# uninstaller already trusts exactly that: it removes a file only while it is
# still byte-identical to what was installed, and reports anything else as
# KEPT (modified since install). The installer did not. It compared the
# destination against the rendered source and overwrote whenever the two
# differed, so "the user edited this file" and "the repo moved on" were
# indistinguishable, and a local customization was silently replaced. The hash
# needed to tell them apart was written on every run and then loaded with
# `cut -f1`, which discarded it.
#
# This is conflict protection, not transactional atomicity. It refuses before
# the first write; it does not make the write loop itself crash-safe. A failure
# part-way through still leaves a partially updated tree, and the verified
# backup below is what covers that.
conflicts=0
while IFS="$(printf '\t')" read -r psrc pdst; do
  [ -z "$pdst" ] && continue
  [ -f "$pdst" ] || continue
  # This run would not change the bytes, so there is nothing to lose.
  render "$psrc" | cmp -s - "$pdst" && continue
  # Absent from the manifest: this installer never wrote it. Reported by the
  # write loop rather than blocked here — the verified backup covers it, and
  # refusing would break a first install onto a machine that already has files
  # of its own at these paths.
  prev_recorded="$(prev_digest "$pdst")" || continue
  [ "$(as_sha256 "$pdst")" = "$prev_recorded" ] && continue
  echo "  CONFLICT (edited since installed, would be overwritten) $pdst"
  conflicts=$((conflicts + 1))
done < <(each_target)

if [ "$conflicts" -gt 0 ]; then
  echo
  echo "$conflicts installed file(s) carry local edits this run would replace." >&2
  echo "Nothing was written, no backup was taken, and the manifest is unchanged." >&2
  echo "Save the edits elsewhere or restore the file, then re-run." >&2
  exit 1
fi

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
        # The preflight cleared every file it recognises, so anything still
        # differing here is either this installer's own output moving forward
        # or a file it never wrote. Say which.
        if prev_digest "$target" >/dev/null; then
          echo "  OVERWRITE $target"
        else
          echo "  OVERWRITE (not recorded by this installer) $target"
        fi
        changed=$((changed + 1))
      fi
      if [ "$APPLY" -eq 1 ]; then
        write_rendered "$f" "$target" || { echo "  FAILED   $target"; failed=$((failed + 1)); }
      fi
      record "$target"
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
    record "$dst"
  fi
done <<EOF
$PAIRS
EOF

# A file this installer owned on a previous run, which the repo no longer ships
# (a renamed skill, a deleted rule). It is never deleted here — the uninstaller
# is the only thing that removes, and only on request.
stale=0
if [ -n "$PREV_ROWS" ]; then
  INSTALLED_KEYS="$(printf '%s' "$INSTALLED_PATHS" | as_path_keys)"
  while IFS="$(printf '\t')" read -r p key _hash; do
    [ -z "$p" ] && continue
    printf '%s\n' "$INSTALLED_KEYS" | grep -qxF "$key" && continue
    [ -e "$p" ] || continue
    echo "  STALE (installed previously, no longer in repo) $p"
    stale=$((stale + 1))
  done <<EOF
$PREV_ROWS
EOF
fi

if [ "$APPLY" -eq 1 ] && [ "$failed" -eq 0 ]; then
  mkdir -p "$MANIFEST_DIR" || { echo "FATAL: cannot create $MANIFEST_DIR" >&2; exit 1; }
  : > "$MANIFEST_TMP" || { echo "FATAL: cannot write $MANIFEST_TMP" >&2; exit 1; }
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    printf '%s\t%s\n' "$p" "$(as_sha256 "$p")" >> "$MANIFEST_TMP"
  done <<EOF
$INSTALLED_PATHS
EOF
  mv -f "$MANIFEST_TMP" "$MANIFEST" || { echo "FATAL: cannot update $MANIFEST" >&2; exit 1; }
fi

echo
if [ "$APPLY" -eq 1 ]; then
  echo "$changed file(s) changed."
else
  echo "$changed file(s) would change."
fi
[ "$stale" -gt 0 ] && echo "$stale stale file(s) from an earlier install — remove with scripts/uninstall.sh --stale --apply."
if [ "$failed" -gt 0 ]; then
  echo "$failed file(s) FAILED to write." >&2
  exit 1
fi
if [ "$APPLY" -eq 1 ]; then
  echo "manifest:    $MANIFEST"
  echo "Applied. Restart your coding agent so the rule imports and skill list reload."
else
  echo "Nothing written. Re-run with --apply to install."
fi
