#!/usr/bin/env bash
# Claude Code adapter: integrate the shared configuration with a Claude Code
# config directory (repo -> machine). Run AFTER scripts/install.sh.
#
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh            # dry run
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --apply    # writes, after backing up
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --check    # verify an existing install
#   AGENT_HOME=~/.claude bash scripts/adapters/claude.sh --remove   # take the block back out
#
# Claude Code auto-loads $AGENT_HOME/rules/*.md, so the rules need no imports.
# The only thing this adapter writes is a marker-delimited block inside
# $AGENT_HOME/CLAUDE.md — everything the user wrote there is preserved.
# See config/claude/README.md for the measurements behind that.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${AGENT_HOME:-$HOME/.agent}"
BLOCK_SRC="$ROOT/config/claude/CLAUDE.md.block"
TARGET="$DEST/CLAUDE.md"
BEGIN='<!-- agent-skills:begin -->'
END='<!-- agent-skills:end -->'

# Flags compose: --remove --apply actually removes; --remove alone previews.
APPLY=0
ACTION=install
for arg in "$@"; do
  case "$arg" in
    --apply)  APPLY=1 ;;
    --check)  ACTION=check ;;
    --remove) ACTION=remove ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done
if [ "$ACTION" = check ]; then MODE=check
elif [ "$APPLY" -eq 1 ]; then MODE="$ACTION (apply)"
else MODE="$ACTION (dry run — pass --apply to write)"
fi

fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

echo "repo:        $ROOT"
echo "destination: $DEST"
echo "mode:        $MODE"
echo

[ -f "$BLOCK_SRC" ] || { echo "FATAL: missing $BLOCK_SRC" >&2; exit 1; }

DEST_ESC="$(printf '%s' "$DEST" | sed -e 's/[\\&|]/\\&/g')"
render_block() { LC_ALL=C sed "s|{{AGENT_HOME}}|$DEST_ESC|g" "$BLOCK_SRC"; }

if [ "$ACTION" = check ]; then
  echo "== Claude Code integration =="
  [ -d "$DEST/rules" ] && ok "$DEST/rules exists (auto-loaded by Claude Code)" \
                       || bad "$DEST/rules missing — run scripts/install.sh --apply first"
  n_rules=$(find "$DEST/rules" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c . || true)
  [ "${n_rules:-0}" -gt 0 ] && ok "$n_rules rule file(s) installed" || bad "no rule files in $DEST/rules"

  # Skills must be flat: Claude Code does not recurse past <name>/SKILL.md.
  n_flat=$(find "$DEST/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | grep -c . || true)
  n_deep=$(find "$DEST/skills" -mindepth 3 -name SKILL.md 2>/dev/null | grep -c . || true)
  [ "${n_flat:-0}" -gt 0 ] && ok "$n_flat skill(s) at the discoverable depth" || bad "no skills found at $DEST/skills/<name>/SKILL.md"
  [ "${n_deep:-0}" -gt 0 ] && echo "  note  $n_deep SKILL.md deeper than one level — Claude Code will not discover those"

  if [ -f "$TARGET" ]; then
    if grep -qF "$BEGIN" "$TARGET"; then ok "managed block present in $TARGET"; else bad "managed block absent from $TARGET"; fi
    if grep -qE '^@.*/rules/' "$TARGET"; then
      bad "$TARGET imports rules/ explicitly — they already auto-load, so each rule loads twice"
    else
      ok "no duplicate rule imports in $TARGET"
    fi
  else
    bad "$TARGET does not exist"
  fi

  # Unresolved placeholders anywhere the installer wrote.
  leftover=$(grep -rlF '{{AGENT_HOME}}' "$DEST/rules" "$DEST/skills" "$DEST/skill-registry" "$DEST/commands" "$TARGET" 2>/dev/null | grep -c . || true)
  [ "${leftover:-0}" -eq 0 ] && ok "no unresolved {{AGENT_HOME}} placeholders" || bad "$leftover installed file(s) still contain {{AGENT_HOME}}"

  echo
  [ "$fail" -eq 0 ] && { echo "ADAPTER CHECK: PASS"; exit 0; } || { echo "ADAPTER CHECK: FAIL ($fail problem(s))"; exit "$fail"; }
fi

if [ ! -f "$TARGET" ]; then
  echo "  $TARGET does not exist yet; it will be created with the managed block only."
  existing=""
else
  existing="$(cat "$TARGET")"
fi

has_block=0
printf '%s\n' "$existing" | grep -qF "$BEGIN" && has_block=1

# Build the new content: replace between markers if present, else append.
tmp="$(mktemp)"; trap 'rm -f "$tmp" "$tmp.blk"' EXIT
if [ "$ACTION" = remove ]; then
  if [ "$has_block" -eq 0 ]; then
    echo "  managed block not present; nothing to remove."
    exit 0
  fi
  printf '%s\n' "$existing" | awk -v b="$BEGIN" -v e="$END" '
    index($0,b) {skip=1; next} index($0,e) {skip=0; next} !skip {print}' > "$tmp"
  # collapse runs of blank lines, then drop any trailing blank the block left behind,
  # so --remove restores the file byte-for-byte.
  awk 'BEGIN{n=0} /^$/{n++; if(n>1) next} !/^$/{n=0} {print}' "$tmp" > "$tmp.blk" && mv "$tmp.blk" "$tmp"
  awk 'NF {last=NR} {line[NR]=$0} END {for (i=1; i<=last; i++) print line[i]}' "$tmp" > "$tmp.blk" && mv "$tmp.blk" "$tmp"
  action="REMOVE block from"
else
  render_block > "$tmp.blk"
  if [ "$has_block" -eq 1 ]; then
    printf '%s\n' "$existing" | awk -v b="$BEGIN" -v e="$END" -v f="$tmp.blk" '
      index($0,b) {skip=1; while ((getline line < f) > 0) print line; close(f); next}
      index($0,e) {skip=0; next}
      !skip {print}' > "$tmp"
    action="UPDATE block in"
  else
    { [ -n "$existing" ] && { printf '%s\n' "$existing"; echo; }; cat "$tmp.blk"; } > "$tmp"
    action="APPEND block to"
  fi
fi

if cmp -s "$tmp" "$TARGET" 2>/dev/null; then
  echo "  unchanged: $TARGET already matches (idempotent)."
  echo
  echo "Nothing to do."
  exit 0
fi

echo "  $action $TARGET"
if [ "$APPLY" -ne 1 ]; then
  echo
  echo "--- proposed diff ---"
  diff -u "$TARGET" "$tmp" 2>/dev/null | sed 's/^/  /' || true
  echo
  echo "Nothing written. Re-run with --apply to write."
  exit 0
fi

# Back up the real file and verify the copy before replacing it.
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$DEST/backups/claude-adapter-$stamp"
mkdir -p "$backup" || { echo "FATAL: cannot create $backup" >&2; exit 1; }
if [ -f "$TARGET" ]; then
  cp -p "$TARGET" "$backup/CLAUDE.md" || { echo "FATAL: backup failed" >&2; exit 1; }
  cmp -s "$TARGET" "$backup/CLAUDE.md" || { echo "FATAL: backup did not verify" >&2; exit 1; }
  echo "  backup:  $backup/CLAUDE.md (verified)"
fi

mv -f "$tmp" "$TARGET" || { echo "FATAL: write failed" >&2; exit 1; }
trap - EXIT; rm -f "$tmp.blk"
echo "  written: $TARGET"
echo
echo "Applied. Restart Claude Code, then: bash scripts/adapters/claude.sh --check"
